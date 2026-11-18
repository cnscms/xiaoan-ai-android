import Foundation
import ImageIO
import UIKit

struct PreparedVaultPhoto: Sendable {
    let data: Data
    let width: Int
    let height: Int
}

enum VaultPhotoProcessorError: LocalizedError, Sendable {
    case unsupportedImage
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedImage:
            return "无法读取所选照片"
        case .encodingFailed:
            return "无法准备加密照片"
        }
    }
}

enum VaultPhotoProcessor {
    static func prepare(
        _ sourceData: Data,
        maxPixelSize: Int = 2_400,
        compressionQuality: CGFloat = 0.84
    ) throws -> PreparedVaultPhoto {
        guard let source = CGImageSourceCreateWithData(
            sourceData as CFData,
            nil
        ) else {
            throw VaultPhotoProcessorError.unsupportedImage
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            throw VaultPhotoProcessorError.unsupportedImage
        }

        let preparedImage = UIImage(cgImage: image, scale: 1, orientation: .up)
        guard let data = preparedImage.jpegData(
            compressionQuality: compressionQuality
        ) else {
            throw VaultPhotoProcessorError.encodingFailed
        }
        return PreparedVaultPhoto(
            data: data,
            width: image.width,
            height: image.height
        )
    }

    static func prepareForVision(_ sourceData: Data) throws -> PreparedVaultPhoto {
        let prepared = try prepare(
            sourceData,
            maxPixelSize: 1_600,
            compressionQuality: 0.76
        )
        if prepared.data.count <= 4_800_000 {
            return prepared
        }
        return try prepare(
            sourceData,
            maxPixelSize: 1_200,
            compressionQuality: 0.68
        )
    }
}
