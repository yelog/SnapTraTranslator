import Foundation
import XCTest
@testable import SnapTra_Translator

final class SmokeTests: XCTestCase {
    func testSmoke() {
        XCTAssertTrue(true)
    }
}

final class SentenceTranslationServiceStreamingTests: XCTestCase {
    override func tearDown() {
        MockLLMURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testOpenAICompatibleStreamingIgnoresMetadataAndFinishChunks() async throws {
        let stream = """
        data: {"choices":[{"delta":{"role":"assistant"}}]}

        data: {"choices":[{"delta":{"content":"嗨"}}]}

        data: {"choices":[{"delta":{"content":"，yangyj13!"}}]}

        data: {"choices":[{"finish_reason":"stop"}]}

        data: [DONE]

        """

        MockLLMURLProtocol.requestHandler = { request in
            guard request.url?.absoluteString == "https://llm.example/v1/chat/completions" else {
                throw MockLLMURLProtocol.Error.unexpectedURL
            }
            guard request.value(forHTTPHeaderField: "Accept") == "text/event-stream" else {
                throw MockLLMURLProtocol.Error.unexpectedHeader
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
    }
}

private final class MockLLMURLProtocol: URLProtocol {
    enum Error: Swift.Error {
        case missingHandler
        case unexpectedURL
        case unexpectedHeader
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
