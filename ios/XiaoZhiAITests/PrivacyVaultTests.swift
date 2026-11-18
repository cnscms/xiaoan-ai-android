import CryptoKit
import UIKit
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

    func testLegacyVaultDocumentWithoutPhotosStillDecodes() throws {
        let document = try JSONDecoder().decode(
            PrivacyVaultSnapshot.self,
            from: Data("{}".utf8)
        )

        XCTAssertTrue(document.messages.isEmpty)
        XCTAssertTrue(document.todayItems.isEmpty)
        XCTAssertTrue(document.photos.isEmpty)
    }

    @MainActor
    func testPhotoRoundTripAndDelete() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let key = SymmetricKey(size: .bits256)
        let vaultFile = directory.appendingPathComponent("privacy-vault.bin")
        let vault = PrivacyVaultStore(
            storage: EncryptedDataStore(
                fileURL: vaultFile,
                explicitKey: key
            )
        )
        let photoData = Data("encrypted-photo-test-payload".utf8)

        let photo = try vault.importPhoto(
            data: photoData,
            width: 320,
            height: 240
        )
        let storedPhoto = try XCTUnwrap(try vault.storedPhotos().first)
        XCTAssertEqual(storedPhoto, photo)
        XCTAssertEqual(
            try vault.decryptedPhotoData(for: photo),
            photoData
        )

        let encryptedFile = directory
            .appendingPathComponent("PrivacyVaultPhotos", isDirectory: true)
            .appendingPathComponent(photo.fileName)
        let encrypted = try Data(contentsOf: encryptedFile)
        XCTAssertNil(encrypted.range(of: photoData))

        try vault.deletePhoto(photo)
        XCTAssertTrue(try vault.storedPhotos().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: encryptedFile.path))
    }

    func testPhotoProcessorCreatesBoundedJPEG() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 80))
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        }
        let source = try XCTUnwrap(image.pngData())

        let prepared = try VaultPhotoProcessor.prepare(
            source,
            maxPixelSize: 40
        )

        XCTAssertEqual(prepared.width, 40)
        XCTAssertTrue((26...27).contains(prepared.height))
        XCTAssertNotNil(UIImage(data: prepared.data))
    }
}
