import Foundation
import XCTest
@testable import SnapTra_Translator

final class SmokeTests: XCTestCase {
    func testSmoke() {
        XCTAssertTrue(true)
    }
}

final class SentenceTranslationServiceStreamingTests: XCTestCase {
    private var didCaptureOpenAIAPIKey = false
    private var capturedOpenAIAPIKey: String?

    override func tearDown() {
        if didCaptureOpenAIAPIKey {
            if let capturedOpenAIAPIKey {
                LLMProviderCredentialStore.setAPIKey(capturedOpenAIAPIKey, for: .openAI)
            } else {
                LLMProviderCredentialStore.deleteAPIKey(for: .openAI)
            }
        }
        MockLLMURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testOpenAICompatibleStreamingDisablesThinkingAndIgnoresMetadataChunks() async throws {
        let stream = """
        data: {"choices":[{"delta":{"role":"assistant"}}]}

        data: {"choices":[{"delta":{"content":"嗨"}}]}

        data: {"choices":[{"delta":{"content":"，yangyj13!"}}]}

        data: {"choices":[{"finish_reason":"stop"}]}

        data: [DONE]

        """
        var requestBodies: [[String: Any]] = []

        MockLLMURLProtocol.requestHandler = { request in
            guard request.url?.absoluteString == "https://llm.example/v1/chat/completions" else {
                throw MockLLMURLProtocol.Error.unexpectedURL
            }
            guard request.value(forHTTPHeaderField: "Accept") == "text/event-stream" else {
                throw MockLLMURLProtocol.Error.unexpectedHeader
            }
            requestBodies.append(try request.jsonBody())

            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/event-stream"]
                )!,
                Data(stream.utf8)
            )
        }

        let service = SentenceTranslationService(session: .mockLLM)
        var partialResults: [String] = []

        let translation = try await service.translateStreaming(
            text: "Hi yangyj13!",
            provider: .ollama,
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            llmConfiguration: LLMProviderConfiguration(
                provider: .ollama,
                model: "test-model",
                baseURL: "https://llm.example/v1"
            ),
            onPartialResult: { partial in
                partialResults.append(partial)
            }
        )

