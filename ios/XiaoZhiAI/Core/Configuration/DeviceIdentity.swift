import Foundation

struct DeviceIdentity: Codable, Equatable {
    let clientID: String
    let deviceID: String

    static func loadOrCreate(keychain: KeychainStore = KeychainStore()) -> DeviceIdentity {
        let clientID = validClientID(keychain.string(for: "client_id"))
            ?? UUID().uuidString.lowercased()
        let deviceID = validDeviceID(keychain.string(for: "device_id"))
            ?? makeDeviceID(seed: clientID)

        keychain.set(clientID, for: "client_id")
        keychain.set(deviceID, for: "device_id")
        return DeviceIdentity(clientID: clientID, deviceID: deviceID)
    }

    private static func validClientID(_ value: String?) -> String? {
        guard let value, UUID(uuidString: value) != nil else {
            return nil
        }
        return value.lowercased()
    }

    private static func validDeviceID(_ value: String?) -> String? {
        guard let value,
              value.range(
                of: #"^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$"#,
                options: .regularExpression
              ) != nil else {
            return nil
        }
        return value.uppercased()
    }

    private static func makeDeviceID(seed: String) -> String {
        let compact = seed.replacingOccurrences(of: "-", with: "")
        let characters = Array(compact)
        var bytes: [UInt8] = [0x02]
        for index in stride(from: 0, to: min(characters.count, 10), by: 2) {
            bytes.append(UInt8(String(characters[index...index + 1]), radix: 16) ?? 0)
        }
        while bytes.count < 6 {
            bytes.append(UInt8.random(in: 1...255))
        }
        return bytes.prefix(6).map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}

