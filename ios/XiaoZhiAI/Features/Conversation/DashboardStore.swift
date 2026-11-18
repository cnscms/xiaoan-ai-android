import Combine
import Foundation

struct WeatherSnapshot: Codable, Equatable {
    let city: String
    let icon: String
    let description: String
    let temperature: Int
    let minimum: Int
    let maximum: Int
    let updatedAt: Int64
}

struct TodayItem: Codable, Equatable, Identifiable {
    let id: String
    let type: String
    let title: String
    let content: String
    let createdAtMs: Int64
    let atMs: Int64
    let status: String

    var isReminder: Bool {
        type == "reminder"
    }

    var displayTimeMs: Int64 {
        isReminder ? atMs : createdAtMs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decode(String.self, forKey: .id) {
            id = value
        } else if let value = try? container.decode(Int64.self, forKey: .id) {
            id = String(value)
        } else {
            id = UUID().uuidString
        }

        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "note"
        let decodedTitle = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        let contentValue = try container.decodeIfPresent(
            String.self,
            forKey: .content
        )
        let textValue = try container.decodeIfPresent(String.self, forKey: .text)
        let decodedContent = contentValue ?? textValue ?? ""
        title = decodedTitle.isEmpty ? decodedContent : decodedTitle
        content = decodedContent
        createdAtMs = try container.decodeIfPresent(
            Int64.self,
            forKey: .createdAtMs
        ) ?? 0
        atMs = try container.decodeIfPresent(Int64.self, forKey: .atMs)
            ?? createdAtMs
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "saved"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(title, forKey: .title)
        try container.encode(content, forKey: .content)
        try container.encode(createdAtMs, forKey: .createdAtMs)
        try container.encode(atMs, forKey: .atMs)
        try container.encode(status, forKey: .status)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
        case content
        case text
        case createdAtMs
        case atMs
        case status
    }
}

@MainActor
final class DashboardStore: ObservableObject {
    @Published private(set) var weather: WeatherSnapshot?
    @Published private(set) var todayItems: [TodayItem] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var weatherUnavailable = false

    private let defaults: UserDefaults
    private let session: URLSession

    init(
        defaults: UserDefaults = .standard,
        session: URLSession = .shared
    ) {
        self.defaults = defaults
        self.session = session
    }

    func refresh(config: AppConfig) async {
        guard !isRefreshing else {
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        async let weatherResult = loadWeather(config: config)
        async let notesResult = loadTodayItems(config: config)

        let resolvedWeather = await weatherResult
        let resolvedItems = await notesResult

        if let resolvedWeather {
            weather = resolvedWeather
            weatherUnavailable = false
            if let data = try? JSONEncoder().encode(resolvedWeather) {
                defaults.set(data, forKey: weatherCacheKey(config))
            }
        } else {
            weatherUnavailable = true
        }

        todayItems = resolvedItems
        if let data = try? JSONEncoder().encode(resolvedItems) {
            defaults.set(data, forKey: notesCacheKey(config))
        }
    }

    func restoreCache(config: AppConfig) {
        if let data = defaults.data(forKey: weatherCacheKey(config)),
           let cached = try? JSONDecoder().decode(WeatherSnapshot.self, from: data) {
            weather = cached
        }
        if let data = defaults.data(forKey: notesCacheKey(config)),
           let cached = try? JSONDecoder().decode([TodayItem].self, from: data) {
            todayItems = cached
        }
    }

    private func loadWeather(config: AppConfig) async -> WeatherSnapshot? {
        if let server = await fetchServerWeather(config: config) {
            return server
        }
        return await fetchOpenMeteo(config: config)
    }

    private func fetchServerWeather(config: AppConfig) async -> WeatherSnapshot? {
        guard let url = endpoint(
            config: config,
            path: "/api/weather",
            query: [
                URLQueryItem(name: "city", value: config.weatherCity),
                URLQueryItem(name: "deviceId", value: config.deviceID),
                URLQueryItem(name: "clientId", value: config.clientID)
            ]
        ) else {
            return nil
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return nil
            }
            let value = try JSONDecoder().decode(ServerWeatherResponse.self, from: data)
            guard value.ok else {
                return nil
            }
            return WeatherSnapshot(
                city: value.city ?? config.weatherCity,
                icon: value.icon ?? "☁",
                description: value.description ?? "天气",
                temperature: Int((value.temperature ?? 0).rounded()),
                minimum: Int((value.minimum ?? value.temperature ?? 0).rounded()),
                maximum: Int((value.maximum ?? value.temperature ?? 0).rounded()),
                updatedAt: value.updatedAt ?? Int64(Date().timeIntervalSince1970 * 1000)
            )
        } catch {
            return nil
        }
    }

