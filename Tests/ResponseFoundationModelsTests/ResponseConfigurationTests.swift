#if RESPONSE_ENABLED
import Testing
import Foundation
@testable import ResponseFoundationModels

@Suite("ResponseConfiguration Tests")
struct ResponseConfigurationTests {

    @Test("Default base URL is OpenAI")
    func defaultBaseURL() {
        let config = ResponseConfiguration(apiKey: "test-key")
        #expect(config.baseURL == URL(string: "https://api.openai.com/v1")!)
    }

    @Test("Custom base URL is preserved")
    func customBaseURL() {
        let url = URL(string: "https://custom.api.com/v2")!
        let config = ResponseConfiguration(baseURL: url, apiKey: "test-key")
        #expect(config.baseURL == url)
    }

    @Test("Default timeout is 120 seconds")
    func defaultTimeout() {
        let config = ResponseConfiguration(apiKey: "test-key")
        #expect(config.timeout == 120)
    }

    @Test("Custom timeout is preserved")
    func customTimeout() {
        let config = ResponseConfiguration(apiKey: "key", timeout: 60)
        #expect(config.timeout == 60)
    }

    @Test("API key is preserved")
    func apiKey() {
        let config = ResponseConfiguration(apiKey: "sk-test-123")
        #expect(config.apiKey == "sk-test-123")
    }
}

#endif
