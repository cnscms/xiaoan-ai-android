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

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable, Equatable {
        case user
        case assistant
        case system
    }

    let id: UUID
    let role: Role
    var content: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

struct VideoRequest: Identifiable, Equatable {
    let id: UUID
    let name: String
    let url: String

    init(id: UUID = UUID(), name: String, url: String) {
        self.id = id
        self.name = name
        self.url = url
    }
}

@MainActor
final class ConversationStore: ObservableObject {
    @Published private(set) var state: ConversationState = .idle
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var sessionID: String?
    @Published var activationCode: String?
    @Published var errorMessage: String?
    @Published private(set) var videoRequest: VideoRequest?

    let configStore: AppConfigStore
    let privacyVault: PrivacyVaultStore

    private let otaClient: OtaClient
    private let socket: XiaozhiWebSocketClient
    private let audioManager = XiaoZhiAudioManager()
    private let defaults: UserDefaults
    private let historyStorageKey = "xiaoan.chat.history.v1"
    private let historyLimit = 100
    private var eventTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    private var videoTask: Task<Void, Never>?

    init(
        configStore: AppConfigStore,
        otaClient: OtaClient = OtaClient(),
        socket: XiaozhiWebSocketClient = XiaozhiWebSocketClient(),
        defaults: UserDefaults = .standard,
        privacyVault: PrivacyVaultStore
    ) {
        self.configStore = configStore
        self.otaClient = otaClient
        self.socket = socket
        self.defaults = defaults
        self.privacyVault = privacyVault
        Self.migrateLegacyHistory(
            defaults: defaults,
            key: "xiaoan.chat.history.v1",
            privacyVault: privacyVault
        )
        ensureEventTask()
    }

    var isConnected: Bool {
        sessionID != nil
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
        dismissVideo()
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
            appendMessage(ChatMessage(role: .user, content: value))
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

    func abortSpeaking() {
        audioManager.stopCapture()
        audioManager.stopPlayback()
        state = .connected
        guard !sessionID.isNilOrEmpty else {
            return
        }
        Task {
            do {
                try await socket.send(
                    AbortCommand(sessionID: sessionID, reason: "user_interrupt")
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func dismissVideo() {
        videoTask?.cancel()
        videoTask = nil
        videoRequest = nil
    }

    func clearHistory() {
        messages.removeAll()
        defaults.removeObject(forKey: historyStorageKey)
        do {
            try privacyVault.clearChatHistory()
        } catch {
            errorMessage = "清空隐私保险箱失败：\(error.localizedDescription)"
        }
    }

    private func connectFlow() async {
        let config = configStore.config
        var resolvedConfig = config

        if config.otaURL != nil {
            do {
                let ota = try await otaClient.fetch(config: config)
                let websocketURL = ota.websocket.url
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !websocketURL.isEmpty {
                    resolvedConfig.websocketURLString = websocketURL
                }
                if let token = ota.websocket.token, !token.isEmpty {
                    resolvedConfig.token = token
                }
                configStore.save(resolvedConfig)

                if let activation = ota.activation, !activation.code.isEmpty {
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
                self.handle(event)
            }
        }
    }

    private func handle(_ event: XiaozhiWebSocketClient.Event) {
        switch event {
        case let .state(connection):
            switch connection {
            case .disconnected:
                dismissVideo()
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
                dismissVideo()
                audioManager.stopCapture()
                audioManager.stopPlayback()
                state = .failed(message)
                errorMessage = message
            }

        case let .text(event):
            handleServerEvent(event)

        case let .binary(data):
            if videoRequest != nil || videoTask != nil {
                return
            }
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
                appendMessage(ChatMessage(role: .user, content: text))
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

        case "video":
            handleVideoEvent(event)

        default:
            break
        }
    }

    private func handleVideoEvent(_ event: ServerEvent) {
        if event.action == "stop" {
            dismissVideo()
            return
        }
        let value = event.url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            errorMessage = "服务端下发的视频地址无效"
            return
        }

        audioManager.stopCapture()
        audioManager.stopPlayback()
        let trimmedName = event.name?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let request = VideoRequest(
            name: trimmedName.isEmpty ? "视频" : trimmedName,
            url: value
        )
        let delay = min(max(event.startDelayMs ?? 900, 0), 5_000)

        videoTask?.cancel()
        videoTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else {
                return
            }
            self.videoRequest = request
            self.videoTask = nil
        }
    }

    private func mergeAssistantText(_ text: String) {
        if messages.last?.role == .assistant {
            messages[messages.count - 1].content = text
            if let message = messages.last {
                persistEncryptedMessage(message)
            }
        } else {
            appendMessage(ChatMessage(role: .assistant, content: text))
        }
    }

    private func handleAudioError(_ error: Error) {
        audioManager.stopCapture()
        audioManager.stopPlayback()
        state = .failed(error.localizedDescription)
        errorMessage = error.localizedDescription
    }

    private func appendMessage(_ message: ChatMessage) {
        messages.append(message)
        if messages.count > historyLimit {
            messages.removeFirst(messages.count - historyLimit)
        }
        persistEncryptedMessage(message)
    }

    private func persistEncryptedMessage(_ message: ChatMessage) {
        do {
            try privacyVault.upsertChatMessage(message)
        } catch {
            errorMessage = "历史消息加密保存失败：\(error.localizedDescription)"
        }
    }

    private static func migrateLegacyHistory(
        defaults: UserDefaults,
        key: String,
        privacyVault: PrivacyVaultStore
    ) {
        guard let data = defaults.data(forKey: key) else {
            return
        }
        guard let decoded = try? JSONDecoder().decode([ChatMessage].self, from: data) else {
            defaults.removeObject(forKey: key)
            return
        }
        do {
            for message in decoded.suffix(100) {
                try privacyVault.upsertChatMessage(message)
            }
            defaults.removeObject(forKey: key)
        } catch {
            // Keep the legacy file so a later launch can retry the migration.
        }
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        self?.isEmpty != false
    }
}

