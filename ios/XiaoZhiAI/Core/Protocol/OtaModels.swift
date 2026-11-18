import Foundation

struct OtaDeviceReportRequest: Encodable, Equatable, Sendable {
    let application: Application
    let board: Board

    struct Application: Encodable, Equatable, Sendable {
        let version: String
        let elfSha256: String

        enum CodingKeys: String, CodingKey {
            case version
            case elfSha256 = "elf_sha256"
        }
    }

    struct Board: Encodable, Equatable, Sendable {
        let type: String
        let name: String
        let ssid: String
        let rssi: Int
        let channel: Int
        let ip: String
        let mac: String
    }
}

struct OtaResponse: Decodable, Equatable, Sendable {
    let serverTime: ServerTime
    let activation: Activation?
    let firmware: Firmware
    let websocket: WebSocket

    enum CodingKeys: String, CodingKey {
        case serverTime = "server_time"
        case activation
        case firmware
        case websocket
    }

    struct ServerTime: Decodable, Equatable, Sendable {
        let timestamp: Int64
        let timeZone: String?
        let timezoneOffset: Int

        enum CodingKeys: String, CodingKey {
            case timestamp
            case timeZone
            case timezoneOffset = "timezone_offset"
        }
    }

    struct Activation: Decodable, Equatable, Sendable {
        let code: String
        let message: String
        let challenge: String
    }

    struct Firmware: Decodable, Equatable, Sendable {
        let version: String
        let url: String
    }

    struct WebSocket: Decodable, Equatable, Sendable {
        let url: String
        let token: String?
    }
}

