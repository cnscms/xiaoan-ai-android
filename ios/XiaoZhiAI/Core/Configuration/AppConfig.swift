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

    var defaultVisionURL: String {
        switch self {
        case .domain:
            return "http://sql.ms48.com:8003/mcp/vision/explain"
        case .lan:
            return "http://192.168.0.20:8003/mcp/vision/explain"
        }
    }

    var defaultVoiceNotesURL: String {
        switch self {
        case .domain:
            return "http://sql.ms48.com:19090"
        case .lan:
            return "http://192.168.0.20:19090"
        }
    }

    var defaultManagementURL: String {
        switch self {
        case .domain:
            return "https://ai.ms48.com"
        case .lan:
            return "http://192.168.0.20:8002"
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

    static var defaultVisionURL: String {
        ServerEnvironment.current.defaultVisionURL
    }

    static var defaultVoiceNotesURL: String {
        ServerEnvironment.current.defaultVoiceNotesURL
    }

    static var defaultManagementURL: String {
        ServerEnvironment.current.defaultManagementURL
    }

    var displayName: String
    var otaURLString: String
    var websocketURLString: String
    var visionURLString: String
    var voiceNotesURLString: String
    var managementURLString: String
    var token: String
    var voiceNotesToken: String
    var clientID: String
    var deviceID: String
    var mcpEnabled: Bool
    var weatherCity: String
    var weatherLatitude: Double
    var weatherLongitude: Double

    init(
        displayName: String = ServerEnvironment.current.displayName,
        otaURLString: String = AppConfig.defaultOTAURL,
        websocketURLString: String = AppConfig.defaultWebSocketURL,
        visionURLString: String = AppConfig.defaultVisionURL,
        voiceNotesURLString: String = AppConfig.defaultVoiceNotesURL,
        managementURLString: String = AppConfig.defaultManagementURL,
        token: String = "",
        voiceNotesToken: String = "",
        clientID: String,
        deviceID: String,
        mcpEnabled: Bool = false,
        weatherCity: String = "眉山",
        weatherLatitude: Double = 30.05,
        weatherLongitude: Double = 103.83
    ) {
        self.displayName = displayName
        self.otaURLString = otaURLString
        self.websocketURLString = websocketURLString
        self.visionURLString = visionURLString
        self.voiceNotesURLString = voiceNotesURLString
        self.managementURLString = managementURLString
        self.token = token
        self.voiceNotesToken = voiceNotesToken
        self.clientID = clientID
        self.deviceID = deviceID
        self.mcpEnabled = mcpEnabled
        self.weatherCity = weatherCity
        self.weatherLatitude = weatherLatitude
        self.weatherLongitude = weatherLongitude
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? ServerEnvironment.current.displayName
        otaURLString = try container.decodeIfPresent(String.self, forKey: .otaURLString)
            ?? AppConfig.defaultOTAURL
        websocketURLString = try container.decodeIfPresent(
            String.self,
            forKey: .websocketURLString
        ) ?? AppConfig.defaultWebSocketURL
        visionURLString = try container.decodeIfPresent(
            String.self,
            forKey: .visionURLString
        ) ?? AppConfig.defaultVisionURL
        voiceNotesURLString = try container.decodeIfPresent(
            String.self,
            forKey: .voiceNotesURLString
        ) ?? AppConfig.defaultVoiceNotesURL
        managementURLString = try container.decodeIfPresent(
            String.self,
            forKey: .managementURLString
        ) ?? AppConfig.defaultManagementURL
        token = try container.decodeIfPresent(String.self, forKey: .token) ?? ""
        voiceNotesToken = try container.decodeIfPresent(
            String.self,
            forKey: .voiceNotesToken
        ) ?? ""
        clientID = try container.decodeIfPresent(String.self, forKey: .clientID) ?? ""
        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID) ?? ""
        mcpEnabled = try container.decodeIfPresent(Bool.self, forKey: .mcpEnabled) ?? false
        weatherCity = try container.decodeIfPresent(String.self, forKey: .weatherCity) ?? "眉山"
        weatherLatitude = try container.decodeIfPresent(
            Double.self,
            forKey: .weatherLatitude
        ) ?? 30.05
        weatherLongitude = try container.decodeIfPresent(
            Double.self,
            forKey: .weatherLongitude
        ) ?? 103.83
    }

    enum CodingKeys: String, CodingKey {
        case displayName
        case otaURLString
        case websocketURLString
        case visionURLString
        case voiceNotesURLString
        case managementURLString
        case token
        case voiceNotesToken
        case clientID
        case deviceID
        case mcpEnabled
        case weatherCity
        case weatherLatitude
        case weatherLongitude
    }

    var otaURL: URL? {
        Self.networkURL(from: otaURLString, schemes: ["http", "https"])
    }

    var websocketURL: URL? {
        Self.networkURL(from: websocketURLString, schemes: ["ws", "wss"])
    }

    var visionURL: URL? {
        Self.networkURL(from: visionURLString, schemes: ["http", "https"])
    }

    var voiceNotesURL: URL? {
        Self.networkURL(from: voiceNotesURLString, schemes: ["http", "https"])
    }

    var managementURL: URL? {
        Self.networkURL(from: managementURLString, schemes: ["http", "https"])
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
        visionURLString = visionURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        voiceNotesURLString = voiceNotesURLString.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        while voiceNotesURLString.hasSuffix("/") {
            voiceNotesURLString.removeLast()
        }
        managementURLString = managementURLString.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        while managementURLString.hasSuffix("/") {
            managementURLString.removeLast()
        }
        token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        voiceNotesToken = voiceNotesToken.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        deviceID = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        weatherCity = weatherCity.trimmingCharacters(in: .whitespacesAndNewlines)
        if weatherCity.isEmpty {
            weatherCity = "眉山"
        }
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

