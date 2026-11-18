import CryptoKit
import XCTest
@testable import XiaoZhiAI

final class PrivacyVaultTests: XCTestCase {
    func testEncryptedDataStoreRoundTripDoesNotWritePlaintext() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("vault")
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let key = SymmetricKey(size: .bits256)
        let store = EncryptedDataStore(
            fileURL: fileURL,
            explicitKey: key
        )
        let plaintext = Data("这是只有设备主人能看到的隐私内容".utf8)

        try store.save(plaintext)

        let encrypted = try Data(contentsOf: fileURL)
        XCTAssertNotEqual(encrypted, plaintext)
        XCTAssertNil(encrypted.range(of: plaintext))
        XCTAssertEqual(try store.load(), plaintext)
    }

    func testEncryptedDataStoreRejectsCorruptedPayload() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("vault")
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        try Data([0x00, 0x01, 0x02, 0x03]).write(to: fileURL)
        let store = EncryptedDataStore(
            fileURL: fileURL,
            explicitKey: SymmetricKey(size: .bits256)
        )

        XCTAssertThrowsError(try store.load())
    }
}
