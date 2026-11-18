import Combine
import CryptoKit
import Foundation
import LocalAuthentication

struct VaultPhoto: Codable, Equatable, Identifiable {
    let id: UUID
    let fileName: String
    let addedAt: Date
    let width: Int
    let height: Int
}

struct PrivacyVaultSnapshot: Codable, Equatable {
    var messages: [ChatMessage]
    var todayItems: [TodayItem]
    var photos: [VaultPhoto]
    var updatedAt: Date

    static let empty = PrivacyVaultSnapshot(
        messages: [],
        todayItems: [],
        photos: [],
        updatedAt: .distantPast
    )

    init(
        messages: [ChatMessage],
        todayItems: [TodayItem],
        photos: [VaultPhoto],
        updatedAt: Date
    ) {
        self.messages = messages
        self.todayItems = todayItems
        self.photos = photos
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messages = try container.decodeIfPresent(
            [ChatMessage].self,
            forKey: .messages
        ) ?? []
        todayItems = try container.decodeIfPresent(
            [TodayItem].self,
            forKey: .todayItems
        ) ?? []
        photos = try container.decodeIfPresent(
            [VaultPhoto].self,
            forKey: .photos
        ) ?? []
        updatedAt = try container.decodeIfPresent(
            Date.self,
            forKey: .updatedAt
        ) ?? .distantPast
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(messages, forKey: .messages)
        try container.encode(todayItems, forKey: .todayItems)
        try container.encode(photos, forKey: .photos)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    enum CodingKeys: String, CodingKey {
        case messages
        case todayItems
        case photos
        case updatedAt
    }
}

enum EncryptedDataStoreError: LocalizedError {
    case invalidEncryptionKey
    case keyStorageFailed
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .invalidEncryptionKey:
            return "隐私保险箱的加密密钥无效"
        case .keyStorageFailed:
            return "无法在钥匙串中保存隐私保险箱密钥"
        case .invalidPayload:
            return "隐私保险箱数据已损坏"
        }
    }
}

struct EncryptedDataStore {
    private let keychain: KeychainStore
    private let keyName: String
    private let explicitKey: SymmetricKey?
    let fileURL: URL

    init(
        fileURL: URL? = nil,
        keychain: KeychainStore = KeychainStore(),
        keyName: String = "privacy_vault_key_v1",
        explicitKey: SymmetricKey? = nil
    ) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        self.keychain = keychain
        self.keyName = keyName
        self.explicitKey = explicitKey
    }

    func load() throws -> Data? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let encrypted = try Data(contentsOf: fileURL)
        do {
            let box = try AES.GCM.SealedBox(combined: encrypted)
            return try AES.GCM.open(box, using: encryptionKey())
        } catch {
            throw EncryptedDataStoreError.invalidPayload
        }
    }

    func save(_ payload: Data) throws {
        let key = try encryptionKey()
        let sealed = try AES.GCM.seal(payload, using: key)
        guard let encrypted = sealed.combined else {
            throw EncryptedDataStoreError.invalidPayload
        }

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encrypted.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }

    func delete() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: fileURL)
    }

    func store(at fileURL: URL) -> EncryptedDataStore {
        EncryptedDataStore(
            fileURL: fileURL,
            keychain: keychain,
            keyName: keyName,
            explicitKey: explicitKey
        )
    }

    private func encryptionKey() throws -> SymmetricKey {
        if let explicitKey {
            return explicitKey
        }
        if let stored = keychain.string(for: keyName),
           let data = Data(base64Encoded: stored),
           data.count == 32 {
            return SymmetricKey(data: data)
        }

        let generated = SymmetricKey(size: .bits256)
        let data = generated.withUnsafeBytes { Data($0) }
        guard keychain.set(data.base64EncodedString(), for: keyName) else {
            throw EncryptedDataStoreError.keyStorageFailed
        }
        return generated
    }

    private static var defaultFileURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Xiaoan", isDirectory: true)
            .appendingPathComponent("privacy-vault.bin")
    }
}

@MainActor
final class PrivacyVaultStore: ObservableObject {
    @Published private(set) var snapshot = PrivacyVaultSnapshot.empty
    @Published private(set) var isLocked = true
    @Published private(set) var isAuthenticating = false
    @Published private(set) var authenticationError: String?
    @Published private(set) var authenticationMethod = "设备密码"

    private let storage: EncryptedDataStore

