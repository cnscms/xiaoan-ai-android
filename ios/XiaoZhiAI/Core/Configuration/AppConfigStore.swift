import Combine
import Foundation

@MainActor
final class AppConfigStore: ObservableObject {
    @Published private(set) var config: AppConfig

    private let defaults: UserDefaults
    private let keychain: KeychainStore
    private let storageKey = "xiaozhi.ai.config.v1"

    init(
        defaults: UserDefaults = .standard,
        keychain: KeychainStore = KeychainStore()
    ) {
        self.defaults = defaults
        self.keychain = keychain

        let identity = DeviceIdentity.loadOrCreate(keychain: keychain)
        var loaded: AppConfig
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            loaded = decoded
        } else {
            loaded = AppConfig(
                clientID: identity.clientID,
                deviceID: identity.deviceID
            )
        }

        loaded.token = keychain.string(for: "auth_token") ?? loaded.token
        if loaded.otaURLString.isEmpty {
            loaded.otaURLString = AppConfig.defaultOTAURL
        }
        if loaded.websocketURLString.isEmpty {
            loaded.websocketURLString = AppConfig.defaultWebSocketURL
        }
        loaded.clientID = identity.clientID
        loaded.deviceID = identity.deviceID
        loaded.normalize()
        config = loaded
    }

    func save(_ updated: AppConfig) {
        var value = updated
        value.normalize()
        value.clientID = config.clientID
        value.deviceID = config.deviceID

        keychain.set(value.token, for: "auth_token")
        var persisted = value
        persisted.token = ""
        if let data = try? JSONEncoder().encode(persisted) {
            defaults.set(data, forKey: storageKey)
        }
        config = value
    }
}
