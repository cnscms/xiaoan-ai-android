import XCTest
@testable import XiaoZhiAI

final class OpusCodecTests: XCTestCase {
    func testOpusSilenceRoundTrip() throws {
        let codec = try OpusCodec()
        let pcm = Data(count: 960 * MemoryLayout<Int16>.size)

        let packet = try codec.encodePCM16LE(pcm)
        XCTAssertFalse(packet.isEmpty)

        let decoded = try codec.decode(packet)
        XCTAssertGreaterThan(decoded.count, 0)
        XCTAssertEqual(decoded.count % MemoryLayout<Int16>.size, 0)
    }
}