    private var attachmentDirectory: URL {
        storage.fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("PrivacyVaultPhotos", isDirectory: true)
    }

    init(storage: EncryptedDataStore = EncryptedDataStore()) {
        self.storage = storage
        configureAuthenticationMethod()
    }

    func unlock() async -> Bool {
        guard !isAuthenticating else {
            return false
        }
        isAuthenticating = true
        authenticationError = nil
        defer { isAuthenticating = false }

        let context = LAContext()
        context.localizedFallbackTitle = "使用设备密码"
        var policyError: NSError?
        guard context.canEvaluatePolicy(
            .deviceOwnerAuthentication,
            error: &policyError
        ) else {
            authenticationError = policyError?.localizedDescription
                ?? "当前设备未设置面容、触控或设备密码"
            return false
        }

        do {
            let authorized = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "解锁小安隐私保险箱"
            )
            guard authorized else {
                authenticationError = "身份验证未通过"
                return false
            }
            snapshot = try loadDocument()
            isLocked = false
            return true
        } catch {
            authenticationError = error.localizedDescription
            return false
        }
    }

    func lock() {
        isLocked = true
        authenticationError = nil
        snapshot = .empty
    }

    func upsertChatMessage(_ message: ChatMessage) throws {
        var document = try loadDocument()
        if let index = document.messages.firstIndex(where: { $0.id == message.id }) {
            document.messages[index] = message
        } else {
            document.messages.append(message)
        }
        if document.messages.count > 100 {
            document.messages.removeFirst(document.messages.count - 100)
        }
        try saveDocument(document)
    }

    func replaceTodayItems(_ items: [TodayItem]) throws {
        var document = try loadDocument()
        document.todayItems = items
        try saveDocument(document)
    }

    func cachedTodayItems() -> [TodayItem] {
        (try? loadDocument())?.todayItems ?? []
    }

    func storedPhotos() throws -> [VaultPhoto] {
        try loadDocument().photos
    }

    @discardableResult
    func importPhoto(data: Data, width: Int, height: Int) throws -> VaultPhoto {
        let id = UUID()
        let photo = VaultPhoto(
            id: id,
            fileName: "\(id.uuidString).bin",
            addedAt: Date(),
            width: width,
            height: height
        )
        let photoStore = storage.store(at: photoURL(for: photo))
        try photoStore.save(data)

        var document = try loadDocument()
        document.photos.append(photo)
        do {
            try saveDocument(document)
            return photo
        } catch {
            try? photoStore.delete()
            throw error
        }
    }

    func decryptedPhotoData(for photo: VaultPhoto) throws -> Data? {
        try storage.store(at: photoURL(for: photo)).load()
    }

    func deletePhoto(_ photo: VaultPhoto) throws {
        var document = try loadDocument()
        document.photos.removeAll { $0.id == photo.id }
        try saveDocument(document)
        try? storage.store(at: photoURL(for: photo)).delete()
    }

    func clearChatHistory() throws {
        var document = try loadDocument()
        document.messages.removeAll()
        try saveDocument(document)
        if !isLocked {
            snapshot.messages.removeAll()
        }
    }

    func clearAll() throws {
        try storage.delete()
        if FileManager.default.fileExists(atPath: attachmentDirectory.path) {
            try FileManager.default.removeItem(at: attachmentDirectory)
        }
        snapshot = .empty
        authenticationError = nil
    }

    private func photoURL(for photo: VaultPhoto) -> URL {
        attachmentDirectory.appendingPathComponent(photo.fileName, isDirectory: false)
    }

    private func loadDocument() throws -> PrivacyVaultSnapshot {
        guard let data = try storage.load() else {
            return .empty
        }
        return try JSONDecoder().decode(PrivacyVaultSnapshot.self, from: data)
    }

    private func saveDocument(_ document: PrivacyVaultSnapshot) throws {
        var value = document
        value.updatedAt = Date()
        let data = try JSONEncoder().encode(value)
        try storage.save(data)
        if !isLocked {
            snapshot = value
        }
    }

    private func configureAuthenticationMethod() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(
            .deviceOwnerAuthentication,
            error: &error
        ) else {
            authenticationMethod = "设备密码"
            return
        }

        switch context.biometryType {
        case .faceID:
            authenticationMethod = "面容 ID"
        case .touchID:
            authenticationMethod = "触控 ID"
        default:
            authenticationMethod = "设备密码"
        }
    }
}
