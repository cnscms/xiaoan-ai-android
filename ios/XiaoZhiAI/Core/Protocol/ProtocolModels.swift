import Foundation

struct AudioParameters: Codable, Equatable, Sendable {
    let format: String
    let sampleRate: Int
    let channels: Int
    let frameDuration: Int

    static let opus16k60ms = AudioParameters(
        format: "opus",
        sampleRate: 16_000,
        channels: 1,
        frameDuration: 60
    )

    enum CodingKeys: String, CodingKey {
        case format
        case sampleRate = "sample_rate"
        case channels
        case frameDuration = "frame_duration"
    }
}

struct HelloRequest: Codable, Equatable, Sendable {
    let type = "hello"
    let version = 1
    let transport = "websocket"
    let audioParameters: AudioParameters

    enum CodingKeys: String, CodingKey {
        case type
        case version
        case transport
        case audioParameters = "audio_params"
    }
}

enum ListenState: String, Codable, Sendable {
    case start
    case stop
    case detect
}

enum ListenMode: String, Codable, Sendable {
    case auto
    case manual
    case realtime
}

struct ListenCommand: Encodable, Equatable, Sendable {
    let sessionID: String?
    let type = "listen"
    let state: ListenState
    let mode: ListenMode?
    let text: String?
    let source: String?

    static func start(sessionID: String?, mode: ListenMode = .auto) -> ListenCommand {
        ListenCommand(
            sessionID: sessionID,
            state: .start,
            mode: mode,
            text: nil,
            source: nil
        )
    }

    static func stop(sessionID: String?, mode: ListenMode = .auto) -> ListenCommand {
        ListenCommand(
            sessionID: sessionID,
            state: .stop,
            mode: mode,
            text: nil,
            source: nil
        )
    }

    static func detect(sessionID: String?, text: String) -> ListenCommand {
        ListenCommand(
            sessionID: sessionID,
            state: .detect,
            mode: nil,
            text: text,
            source: "text"
        )
    }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case type
        case state
        case mode
        case text
        case source
    }
}

struct AbortCommand: Encodable, Equatable, Sendable {
    let sessionID: String?
    let type = "abort"
    let reason: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case type
        case reason
    }
}

struct ServerEvent: Decodable, Equatable, Sendable {
    let type: String
    let version: Int?
    let transport: String?
    let sessionID: String?
    let state: String?
    let text: String?
    let emotion: String?
    let source: String?
    let audioParameters: AudioParameters?

    var isHello: Bool {
        type == "hello" && transport == "websocket"
    }

    enum CodingKeys: String, CodingKey {
        case type
        case version
        case transport
        case sessionID = "session_id"
        case state
        case text
        case emotion
        case source
        case audioParameters = "audio_params"
    }
}

enum XiaozhiJSON {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    static func decodeServerEvent(_ data: Data) throws -> ServerEvent {
        try JSONDecoder().decode(ServerEvent.self, from: data)
    }
}

