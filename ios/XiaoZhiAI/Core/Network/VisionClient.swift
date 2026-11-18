import Foundation

struct MultipartFormData {
    let boundary: String
    private(set) var data = Data()

    init(boundary: String = "XiaoanBoundary-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    mutating func addText(name: String, value: String) {
        append("--\(boundary)\r\n")
        append(
            "Content-Disposition: form-data; name=\"\(name)\"\r\n"
                + "Content-Type: text/plain; charset=utf-8\r\n\r\n"
        )
        append(value)
        append("\r\n")
    }

    mutating func addFile(
        name: String,
        fileName: String,
        mimeType: String,
        fileData: Data
    ) {
        append("--\(boundary)\r\n")
        append(
            "Content-Disposition: form-data; name=\"\(name)\"; "
                + "filename=\"\(fileName)\"\r\n"
        )
        append("Content-Type: \(mimeType)\r\n\r\n")
        data.append(fileData)
        append("\r\n")
    }

    mutating func finish() {
        append("--\(boundary)--\r\n")
    }

    private mutating func append(_ value: String) {
        data.append(Data(value.utf8))
    }
}

struct VisionClient {
    enum VisionError: LocalizedError {
        case invalidURL
        case emptyPhoto
        case photoTooLarge
        case invalidResponse
        case unauthorized
        case server(String)
        case emptyAnswer

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "视觉分析地址无效，请到设置中检查"
            case .emptyPhoto:
                return "照片数据为空"
            case .photoTooLarge:
                return "照片超过视觉服务允许的 5 MB"
            case .invalidResponse:
                return "视觉服务返回了无效响应"
            case .unauthorized:
                return "视觉服务认证失败，请重新完成设备绑定"
            case let .server(message):
                return message
            case .emptyAnswer:
                return "小安没有返回照片分析结果"
            }
        }
    }

    var session: URLSession = .shared

    func explain(
        config: AppConfig,
        question: String,
        imageData: Data
    ) async throws -> String {
        guard let url = config.visionURL else {
            throw VisionError.invalidURL
        }
        guard !imageData.isEmpty else {
            throw VisionError.emptyPhoto
        }
        guard imageData.count <= 5 * 1024 * 1024 else {
            throw VisionError.photoTooLarge
        }

        var form = MultipartFormData()
        form.addText(name: "question", value: question)
        form.addFile(
            name: "file",
            fileName: "xiaoan-photo.jpg",
            mimeType: "image/jpeg",
            fileData: imageData
        )
        form.finish()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.httpBody = form.data
        request.setValue(
            "multipart/form-data; boundary=\(form.boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Xiaoan-iOS/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue(config.deviceID, forHTTPHeaderField: "Device-Id")
        request.setValue(config.clientID, forHTTPHeaderField: "Client-Id")
        if !config.token.isEmpty {
            request.setValue(
                "Bearer \(config.token)",
                forHTTPHeaderField: "Authorization"
            )
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw VisionError.invalidResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw VisionError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw VisionError.server(Self.errorMessage(from: data))
        }
        return try Self.answer(from: data)
    }

    static func answer(from data: Data) throws -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            let fallback = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !fallback.isEmpty else {
                throw VisionError.emptyAnswer
            }
            return fallback
        }

        if let success = dictionary["success"] as? Bool, !success {
            throw VisionError.server(
                dictionary["message"] as? String ?? "视觉分析失败"
            )
        }
        if let response = dictionary["response"] as? String,
           !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return response
        }
        if let response = dictionary["response"] as? [String: Any] {
            for key in ["text", "content", "answer", "message"] {
                if let value = response[key] as? String,
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value
                }
            }
        }
        for key in ["text", "content", "answer", "message"] {
            if let value = dictionary[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        throw VisionError.emptyAnswer
    }

    private static func errorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return "视觉分析服务请求失败"
        }
        return dictionary["message"] as? String
            ?? dictionary["error"] as? String
            ?? "视觉分析服务请求失败"
    }
}
