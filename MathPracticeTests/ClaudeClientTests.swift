import XCTest
@testable import MathPractice

/// Serves canned responses to URLSession.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [(Int, String)] = []
    nonisolated(unsafe) static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        Self.requestCount += 1
        let (status, body) = Self.responses.isEmpty ? (500, "{}") : Self.responses.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class ClaudeClientTests: XCTestCase {
    func sse(text: String, stopReason: String = "end_turn") -> String {
        let escaped = String(data: try! JSONSerialization.data(withJSONObject: [text]), encoding: .utf8)!.dropFirst().dropLast()
        return """
        event: message_start
        data: {"type":"message_start","message":{"id":"msg_1"}}

        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}

        event: content_block_start
        data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":\(escaped)}}

        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"\(stopReason)"}}

        event: message_stop
        data: {"type":"message_stop"}

        """
    }

    func makeClient() -> ClaudeClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        var client = ClaudeClient(apiKey: { "test-key" }, session: URLSession(configuration: config))
        client.maxRetries = 1
        return client
    }

    override func setUp() {
        MockURLProtocol.responses = []
        MockURLProtocol.requestCount = 0
    }

    func testRequestBodyShape() throws {
        let body = ClaudeClient.requestBody(model: "claude-opus-5-5", system: "sys", content: [.text("hi")],
                                            schema: SolveDTO.schema, effort: .high, maxTokens: 100)
        let output = try XCTUnwrap(body["output_config"] as? [String: Any])
        XCTAssertEqual(output["effort"] as? String, "high")
        let format = try XCTUnwrap(output["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertNil(body["thinking"])
        XCTAssertNil(body["temperature"])
    }

    func testDecodesStructuredStreamIgnoringThinking() async throws {
        MockURLProtocol.responses = [(200, sse(text: #"{"solution":"x=2","final_answer":"2","solvable":true}"#))]
        let result = try await makeClient().structured(SolveDTO.self, system: "s", content: [.text("q")],
                                                       schema: SolveDTO.schema, effort: .low)
        XCTAssertEqual(result.final_answer, "2")
    }

    func testRetriesOverloadedThenSucceeds() async throws {
        MockURLProtocol.responses = [
            (529, #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#),
            (200, sse(text: #"{"solution":"","final_answer":"7","solvable":true}"#)),
        ]
        let result = try await makeClient().structured(SolveDTO.self, system: "s", content: [.text("q")],
                                                       schema: SolveDTO.schema, effort: .low)
        XCTAssertEqual(result.final_answer, "7")
        XCTAssertEqual(MockURLProtocol.requestCount, 2)
    }

    func testDoesNotRetryBadRequest() async {
        MockURLProtocol.responses = [(400, #"{"type":"error","error":{"type":"invalid_request_error","message":"bad"}}"#)]
        do {
            _ = try await makeClient().send(system: "s", content: [.text("q")], schema: nil, effort: .low, maxTokens: 10)
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? ClaudeClient.ClientError, .http(status: 400, message: "bad"))
            XCTAssertEqual(MockURLProtocol.requestCount, 1)
        }
    }

    func testRefusalAndTruncationSurface() throws {
        var refusal = SSEAccumulator()
        for line in sse(text: "", stopReason: "refusal").split(separator: "\n") { try refusal.consume(line: String(line)) }
        XCTAssertThrowsError(try refusal.finish()) { XCTAssertEqual($0 as? ClaudeClient.ClientError, .refusal("unspecified")) }

        var cut = SSEAccumulator()
        for line in sse(text: "{\"a\":", stopReason: "max_tokens").split(separator: "\n") { try cut.consume(line: String(line)) }
        XCTAssertThrowsError(try cut.finish()) { XCTAssertEqual($0 as? ClaudeClient.ClientError, .truncated) }
    }

    func testMissingKey() async {
        let client = ClaudeClient(apiKey: { nil })
        do {
            _ = try await client.send(system: "", content: [], schema: nil, effort: .low, maxTokens: 1)
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? ClaudeClient.ClientError, .missingAPIKey)
        }
    }
}
