import XCTest
@testable import XiaoZhiAI

final class VisionClientTests: XCTestCase {
    func testMultipartSendsQuestionBeforeImage() throws {
        var form = MultipartFormData(boundary: "test-boundary")
        form.addText(name: "question", value: "照片里有什么？")
        form.addFile(
            name: "file",
            fileName: "photo.jpg",
            mimeType: "image/jpeg",
            fileData: Data([0xFF, 0xD8, 0xFF, 0xD9])
        )
        form.finish()

        let body = try XCTUnwrap(String(data: form.data, encoding: .utf8))
        let questionRange = try XCTUnwrap(body.range(of: "name=\"question\""))
        let fileRange = try XCTUnwrap(body.range(of: "name=\"file\""))
        XCTAssertLessThan(questionRange.lowerBound, fileRange.lowerBound)
        XCTAssertTrue(body.contains("--test-boundary"))
    }

    func testVisionResponseDecodesText() throws {
        let data = Data(
            """
            {
              "success": true,
              "action": "RESPONSE",
              "response": "照片里是一只橘猫。"
            }
            """.utf8
        )

        XCTAssertEqual(
            try VisionClient.answer(from: data),
            "照片里是一只橘猫。"
        )
    }

    func testVisionErrorResponseIsSurfaced() {
        let data = Data(
            """
            {
              "success": false,
              "message": "您还未设置默认的视觉分析模块"
            }
            """.utf8
        )

        XCTAssertThrowsError(try VisionClient.answer(from: data)) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "您还未设置默认的视觉分析模块"
            )
        }
    }
}
