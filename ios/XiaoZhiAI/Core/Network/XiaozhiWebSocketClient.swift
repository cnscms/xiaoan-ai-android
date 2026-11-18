import Foundation

actor XiaozhiWebSocketClient {
    enum ConnectionState: Sendable, Equatable {
        case disconnected
        case connecting
        case connected(sessionID: String)
        case failed(String)
    }

    enum Event: Sendable {
        case state(ConnectionState)
        case text(ServerEvent)
        case binary(Data)
        case protocolError(String)
    }

    enum ClientError: LocalizedError {
        case invalidURL
        case notConnected

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "WebSocket 地址无效"
            case .notConnected:
                return "WebSocket 尚未连接"
            }
        }
    }

    nonisolated let events: AsyncStream<Event>

    private let eventContinuation: AsyncStream<Event>.Continuation
    private let session: URLSession
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var generation = 0
    private var sessionID: String?

    init(session: URLSession = .shared) {
        self.session = session
        let pair = AsyncStream<Event>.makeStream(
            bufferingPolicy: .bufferingNewest(256)
        )
        events = pair.stream
        eventContinuation = pair.continuation
    }

    func connect(config: AppConfig) async throws {
        guard let url = config.websocketURL else {
            throw ClientError.invalidURL
        }

        disconnect()
        generation += 1
        let activeGeneration = generation

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(config.deviceID, forHTTPHeaderField: "Device-Id")
        request.setValue(config.clientID, forHTTPHeaderField: "Client-Id")
        request.setValue("1", forHTTPHeaderField: "Protocol-Version")
        if !config.token.isEmpty {
            request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        }

        let socket = session.webSocketTask(with: request)
        self.socket = socket
        eventContinuation.yield(.state(.connecting))
        socket.resume()

        try await sendHello()
        receiveTask = Task {
            await receiveLoop(generation: activeGeneration)
        }
        pingTask = Task {
            await pingLoop(generation: activeGeneration)
        }
    }

    func sendText(_ text: String) async throws {
        guard let socket else {
            throw ClientError.notConnected
        }
        try await socket.send(.string(text))
    }

    func sendBinary(_ data: Data) async throws {
        guard let socket else {
            throw ClientError.notConnected
        }
        try await socket.send(.data(data))
    }

    func send<T: Encodable>(_ command: T) async throws {
        let data = try XiaozhiJSON.encode(command)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ClientError.notConnected
        }
        try await sendText(text)
    }

    func currentSessionID() -> String? {
        sessionID
    }

    func disconnect() {
        generation += 1
        receiveTask?.cancel()
        pingTask?.cancel()
        receiveTask = nil
        pingTask = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        sessionID = nil
        eventContinuation.yield(.state(.disconnected))
    }

    private func sendHello() async throws {
        try await send(HelloRequest(audioParameters: .opus16k60ms))
    }

    private func receiveLoop(generation activeGeneration: Int) async {
        while !Task.isCancelled {
            guard activeGeneration == generation, let socket else {
                return
            }
            do {
                let message = try await socket.receive()
                guard activeGeneration == generation else {
                    return
                }
                switch message {
                case let .string(text):
                    let data = Data(text.utf8)
                    do {
                        let event = try XiaozhiJSON.decodeServerEvent(data)
                        if event.isHello {
                            sessionID = event.sessionID
                            eventContinuation.yield(
                                .state(.connected(sessionID: event.sessionID ?? ""))
                            )
                        }
                        eventContinuation.yield(.text(event))
                    } catch {
                        eventContinuation.yield(.protocolError(error.localizedDescription))
                    }
                case let .data(data):
                    eventContinuation.yield(.binary(data))
                @unknown default:
                    eventContinuation.yield(.protocolError("不支持的 WebSocket 消息类型"))
                }
            } catch {
                if Task.isCancelled || activeGeneration != generation {
                    return
                }
                eventContinuation.yield(.state(.failed(error.localizedDescription)))
                socket.cancel(with: .goingAway, reason: nil)
                self.socket = nil
                return
            }
        }
    }

    private func pingLoop(generation activeGeneration: Int) async {
        while !Task.isCancelled && activeGeneration == generation {
            do {
                try await Task.sleep(nanoseconds: 25_000_000_000)
            } catch {
                return
            }
            guard activeGeneration == generation, let socket else {
                return
            }
            socket.sendPing { _ in }
        }
    }
}
