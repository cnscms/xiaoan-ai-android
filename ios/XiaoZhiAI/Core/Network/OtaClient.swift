import Foundation

struct OtaClient {
    enum OtaError: LocalizedError {
        case invalidURL
        case invalidHTTPResponse
        case server(statusCode: Int, body: String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "OTA 地址无效"
            case .invalidHTTPResponse:
                return "OTA 服务返回了无效响应"
            case let .server(statusCode, body):
                return "OTA 服务返回 HTTP \(statusCode): \(body)"
            }
        }
    }

    var session: URLSession = .shared
    var appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"

    func fetch(config: AppConfig) async throws -> OtaResponse {
        guard let url = config.otaURL else {
            throw OtaError.invalidURL
        }

        let report = OtaDeviceReportRequest(
            application: .init(version: appVersion, elfSha256: ""),
            board: .init(
                type: "wifi",
                name: "xiaozhi-ios",
                ssid: "iOS",
                rssi: -55,
                channel: 0,
                ip: "0.0.0.0",
                mac: config.deviceID
            )
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.httpBody = try XiaozhiJSON.encode(report)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.clientID, forHTTPHeaderField: "Client-Id")
        request.setValue(config.deviceID, forHTTPHeaderField: "Device-Id")
        if !config.token.isEmpty {
            request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OtaError.invalidHTTPResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OtaError.server(
                statusCode: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
        return try JSONDecoder().decode(OtaResponse.self, from: data)
    }
}
