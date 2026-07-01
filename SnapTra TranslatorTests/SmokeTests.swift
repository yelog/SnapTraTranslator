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
        LLMProviderCredentialStore.clearTestAPIKeyOverrides()
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

    func testLLMPromptNormalizesOCRWrappedLineBreaksSemantically() async throws {
        let stream = """
        data: {"choices":[{"delta":{"content":"如果你已经意识到自己经验不足，就不应该把时间用来练习吗？"}}]}

        data: [DONE]

        """
        var requestBody: [String: Any]?

        MockLLMURLProtocol.requestHandler = { request in
            guard request.url?.absoluteString == "https://llm.example/v1/chat/completions" else {
                throw MockLLMURLProtocol.Error.unexpectedURL
            }
            requestBody = try request.jsonBody()

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
            text: """
            If you're
            aware enough
            to know you're
            inexperienced,
            then shouldn't
            you be using
            your time to
            practice?
            """,
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

        XCTAssertEqual(translation, "如果你已经意识到自己经验不足，就不应该把时间用来练习吗？")

        let messages = try XCTUnwrap(requestBody?["messages"] as? [[String: Any]])
        let systemPrompt = try XCTUnwrap(messages.first?["content"] as? String)
        let userPrompt = try XCTUnwrap(messages.dropFirst().first?["content"] as? String)

        XCTAssertTrue(systemPrompt.contains("Normalize OCR line breaks by meaning"))
        XCTAssertTrue(systemPrompt.contains("if a line break only splits one continuous sentence"))
        XCTAssertTrue(systemPrompt.contains("Preserve line breaks that carry structure or meaning"))
        XCTAssertTrue(systemPrompt.contains("list items"))
        XCTAssertTrue(userPrompt.contains("If you're\naware enough\nto know you're"))
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
        configureTemporaryOpenAIAPIKey()

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
        configureTemporaryOpenAIAPIKey()

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

    func testZhipuStreamingUsesInternationalURLAndDisablesThinking() async throws {
        configureTemporaryZhipuAPIKey()

        let stream = """
        data: {"choices":[{"delta":{"content":"你好"}}]}

        data: [DONE]

        """
        var requestBody: [String: Any]?

        MockLLMURLProtocol.requestHandler = { request in
            guard request.url?.absoluteString == "https://api.z.ai/api/paas/v4/chat/completions" else {
                throw MockLLMURLProtocol.Error.unexpectedURL
            }
            guard request.value(forHTTPHeaderField: "Authorization") == "Bearer zhipu-test-key" else {
                throw MockLLMURLProtocol.Error.unexpectedHeader
            }
            requestBody = try request.jsonBody()

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
            provider: .zhipu,
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            llmConfiguration: LLMProviderConfiguration(
                provider: .zhipu,
                zhipuRegion: .international
            ),
            onPartialResult: { _ in }
        )

        XCTAssertEqual(translation, "你好")
        XCTAssertEqual(requestBody?["model"] as? String, "glm-4.7-flash")
        XCTAssertEqual(requestBody?["stream"] as? Bool, true)
        let thinking = try XCTUnwrap(requestBody?["thinking"] as? [String: Any])
        XCTAssertEqual(thinking["type"] as? String, "disabled")
        XCTAssertNil(requestBody?["think"])
        XCTAssertNil(requestBody?["reasoning_effort"])
    }

    private func configureTemporaryOpenAIAPIKey() {
        LLMProviderCredentialStore.setTestAPIKeyOverride("test-api-key", for: .openAI)
    }

    private func configureTemporaryZhipuAPIKey() {
        LLMProviderCredentialStore.setTestAPIKeyOverride("zhipu-test-key", for: .zhipu)
    }
}

final class ImageTranslationServiceTests: XCTestCase {
    override func tearDown() {
        ImageTranslationCredentialStore.clearTestSecretOverrides()
        MockLLMURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testBaiduImageTranslationFetchesAccessTokenWithAPIKeyAndSecretBeforeV2Request() async throws {
        configureTemporaryBaiduSecret()

        let translatedImageBase64 = Data("translated-image".utf8).base64EncodedString()
        var requestURLs: [String] = []

        MockLLMURLProtocol.requestHandler = { request in
            requestURLs.append(request.url?.absoluteString ?? "")

            if request.url?.host == "aip.baidubce.com" {
                guard request.url?.path == "/oauth/2.0/token" else {
                    throw MockLLMURLProtocol.Error.unexpectedURL
                }
                guard request.httpMethod == "POST" else {
                    throw MockLLMURLProtocol.Error.unexpectedHeader
                }

                let queryItems = Dictionary(
                    uniqueKeysWithValues: URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                        .queryItems?
                        .compactMap { item in item.value.map { (item.name, $0) } } ?? []
                )
                XCTAssertEqual(queryItems["grant_type"], "client_credentials")
                XCTAssertEqual(queryItems["client_id"], "test-api-key")
                XCTAssertEqual(queryItems["client_secret"], "test-secret")

                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!,
                    Data(#"{"access_token":"oauth-access-token","expires_in":2592000}"#.utf8)
                )
            }

            guard request.url?.absoluteString == "https://fanyi-api.baidu.com/ait/api/picture/translate" else {
                throw MockLLMURLProtocol.Error.unexpectedURL
            }
            guard request.value(forHTTPHeaderField: "Authorization") == "Bearer oauth-access-token" else {
                throw MockLLMURLProtocol.Error.unexpectedHeader
            }

            let response = """
            {"from":"en","to":"zh","src":"Hello","dst":"你好","paste_img":"\(translatedImageBase64)","contents":[]}
            """
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(response.utf8)
            )
        }

        let service = ImageTranslationService(session: .mockLLM)
        let result = try await service.translate(
            imageData: Data("fake-png-data".utf8),
            provider: .baidu,
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            configuration: ImageTranslationProviderConfiguration(
                provider: .baidu,
                appID: "test-appid",
                apiKey: "test-api-key",
                endpoint: "https://fanyi-api.baidu.com/ait/api/picture/translate"
            )
        )

        XCTAssertEqual(result.translatedText, "你好")
        XCTAssertEqual(requestURLs.count, 2)
        XCTAssertEqual(requestURLs.first?.contains("https://aip.baidubce.com/oauth/2.0/token"), true)
        XCTAssertEqual(requestURLs.last, "https://fanyi-api.baidu.com/ait/api/picture/translate")
    }

    func testBaiduImageTranslationUsesV2JSONRequestAndReturnsTranslatedImage() async throws {
        configureTemporaryBaiduSecret()

        let imageData = Data("fake-png-data".utf8)
        let translatedImageBase64 = Data("translated-image".utf8).base64EncodedString()
        var capturedRequest: URLRequest?
        var capturedBody: [String: Any]?

        MockLLMURLProtocol.requestHandler = { request in
            guard request.url?.absoluteString == "https://fanyi-api.baidu.com/ait/api/picture/translate" else {
                throw MockLLMURLProtocol.Error.unexpectedURL
            }
            guard request.httpMethod == "POST" else {
                throw MockLLMURLProtocol.Error.unexpectedHeader
            }
            guard request.value(forHTTPHeaderField: "Content-Type") == "application/json" else {
                throw MockLLMURLProtocol.Error.unexpectedHeader
            }
            guard request.value(forHTTPHeaderField: "Authorization") == "Bearer test-secret" else {
                throw MockLLMURLProtocol.Error.unexpectedHeader
            }
            capturedRequest = request
            capturedBody = try JSONSerialization.jsonObject(with: request.rawBody()) as? [String: Any]

            let response = """
            {"from":"en","to":"zh","src":"Hello","dst":"你好","paste_img":"\(translatedImageBase64)","contents":[]}
            """
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(response.utf8)
            )
        }

        let service = ImageTranslationService(session: .mockLLM)
        let result = try await service.translate(
            imageData: imageData,
            provider: .baidu,
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            configuration: ImageTranslationProviderConfiguration(
                provider: .baidu,
                appID: "test-appid",
                endpoint: "https://fanyi-api.baidu.com/ait/api/picture/translate"
            )
        )

        XCTAssertEqual(result.translatedText, "你好")
        XCTAssertEqual(result.pasteImageBase64, translatedImageBase64)
        let request = try XCTUnwrap(capturedRequest)
        let queryItems = Dictionary(
            uniqueKeysWithValues: URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
                .queryItems?
                .compactMap { item in item.value.map { (item.name, $0) } } ?? []
        )
        XCTAssertNil(queryItems["access_token"])
        XCTAssertNil(queryItems["sign"])

        let body = try XCTUnwrap(capturedBody)
        XCTAssertEqual(body["from"] as? String, "auto")
        XCTAssertEqual(body["to"] as? String, "zh")
        XCTAssertEqual(body["appid"] as? String, "test-appid")
        XCTAssertEqual(body["content"] as? String, imageData.base64EncodedString())
        XCTAssertEqual(body["paste"] as? Int, 1)
        XCTAssertEqual(body["need_intervene"] as? Int, 0)
        XCTAssertEqual(body["view_type"] as? Int, 1)
        XCTAssertEqual(body["model_type"] as? String, "nmt")
    }

    func testBaiduImageTranslationReportsNumericV2ErrorCode() async throws {
        configureTemporaryBaiduSecret()

        MockLLMURLProtocol.requestHandler = { request in
            guard request.url?.absoluteString == "https://fanyi-api.baidu.com/ait/api/picture/translate" else {
                throw MockLLMURLProtocol.Error.unexpectedURL
            }
            guard request.value(forHTTPHeaderField: "Authorization") == "Bearer test-secret" else {
                throw MockLLMURLProtocol.Error.unexpectedHeader
            }

            let response = """
            {"error_code":55002,"error_msg":"Token 校验未通过"}
            """
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(response.utf8)
            )
        }

        let service = ImageTranslationService(session: .mockLLM)

        do {
            _ = try await service.translate(
                imageData: Data("fake-png-data".utf8),
                provider: .baidu,
                sourceLanguage: "en",
                targetLanguage: "zh-Hans",
                configuration: ImageTranslationProviderConfiguration(
                    provider: .baidu,
                    appID: "test-appid",
                    endpoint: "https://fanyi-api.baidu.com/ait/api/picture/translate"
                )
            )
            XCTFail("Expected Baidu provider rejection")
        } catch SentenceTranslationError.providerRejected(let provider, let code, let message) {
            XCTAssertEqual(provider, ImageTranslationProvider.baidu.displayName)
            XCTAssertEqual(code, 55002)
            XCTAssertTrue(message?.contains("Token 校验未通过") == true)
            XCTAssertTrue(message?.contains("V2 Access Token") == true)
            XCTAssertTrue(message?.contains("APP Secret") == true)
            XCTAssertFalse(message?.localizedCaseInsensitiveContains("legacy") == true)
        }
    }

    func testBaiduImageTranslationNormalizesDeprecatedEndpointToV2JSONRequest() async throws {
        configureTemporaryBaiduSecret()

        let imageData = Data("fake-png-data".utf8)
        let translatedImageBase64 = Data("translated-image".utf8).base64EncodedString()
        var capturedRequest: URLRequest?
        var capturedBody: [String: Any]?

        MockLLMURLProtocol.requestHandler = { request in
            guard request.url?.absoluteString == "https://fanyi-api.baidu.com/ait/api/picture/translate" else {
                throw MockLLMURLProtocol.Error.unexpectedURL
            }
            guard request.httpMethod == "POST" else {
                throw MockLLMURLProtocol.Error.unexpectedHeader
            }
            guard request.value(forHTTPHeaderField: "Content-Type") == "application/json" else {
                throw MockLLMURLProtocol.Error.unexpectedHeader
            }
            guard request.value(forHTTPHeaderField: "Authorization") == "Bearer test-secret" else {
                throw MockLLMURLProtocol.Error.unexpectedHeader
            }
            capturedRequest = request
            capturedBody = try JSONSerialization.jsonObject(with: request.rawBody()) as? [String: Any]

            let response = """
            {"from":"en","to":"zh","src":"Hello","dst":"你好","paste_img":"\(translatedImageBase64)","contents":[]}
            """
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(response.utf8)
            )
        }

        let service = ImageTranslationService(session: .mockLLM)
        let result = try await service.translate(
            imageData: imageData,
            provider: .baidu,
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            configuration: ImageTranslationProviderConfiguration(
                provider: .baidu,
                appID: "test-appid",
                endpoint: "https://fanyi-api.baidu.com/api/trans/sdk/picture"
            )
        )

        XCTAssertEqual(result.translatedText, "你好")
        XCTAssertEqual(result.pasteImageBase64, translatedImageBase64)
        let request = try XCTUnwrap(capturedRequest)
        let queryItems = Dictionary(
            uniqueKeysWithValues: URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
                .queryItems?
                .compactMap { item in item.value.map { (item.name, $0) } } ?? []
        )
        XCTAssertNil(queryItems["sign"])
        XCTAssertNil(queryItems["access_token"])

        let body = try XCTUnwrap(capturedBody)
        XCTAssertEqual(body["from"] as? String, "auto")
        XCTAssertEqual(body["to"] as? String, "zh")
        XCTAssertEqual(body["appid"] as? String, "test-appid")
        XCTAssertEqual(body["content"] as? String, imageData.base64EncodedString())
    }

    func testBaiduImageTranslationRejectsDeprecatedResponseShape() async throws {
        configureTemporaryBaiduSecret()

        MockLLMURLProtocol.requestHandler = { request in
            guard request.url?.absoluteString == "https://fanyi-api.baidu.com/ait/api/picture/translate" else {
                throw MockLLMURLProtocol.Error.unexpectedURL
            }

            let response = """
            {"error_code":"0","error_msg":"success","data":{"from":"en","to":"zh","sumSrc":"Hello","sumDst":"你好","pasteImg":"deprecated","content":[]}}
            """
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(response.utf8)
            )
        }

        let service = ImageTranslationService(session: .mockLLM)

        do {
            _ = try await service.translate(
                imageData: Data("fake-png-data".utf8),
                provider: .baidu,
                sourceLanguage: "en",
                targetLanguage: "zh-Hans",
                configuration: ImageTranslationProviderConfiguration(
                    provider: .baidu,
                    appID: "test-appid",
                    endpoint: "https://fanyi-api.baidu.com/ait/api/picture/translate"
                )
            )
            XCTFail("Expected V2 response validation to reject deprecated response shape")
        } catch SentenceTranslationError.invalidResponse {
        }
    }

    private func configureTemporaryBaiduSecret() {
        ImageTranslationCredentialStore.setTestSecretOverride("test-secret", for: .baidu)
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

    func rawBody() throws -> Data {
        if let httpBody {
            return httpBody
        }
        if let httpBodyStream {
            return try Data(reading: httpBodyStream)
        }
        throw MockLLMURLProtocol.Error.missingBody
    }
}

private extension Data {
    func contains(_ needle: Data) -> Bool {
        range(of: needle) != nil
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