    private func fetchOpenMeteo(config: AppConfig) async -> WeatherSnapshot? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(config.weatherLatitude)),
            URLQueryItem(name: "longitude", value: String(config.weatherLongitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(
                name: "daily",
                value: "temperature_2m_max,temperature_2m_min"
            ),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components?.url else {
            return nil
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return nil
            }
            let value = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            let temperature = Int(value.current.temperature2m.rounded())
            let minimum = value.daily.temperature2mMin.first.map {
                Int($0.rounded())
            } ?? temperature
            let maximum = value.daily.temperature2mMax.first.map {
                Int($0.rounded())
            } ?? temperature
            let descriptor = Self.describeWeather(code: value.current.weatherCode)
            return WeatherSnapshot(
                city: config.weatherCity,
                icon: descriptor.icon,
                description: descriptor.description,
                temperature: temperature,
                minimum: minimum,
                maximum: maximum,
                updatedAt: Int64(Date().timeIntervalSince1970 * 1000)
            )
        } catch {
            return nil
        }
    }

    private func loadTodayItems(config: AppConfig) async -> [TodayItem] {
        guard let url = endpoint(
            config: config,
            path: "/api/voice-notes/today",
            query: [URLQueryItem(name: "deviceId", value: config.deviceID)]
        ) else {
            return todayItems
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return todayItems
            }
            let value = try JSONDecoder().decode(TodayResponse.self, from: data)
            return value.ok ? value.items.sorted {
                max($0.createdAtMs, $0.atMs) > max($1.createdAtMs, $1.atMs)
            } : todayItems
        } catch {
            return todayItems
        }
    }

    private func endpoint(
        config: AppConfig,
        path: String,
        query: [URLQueryItem]
    ) -> URL? {
        guard let websocketURL = config.websocketURL,
              let host = websocketURL.host else {
            return nil
        }
        var components = URLComponents()
        components.scheme = websocketURL.scheme == "wss" ? "https" : "http"
        components.host = host
        components.port = websocketURL.port ?? (components.scheme == "https" ? 443 : 80)
        components.path = path
        components.queryItems = query
        return components.url
    }

    private func weatherCacheKey(_ config: AppConfig) -> String {
        "xiaoan.weather.\(config.websocketURLString).\(config.weatherCity)"
    }

    private func notesCacheKey(_ config: AppConfig) -> String {
        "xiaoan.notes.\(config.deviceID)"
    }

    private static func describeWeather(code: Int) -> (icon: String, description: String) {
        switch code {
        case 0:
            return ("☀", "晴")
        case 1...3:
            return ("⛅", code == 3 ? "多云" : "少云")
        case 45, 48:
            return ("🌫", "有雾")
        case 51...67:
            return ("🌧", "有雨")
        case 71...77:
            return ("❄", "有雪")
        case 80...82:
            return ("🌦", "阵雨")
        case 95...:
            return ("⛈", "雷雨")
        default:
            return ("☁", "阴")
        }
    }
}

private struct ServerWeatherResponse: Decodable {
    let ok: Bool
    let city: String?
    let icon: String?
    let description: String?
    let temperature: Double?
    let minimum: Double?
    let maximum: Double?
    let updatedAt: Int64?

    enum CodingKeys: String, CodingKey {
        case ok
        case city
        case icon
        case description
        case temperature
        case minimum = "min"
        case maximum = "max"
        case updatedAt
    }
}

private struct TodayResponse: Decodable {
    let ok: Bool
    let items: [TodayItem]
}

private struct OpenMeteoResponse: Decodable {
    let current: Current
    let daily: Daily

    struct Current: Decodable {
        let temperature2m: Double
        let weatherCode: Int

        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case weatherCode = "weather_code"
        }
    }

    struct Daily: Decodable {
        let temperature2mMax: [Double]
        let temperature2mMin: [Double]

        enum CodingKeys: String, CodingKey {
            case temperature2mMax = "temperature_2m_max"
            case temperature2mMin = "temperature_2m_min"
        }
    }
}
