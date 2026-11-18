import Foundation

enum ServerEnvironment: String {
    case domain
    case lan

    static var current: ServerEnvironment {
        #if XIAOZHI_LAN
        return .lan
        #else
        return .domain
        #endif
    }

    var defaultOTAURL: String {
        switch self {
        case .domain:
            return "http://sql.ms48.com:8002/xiaozhi/ota/"
        case .lan:
            return "http://192.168.0.20:8002/xiaozhi/ota/"
        }
    }

    var defaultWebSocketURL: String {
        switch self {
        case .domain:
            return "ws://sql.ms48.com:8001/xiaozhi/v1/"
        case .lan:
            return "ws://192.168.0.20:8001/xiaozhi/v1/"
        }
    }

    var displayName: String {
        switch self {
        case .domain:
            return "小安"
        case .lan:
            return "小安内网"
        }
    }
}

struct AppConfig: Codable, Equatable {
    static var defaultOTAURL: String {
        ServerEnvironment.current.defaultOTAURL
    }

    static var defaultWebSocketURL: String {
        ServerEnvironment.current.defaultWebSocketURL
    }

    var displayName: String
    var otaURLString: String
    var websocketURLString: String
    var token: String
    var clientID: String
    var deviceID: String
    var mcpEnabled: Bool

    init(
        displayName: String = ServerEnvironment.current.displayName,
        otaURLString: String = AppConfig.defaultOTAURL,
        websocketURLString: String = AppConfig.defaultWebSocketURL,
        token: String = "",
        clientID: String,
        deviceID: String,
        mcpEnabled: Bool = false
    ) {
        self.displayName = displayName
        self.otaURLString = otaURLString
        self.websocketURLString = websocketURLString
        self.token = token
        self.clientID = clientID
        self.deviceID = deviceID
        self.mcpEnabled = mcpEnabled
    }

    var otaURL: URL? {
        Self.networkURL(from: otaURLString, schemes: ["http", "https"])
    }

    var websocketURL: URL? {
        Self.networkURL(from: websocketURLString, schemes: ["ws", "wss"])
    }

    var isComplete: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (otaURL != nil || websocketURL != nil)
            && !deviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    mutating func normalize() {
        displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        otaURLString = otaURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        websocketURLString = websocketURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        deviceID = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func networkURL(from value: String, schemes: Set<String>) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              schemes.contains(scheme),
              url.host != nil else {
            return nil
        }
        return url
    }
}