        XCTAssertEqual(translation, "嗨，yangyj13!")
        XCTAssertEqual(partialResults, ["嗨", "嗨，yangyj13!"])
        XCTAssertEqual(requestBodies.count, 1)
        XCTAssertEqual(requestBodies.first?["think"] as? Bool, false)
    }

    func testOpenAICompatibleStreamingRetriesWithoutThinkingWhenParameterIsUnsupported() async throws {
        let stream = """
        data: {"choices":[{"delta":{"content":"嗨，yangyj13!"}}]}

        data: [DONE]

        """
        var requestBodies: [[String: Any]] = []

        MockLLMURLProtocol.requestHandler = { request in
            guard request.url?.absoluteString == "https://llm.example/v1/chat/completions" else {
                throw MockLLMURLProtocol.Error.unexpectedURL
            }
            requestBodies.append(try request.jsonBody())

            if requestBodies.count == 1 {
                let errorBody = #"{"error":{"message":"Unsupported parameter: think"}}"#
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 400,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!,
                    Data(errorBody.utf8)
                )
            }

            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/event-stream"]
                )!,
                Data(stream.utf8)
            )
        }

        let service = SentenceTranslationService(session: .mockLLM)

        let translation = try await service.translateStreaming(
            text: "Hi yangyj13!",
            provider: .ollama,
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            llmConfiguration: LLMProviderConfiguration(
                provider: .ollama,
                model: "test-model",
                baseURL: "https://llm.example/v1"
            ),
            onPartialResult: { _ in }
        )

        XCTAssertEqual(translation, "嗨，yangyj13!")
        XCTAssertEqual(requestBodies.count, 2)
        XCTAssertEqual(requestBodies.first?["think"] as? Bool, false)
        XCTAssertNil(requestBodies.last?["think"])
    }

    func testOpenAICompatibleStreamingUsesNoneForGPT5MiniReasoningEffort() async throws {
        try configureTemporaryOpenAIAPIKey()

        let stream = """
        data: {"choices":[{"delta":{"content":"你好"}}]}

        data: [DONE]

        """
        var requestBodies: [[String: Any]] = []

        MockLLMURLProtocol.requestHandler = { request in
            guard request.url?.absoluteString == "https://llm.example/v1/chat/completions" else {
                throw MockLLMURLProtocol.Error.unexpectedURL
            }
            guard request.value(forHTTPHeaderField: "Authorization") == "Bearer test-api-key" else {
                throw MockLLMURLProtocol.Error.unexpectedHeader
            }
            requestBodies.append(try request.jsonBody())

            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/event-stream"]
                )!,
                Data(stream.utf8)
            )
        }

        let service = SentenceTranslationService(session: .mockLLM)

        let translation = try await service.translateStreaming(
            text: "Hello",
            provider: .openAI,
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            llmConfiguration: LLMProviderConfiguration(
                provider: .openAI,
                model: "gpt-5.4-mini",
                baseURL: "https://llm.example/v1"
            ),
            onPartialResult: { _ in }
        )

        XCTAssertEqual(translation, "你好")
        XCTAssertEqual(requestBodies.count, 1)
        XCTAssertEqual(requestBodies.first?["reasoning_effort"] as? String, "none")
        XCTAssertNil(requestBodies.first?["think"])
        XCTAssertNil(requestBodies.first?["thinking"])
    }

    func testOpenAICompatibleStreamingRetriesWithoutReasoningEffortWhenValueUnsupported() async throws {
        try configureTemporaryOpenAIAPIKey()

        let stream = """
        data: {"choices":[{"delta":{"content":"你好"}}]}

        data: [DONE]

        """
        var requestBodies: [[String: Any]] = []

        MockLLMURLProtocol.requestHandler = { request in
            guard request.url?.absoluteString == "https://llm.example/v1/chat/completions" else {
                throw MockLLMURLProtocol.Error.unexpectedURL
            }
            requestBodies.append(try request.jsonBody())

            if requestBodies.count == 1 {
                let errorBody = """
                {"error":{"message":"Unsupported value: 'low' is not supported with this model. Supported values are: 'none', 'medium', 'high', and 'xhigh'.","type":"invalid_request_error"}}
                """
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 400,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!,
                    Data(errorBody.utf8)
                )
            }

            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/event-stream"]
                )!,
                Data(stream.utf8)
            )
        }

        let service = SentenceTranslationService(session: .mockLLM)

        let translation = try await service.translateStreaming(
            text: "Hello",
            provider: .openAI,
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            llmConfiguration: LLMProviderConfiguration(
                provider: .openAI,
                model: "o4-mini",
                baseURL: "https://llm.example/v1"
            ),
            onPartialResult: { _ in }
        )

        XCTAssertEqual(translation, "你好")
        XCTAssertEqual(requestBodies.count, 2)
        XCTAssertEqual(requestBodies.first?["reasoning_effort"] as? String, "low")
        XCTAssertNil(requestBodies.last?["reasoning_effort"])
    }

    private func configureTemporaryOpenAIAPIKey() throws {
        capturedOpenAIAPIKey = LLMProviderCredentialStore.apiKey(for: .openAI)
        didCaptureOpenAIAPIKey = true

        guard LLMProviderCredentialStore.setAPIKey("test-api-key", for: .openAI) else {
            throw MockLLMURLProtocol.Error.missingBody
        }
    }
}

private final class MockLLMURLProtocol: URLProtocol {
    enum Error: Swift.Error {
        case missingHandler
        case unexpectedURL
        case unexpectedHeader
        case missingBody
    }

    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: Error.missingHandler)
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension URLSession {
    static var mockLLM: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockLLMURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private extension URLRequest {
    func jsonBody() throws -> [String: Any] {
        let data: Data
        if let httpBody {
            data = httpBody
        } else if let httpBodyStream {
            data = try Data(reading: httpBodyStream)
        } else {
            throw MockLLMURLProtocol.Error.missingBody
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MockLLMURLProtocol.Error.missingBody
        }
        return json
    }
}

private extension Data {
    init(reading inputStream: InputStream) throws {
        self.init()

        inputStream.open()
        defer { inputStream.close() }

        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while inputStream.hasBytesAvailable {
            let count = inputStream.read(buffer, maxLength: bufferSize)
            if count < 0 {
                throw inputStream.streamError ?? MockLLMURLProtocol.Error.missingBody
            }
            if count == 0 {
                break
            }
            append(buffer, count: count)
        }
    }
}
