import XCTest
@testable import XiaoZhiAI

final class VoiceNotesClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testFetchNotesUsesTokenAndDecodesNotes() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/notes")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "X-Voice-Notes-Token"),
                "voice-token"
            )
            let data = Data(
                """
                {
                  "ok": true,
                  "notes": [
                    {
                      "id": "note_1",
                      "title": "给客户回电话",
                      "transcript": "下午给客户回电话",
                      "tags": "[\\"语音记事\\"]",
                      "durationSeconds": 12.5,
                      "createdAt": "2026-11-19T08:30:00"
                    }
                  ]
                }
                """.utf8
            )
            return (
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                data
            )
        }

        let notes = try await makeClient().fetchNotes(config: makeConfig())
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.title, "给客户回电话")
        XCTAssertEqual(notes.first?.durationSeconds, 12.5)
        XCTAssertNotNil(notes.first?.createdDate)
    }

    func testFetchRemindersDecodesPendingStatus() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/reminders")
            let data = Data(
                """
                {
                  "ok": true,
                  "reminders": [
                    {
                      "id": "rem_1",
                      "title": "开会",
                      "content": "明天下午三点开会",
                      "atMs": 1800003600000,
                      "notifyAtMs": 1800003600000,
                      "atText": "11月20日 15:00",
                      "remindBefore": 0,
                      "status": "pending",
                      "attempts": 0,
                      "lastError": null,
                      "createdAtMs": 1800000000000
                    }
                  ]
                }
                """.utf8
            )
            return (
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                data
            )
        }

        let reminders = try await makeClient().fetchReminders(config: makeConfig())
        XCTAssertEqual(reminders.first?.status, "pending")
        XCTAssertTrue(reminders.first?.isPending == true)
    }

    func testCreateNoteUsesPost() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/notes")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Content-Type"),
                "application/json; charset=utf-8"
            )
            return (
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 201,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(#"{"ok":true,"note":{}}"#.utf8)
            )
        }

        try await makeClient().createNote(
            config: makeConfig(),
            content: "下午给客户回电话",
            title: "回电话"
        )
    }

    private func makeClient() -> VoiceNotesClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return VoiceNotesClient(
            session: URLSession(configuration: configuration)
        )
    }

    private func makeConfig() -> AppConfig {
        var config = AppConfig(
            clientID: "client",
            deviceID: "02:00:00:00:00:01"
        )
        config.voiceNotesURLString = "http://192.168.0.20:19090"
        config.voiceNotesToken = "voice-token"
        return config
    }
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.badServerResponse)
            )
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
