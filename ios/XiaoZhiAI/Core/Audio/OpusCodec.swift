import Foundation

final class OpusCodec {
    enum CodecError: LocalizedError {
        case createFailed(String)
        case configureFailed(String)
        case encodeFailed(String)
        case decodeFailed(String)

        var errorDescription: String? {
            switch self {
            case let .createFailed(message),
                 let .configureFailed(message),
                 let .encodeFailed(message),
                 let .decodeFailed(message):
                return message
            }
        }
    }

    private var encoder: OpaquePointer?
    private var decoder: OpaquePointer?

    init(encoderSampleRate: Int = 16_000, decoderSampleRate: Int = 48_000) throws {
        guard let encoder = xz_opus_encoder_create(Int32(encoderSampleRate), 1) else {
            throw CodecError.createFailed("无法创建 Opus 编码器")
        }
        self.encoder = encoder

        let configureResult = xz_opus_encoder_configure(encoder, 24_000, 5)
        guard configureResult == 0 else {
            xz_opus_encoder_destroy(encoder)
            self.encoder = nil
            throw CodecError.configureFailed(errorMessage(configureResult))
        }

        guard let decoder = xz_opus_decoder_create(Int32(decoderSampleRate), 1) else {
            xz_opus_encoder_destroy(encoder)
            self.encoder = nil
            throw CodecError.createFailed("无法创建 Opus 解码器")
        }
        self.decoder = decoder
    }

    deinit {
        if let encoder {
            xz_opus_encoder_destroy(encoder)
        }
        if let decoder {
            xz_opus_decoder_destroy(decoder)
        }
    }

    func encodePCM16LE(_ pcm: Data) throws -> Data {
        guard let encoder, !pcm.isEmpty else {
            throw CodecError.encodeFailed("Opus 编码器不可用或 PCM 为空")
        }
        var output = Data(count: 4_000)
        let result = pcm.withUnsafeBytes { input in
            output.withUnsafeMutableBytes { destination in
                xz_opus_encode(
                    encoder,
                    input.bindMemory(to: Int16.self).baseAddress,
                    Int32(pcm.count / MemoryLayout<Int16>.size),
                    destination.bindMemory(to: UInt8.self).baseAddress,
                    Int32(destination.count)
                )
            }
        }
        guard result > 0 else {
            throw CodecError.encodeFailed(errorMessage(result))
        }
        output.removeSubrange(Int(result)..<output.count)
        return output
    }

    func decode(_ packet: Data) throws -> Data {
        guard let decoder, !packet.isEmpty else {
            throw CodecError.decodeFailed("Opus 解码器不可用或数据为空")
        }
        let sampleCapacity = 5_760
        var output = Data(count: sampleCapacity * MemoryLayout<Int16>.size)
        let result = packet.withUnsafeBytes { input in
            output.withUnsafeMutableBytes { destination in
                xz_opus_decode(
                    decoder,
                    input.bindMemory(to: UInt8.self).baseAddress,
                    Int32(packet.count),
                    destination.bindMemory(to: Int16.self).baseAddress,
                    Int32(sampleCapacity)
                )
            }
        }
        guard result > 0 else {
            throw CodecError.decodeFailed(errorMessage(result))
        }
        output.removeSubrange(Int(result) * MemoryLayout<Int16>.size..<output.count)
        return output
    }

    private func errorMessage(_ code: Int32) -> String {
        guard let value = xz_opus_error_string(code) else {
            return "Opus 错误码 \(code)"
        }
        return "Opus 错误 \(code): \(String(cString: value))"
    }
}
