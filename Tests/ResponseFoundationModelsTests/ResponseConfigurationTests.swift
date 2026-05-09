#if RESPONSE_ENABLED
import Testing
import Foundation
@testable import ResponseFoundationModels

@Suite("ResponseConfiguration Tests")
struct ResponseConfigurationTests {

    // MARK: - Static-key initialiser (backward-compatible path)

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

    @Test("Static init — apiKey property returns the key")
    func apiKeyStaticInit() {
        let config = ResponseConfiguration(apiKey: "sk-test-123")
        #expect(config.apiKey == "sk-test-123")
    }

    @Test("Static init — resolveAPIKey returns key without calling any provider")
    func resolveAPIKeyStaticInit() async throws {
        let config = ResponseConfiguration(apiKey: "sk-static")
        let resolved = try await config.resolveAPIKey()
        #expect(resolved == "sk-static")
    }

    @Test("Static init — resolveAPIKey with forceRefresh still returns key")
    func resolveAPIKeyStaticInitForceRefresh() async throws {
        let config = ResponseConfiguration(apiKey: "sk-static")
        let resolved = try await config.resolveAPIKey(forceRefresh: true)
        #expect(resolved == "sk-static")
    }

    // MARK: - Provider-based initialiser

    @Test("Provider init — apiKey property is nil")
    func providerInitAPIKeyIsNil() {
        let config = ResponseConfiguration(apiKeyProvider: { _ in "key" })
        #expect(config.apiKey == nil)
    }

    @Test("Provider init — resolveAPIKey calls provider with forceRefresh false")
    func providerInitCallsProviderWithForceRefreshFalse() async throws {
        // The provider returns a distinct string per flag value.
        // If the framework passes forceRefresh=false the resolved key will be
        // "key-normal"; any other value would produce a different string,
        // implicitly asserting that the correct flag was forwarded.
        let config = ResponseConfiguration(apiKeyProvider: { forceRefresh in
            forceRefresh ? "key-forced" : "key-normal"
        })

        let resolved = try await config.resolveAPIKey(forceRefresh: false)
        #expect(resolved == "key-normal")
    }

    @Test("Provider init — resolveAPIKey calls provider with forceRefresh true")
    func providerInitCallsProviderWithForceRefreshTrue() async throws {
        // Symmetric: assert that forceRefresh=true is forwarded correctly.
        let config = ResponseConfiguration(apiKeyProvider: { forceRefresh in
            forceRefresh ? "key-forced" : "key-normal"
        })

        let resolved = try await config.resolveAPIKey(forceRefresh: true)
        #expect(resolved == "key-forced")
    }

    @Test("Provider init — resolveAPIKey propagates thrown errors")
    func providerInitPropagatesErrors() async {
        struct FakeAuthError: Error {}

        let config = ResponseConfiguration(apiKeyProvider: { _ in
            throw FakeAuthError()
        })

        await #expect(throws: FakeAuthError.self) {
            try await config.resolveAPIKey()
        }
    }
}

#endif
