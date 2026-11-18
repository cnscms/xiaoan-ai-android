import XCTest
@testable import XiaoZhiAI

final class ProtocolFixtureTests: XCTestCase {
    func testHelloRequestMatchesSharedFixture() throws {
        let request = HelloRequest(audioParameters: .opus16k60ms)
        let actual = try XiaozhiJSON.encode(request)
        let expected = try fixtureData("hello-request")
        try assertJSONEqual(actual, expected)
    }

    func testListenCommandsMatchSharedFixtures() throws {
        let sessionID = "0d051203-c9be-4ae0-8911-dffdc540f06c"

        try assertJSONEqual(
            try XiaozhiJSON.encode(ListenCommand.start(sessionID: sessionID)),
            fixtureData("listen-start")
        )
        try assertJSONEqual(
            try XiaozhiJSON.encode(ListenCommand.stop(sessionID: sessionID)),
            fixtureData("listen-stop")
        )
        try assertJSONEqual(
            try XiaozhiJSON.encode(
                ListenCommand.detect(sessionID: sessionID, text: "你好小安")
            ),
            fixtureData("listen-detect")
        )
        try assertJSONEqual(
            try XiaozhiJSON.encode(
                AbortCommand(sessionID: sessionID, reason: "user_interrupt")
            ),
            fixtureData("abort")
        )
    }

    func testServerEventsDecodeFromSharedFixtures() throws {
        let hello = try XiaozhiJSON.decodeServerEvent(fixtureData("hello-response"))
        XCTAssertTrue(hello.isHello)
        XCTAssertEqual(hello.audioParameters, .opus16k60ms)
        XCTAssertEqual(hello.sessionID, "0d051203-c9be-4ae0-8911-dffdc540f06c")

        let stt = try XiaozhiJSON.decodeServerEvent(fixtureData("stt"))
        XCTAssertEqual(stt.type, "stt")
        XCTAssertEqual(stt.text, "今天天气怎么样")

        let llm = try XiaozhiJSON.decodeServerEvent(fixtureData("llm"))
        XCTAssertEqual(llm.emotion, "happy")

        let ttsStart = try XiaozhiJSON.decodeServerEvent(fixtureData("tts-start"))
        XCTAssertEqual(ttsStart.state, "start")

        let ttsStop = try XiaozhiJSON.decodeServerEvent(fixtureData("tts-stop"))
        XCTAssertEqual(ttsStop.state, "stop")
    }

    func testOtaResponseMatchesConfiguredServer() throws {
        let response = try JSONDecoder().decode(
            OtaResponse.self,
            from: fixtureData("ota-response")
        )
        XCTAssertEqual(response.activation?.code, "123456")
        XCTAssertEqual(
            response.websocket.url,
            "ws://sql.ms48.com:8001/xiaozhi/v1/"
        )
    }

    func testDefaultConfigurationUsesOurServer() {
        let config = AppConfig(clientID: UUID().uuidString, deviceID: "02:00:00:00:00:01")
        XCTAssertEqual(config.otaURLString, "http://sql.ms48.com:8002/xiaozhi/ota/")
        XCTAssertEqual(config.websocketURLString, "ws://sql.ms48.com:8001/xiaozhi/v1/")
        XCTAssertNotNil(config.otaURL)
        XCTAssertNotNil(config.websocketURL)
        XCTAssertTrue(config.isComplete)
    }

    func testLANEnvironmentUsesLANServer() {
        XCTAssertEqual(
            ServerEnvironment.lan.defaultOTAURL,
            "http://192.168.0.20:8002/xiaozhi/ota/"
        )
        XCTAssertEqual(
            ServerEnvironment.lan.defaultWebSocketURL,
            "ws://192.168.0.20:8001/xiaozhi/v1/"
        )
        XCTAssertEqual(ServerEnvironment.lan.displayName, "小安内网")
    }

    private func fixtureData(_ name: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = bundle.url(forResource: name, withExtension: "json")
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "fixtures")
        guard let url else {
            XCTFail("Missing fixture: \(name).json")
            throw FixtureError.missing(name)
        }
        return try Data(contentsOf: url)
    }

    private func assertJSONEqual(
        _ actual: Data,
        _ expected: Data,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let actualObject = try JSONSerialization.jsonObject(with: actual)
        let expectedObject = try JSONSerialization.jsonObject(with: expected)
        XCTAssertEqual(
            actualObject as? NSDictionary,
            expectedObject as? NSDictionary,
            file: file,
            line: line
        )
    }

    private enum FixtureError: Error {
        case missing(String)
    }
}
