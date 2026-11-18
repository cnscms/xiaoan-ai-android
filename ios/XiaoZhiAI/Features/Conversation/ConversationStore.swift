import AVFoundation
import Combine
import Foundation

enum ConversationState: Equatable {
    case idle
    case connecting
    case connected
    case listening
    case processing
    case speaking
    case failed(String)
}

struct ChatMessage: Identifiable, Equatable {
    enum Role: Equatable {
        case user
        case assistant
        case system
    }

    let id = UUID()
    let role: Role
    var content: String
}

@MainActor
final class ConversationStore: ObservableObject {
    @Published private(set) var state: ConversationState = .idle
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var sessionID: String?
    @Published var activationCode: String?
    @Published var errorMessage: String?

    let configStore: AppConfigStore

    private let otaClient: OtaClient
    private let socket: XiaozhiWebSocketClient
    private let audioManager = XiaoZhiAudioManager()
    private var eventTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?

    init(
        configStore: AppConfigStore,
        otaClient: OtaClient = OtaClient(),
        socket: XiaozhiWebSocketClient = XiaozhiWebSocketClient()
    ) {
        self.configStore = configStore
        self.otaClient = otaClient
        self.socket = socket
        ensureEventTask()
    }

    func connect() {
        guard connectionTask == nil else {
            return
        }
        errorMessage = nil
        state = .connecting
        connectionTask = Task { [weak self] in
            guard let self else {
                return
            }
            await self.connectFlow()
            self.connectionTask = nil
        }
    }

    func disconnect() {
        connectionTask?.cancel()
        connectionTask = nil
        audioManager.stopCapture()
        audioManager.stopPlayback()
        Task {
            await socket.disconnect()
        }
        sessionID = nil
        state = .idle
    }

    func confirmActivation() {
        activationCode = nil
        startSocket(with: configStore.config)
    }

    func dismissActivation() {
        activationCode = nil
        state = .idle
    }

    func updateConfig(_ config: AppConfig) {
        disconnect()
        configStore.save(config)
        messages.removeAll()
    }

    func sendText(_ text: String) async {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return
        }
        guard !sessionID.isNilOrEmpty else {
            errorMessage = "请先连接服务器"
            return
        }

        do {
            messages.append(ChatMessage(role: .user, content: value))
            state = .processing
            try await socket.send(
                ListenCommand.detect(sessionID: sessionID, text: value)
            )
        } catch {
            state = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func toggleListening() async {
        if state == .listening {
            await stopListening()
        } else {
            await startListening()
        }
    }

    func startListening() async {
        guard !sessionID.isNilOrEmpty else {
            errorMessage = "请先连接服务器"
            return
        }

        let session = AVAudioSession.sharedInstance()
        let granted: Bool
        switch session.recordPermission {
        case .granted:
            granted = true
        case .denied:
            granted = false
        case .undetermined:
            granted = await withCheckedContinuation { continuation in
                XiaoZhiAudioManager.requestMicrophonePermission { value in
                    continuation.resume(returning: value)
                }
            }
        @unknown default:
            granted = false
        }
        guard granted else {
            errorMessage = "麦克风权限未授予，请到系统设置中开启"
            return
        }

        do {
            audioManager.startCapture(
                onPacket: { [weak self] packet in
                    Task { @MainActor [weak self] in
                        guard let self else {
                            return
                        }
                        do {
                            try await self.socket.sendBinary(packet)
                        } catch {
                            self.handleAudioError(error)
                        }
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor in
                        self?.handleAudioError(error)
                    }
                }
            )
            try await socket.send(
                ListenCommand.start(sessionID: sessionID, mode: .auto)
            )
            state = .listening
            errorMessage = nil
        } catch {
            audioManager.stopCapture()
            state = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func stopListening() async {
        audioManager.stopCapture()
        do {
            try await socket.send(
                ListenCommand.stop(sessionID: sessionID, mode: .auto)
            )
            state = .connected
        } catch {
            state = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    private func connectFlow() async {
        let config = configStore.config
        var resolvedConfig = config

        if config.otaURL != nil {
            do {
                let ota = try await otaClient.fetch(config: config)
                resolvedConfig.websocketURLString = ota.websocket.url
                configStore.save(resolvedConfig)

                if let activation = ota.activation {
                    activationCode = activation.code
                    state = .idle
                    return
                }
            } catch {
                errorMessage = "OTA 检查失败，尝试直接连接：\(error.localizedDescription)"
            }
        }

        guard resolvedConfig.websocketURL != nil else {
            state = .failed("WebSocket 地址无效")
            errorMessage = "WebSocket 地址无效"
            return
        }
        startSocket(with: resolvedConfig)
    }

    private func startSocket(with config: AppConfig) {
        Task {
            do {
                try await socket.connect(config: config)
            } catch {
                state = .failed(error.localizedDescription)
                errorMessage = error.localizedDescription
            }
        }
    }

    private func ensureEventTask() {
        guard eventTask == nil else {
            return
        }
        let eventStream = socket.events
        eventTask = Task { [weak self] in
            for await event in eventStream {
                guard let self else {
                    return
                }
                await self.handle(event)
            }
        }
    }

    private func handle(_ event: XiaozhiWebSocketClient.Event) {
        switch event {
        case let .state(connection):
            switch connection {
            case .disconnected:
                audioManager.stopCapture()
                audioManager.stopPlayback()
                sessionID = nil
                if case .failed = state {
                    break
                }
                state = .idle
            case .connecting:
                state = .connecting
            case let .connected(sessionID):
                self.sessionID = sessionID.isEmpty ? nil : sessionID
                state = .connected
                errorMessage = nil
            case let .failed(message):
                audioManager.stopCapture()
                audioManager.stopPlayback()
                state = .failed(message)
                errorMessage = message
            }

        case let .text(event):
            handleServerEvent(event)

        case let .binary(data):
            audioManager.play(data)

        case let .protocolError(message):
            errorMessage = "协议解析失败：\(message)"
        }
    }

    private func handleServerEvent(_ event: ServerEvent) {
        switch event.type {
        case "hello":
            if let session = event.sessionID, !session.isEmpty {
                sessionID = session
            }
            state = .connected

        case "stt":
            if let text = event.text, !text.isEmpty {
                messages.append(ChatMessage(role: .user, content: text))
                state = .processing
            }

        case "llm":
            guard let text = event.text, !text.isEmpty else {
                return
            }
            mergeAssistantText(text)

        case "tts":
            switch event.state {
            case "start":
                audioManager.stopCapture()
                state = .speaking
            case "sentence_start":
                state = .speaking
                if let text = event.text, !text.isEmpty {
                    mergeAssistantText(text)
                }
            case "stop":
                audioManager.stopPlayback()
                state = .connected
            default:
                break
            }

        case "error":
            errorMessage = event.text ?? "服务端返回错误"
            state = .connected

        default:
            break
        }
    }

    private func mergeAssistantText(_ text: String) {
        if messages.last?.role == .assistant {
            messages[messages.count - 1].content = text
        } else {
            messages.append(ChatMessage(role: .assistant, content: text))
        }
    }

    private func handleAudioError(_ error: Error) {
        audioManager.stopCapture()
        audioManager.stopPlayback()
        state = .failed(error.localizedDescription)
        errorMessage = error.localizedDescription
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        self?.isEmpty != false
    }
}

