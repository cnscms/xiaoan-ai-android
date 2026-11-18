import Foundation

struct VoiceNoteRecord: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let transcript: String
    let tags: String?
    let durationSeconds: Double?
    let createdAt: String

    var createdDate: Date? {
        Self.date(from: createdAt)
    }

    static func date(from value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }
        for format in [
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss"
        ] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }
}

struct VoiceReminderRecord: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let content: String
    let atMs: Int64
    let notifyAtMs: Int64
    let atText: String?
    let remindBefore: Int
    let status: String
    let attempts: Int
    let lastError: String?
    let createdAtMs: Int64

    var atDate: Date {
        Date(timeIntervalSince1970: TimeInterval(atMs) / 1_000)
    }

    var isPending: Bool {
        status == "pending"
    }
}

struct VoiceNotesClient {
    enum VoiceNotesError: LocalizedError {
        case missingURL
        case missingToken
        case invalidResponse
        case unauthorized
        case server(String)

        var errorDescription: String? {
            switch self {
            case .missingURL:
                return "语音记事服务地址无效，请到设置中检查"
            case .missingToken:
                return "请先在设置中填写 VoiceNote Token"
            case .invalidResponse:
                return "语音记事服务返回了无效响应"
            case .unauthorized:
                return "语音记事服务认证失败，请检查 Token"
            case let .server(message):
                return message
            }
        }
    }

    var session: URLSession = .shared

    func fetchNotes(
        config: AppConfig,
        limit: Int = 100
    ) async throws -> [VoiceNoteRecord] {
        let request = try makeRequest(
            config: config,
            path: "/api/notes",
            query: [URLQueryItem(name: "limit", value: String(limit))]
        )
        let data = try await perform(request)
        return try decode(NotesResponse.self, from: data).notes
    }

    func fetchReminders(
        config: AppConfig,
        status: String? = nil,
        limit: Int = 100
    ) async throws -> [VoiceReminderRecord] {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let status, !status.isEmpty {
            query.append(URLQueryItem(name: "status", value: status))
        }
        let request = try makeRequest(
            config: config,
            path: "/api/reminders",
            query: query
        )
        let data = try await perform(request)
        return try decode(RemindersResponse.self, from: data).reminders
    }

    func createNote(
        config: AppConfig,
        content: String,
        title: String
    ) async throws {
        let payload = CreateNoteRequest(
            deviceId: config.deviceID,
            title: title,
            content: content,
            tags: ["语音记事", "iOS"]
        )
        let request = try makeRequest(
            config: config,
            path: "/api/notes",
            method: "POST",
            body: try JSONEncoder().encode(payload)
        )
        _ = try await perform(request, expectedStatus: 201)
    }

    func createReminder(
        config: AppConfig,
        content: String,
        title: String,
        at: Date,
        remindBefore: Int,
        saveNote: Bool
    ) async throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM月dd日 HH:mm"
        let payload = CreateReminderRequest(
            deviceId: config.deviceID,
            title: title,
            content: content,
            atMs: Int64(at.timeIntervalSince1970 * 1_000),
            atText: formatter.string(from: at),
            remindBefore: max(0, min(10_080, remindBefore)),
            saveNote: saveNote
        )
        let request = try makeRequest(
            config: config,
            path: "/api/reminders",
            method: "POST",
            body: try JSONEncoder().encode(payload)
        )
        _ = try await perform(request, expectedStatus: 201)
    }

    func cancelReminder(
        config: AppConfig,
        reminderID: String
    ) async throws {
        let safeID = reminderID.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? reminderID
        let body = try JSONEncoder().encode(
            CancelReminderRequest(deviceId: config.deviceID)
        )
        let request = try makeRequest(
            config: config,
            path: "/api/reminders/\(safeID)/cancel",
            method: "POST",
            body: body
        )
        _ = try await perform(request)
    }

    private func makeRequest(
        config: AppConfig,
        path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: Data? = nil
    ) throws -> URLRequest {
        guard let baseURL = config.voiceNotesURL else {
            throw VoiceNotesError.missingURL
        }
        guard !config.voiceNotesToken.isEmpty else {
            throw VoiceNotesError.missingToken
        }

        guard var components = URLComponents(
            url: baseURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw VoiceNotesError.missingURL
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(
            charactersIn: "/"
        ))
        let requestPath = path.hasPrefix("/") ? path : "/" + path
        components.path = basePath.isEmpty
            ? requestPath
            : "/" + basePath + requestPath
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw VoiceNotesError.missingURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.httpBody = body
        request.setValue(
            config.voiceNotesToken,
            forHTTPHeaderField: "X-Voice-Notes-Token"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue(
                "application/json; charset=utf-8",
                forHTTPHeaderField: "Content-Type"
            )
        }
        return request
    }

    private func perform(
        _ request: URLRequest,
        expectedStatus: Int = 200
    ) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw VoiceNotesError.invalidResponse
        }
        if http.statusCode == 401 {
            throw VoiceNotesError.unauthorized
        }
        guard http.statusCode == expectedStatus else {
            throw VoiceNotesError.server(
                Self.errorMessage(from: data)
                    ?? "语音记事服务返回 HTTP \(http.statusCode)"
            )
        }
        return data
    }

    private func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data
    ) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw VoiceNotesError.invalidResponse
        }
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary["error"] as? String
            ?? dictionary["message"] as? String
    }
}

private struct NotesResponse: Decodable {
    let notes: [VoiceNoteRecord]
}

private struct RemindersResponse: Decodable {
    let reminders: [VoiceReminderRecord]
}

private struct CreateNoteRequest: Encodable {
    let deviceId: String
    let title: String
    let content: String
    let tags: [String]
}

private struct CreateReminderRequest: Encodable {
    let deviceId: String
    let title: String
    let content: String
    let atMs: Int64
    let atText: String
    let remindBefore: Int
    let saveNote: Bool
}

private struct CancelReminderRequest: Encodable {
    let deviceId: String
}
