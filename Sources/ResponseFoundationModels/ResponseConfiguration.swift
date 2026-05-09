#if RESPONSE_ENABLED
import Foundation

/// Configuration for the OpenAI Responses API backend
public struct ResponseConfiguration: Sendable {
    /// Base URL for the API (e.g. https://api.openai.com/v1)
    public let baseURL: URL
    /// Request timeout interval
    public let timeout: TimeInterval

    // MARK: - Internal key representation

    private enum APIKeySource: Sendable {
        case `static`(String)
        case provider(@Sendable (_ forceRefresh: Bool) async throws -> String)
    }

    private let apiKeySource: APIKeySource

    // MARK: - Initialisers

    /// Static API key initialiser — kept for backward compatibility.
    ///
    /// Use this when a fixed, long-lived key is sufficient (tests, previews,
    /// third-party integrations that do not use rotating credentials).
    public init(
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        apiKey: String,
        timeout: TimeInterval = 120
    ) {
        self.baseURL = baseURL
        self.timeout = timeout
        self.apiKeySource = .static(apiKey)
    }

    /// Dynamic API key initialiser.
    ///
    /// Use this when the credential is short-lived (e.g. a backend-issued token
    /// with a ~1 hour TTL). The framework calls `apiKeyProvider` just before
    /// every outgoing request.
    ///
    /// - Parameters:
    ///   - baseURL: Base URL of the API.
    ///   - timeout: Request timeout in seconds (default 120).
    ///   - apiKeyProvider: An async, throwing, `@Sendable` closure that returns
    ///     the current API key. The `forceRefresh` parameter is `false` on normal
    ///     requests and `true` when the framework is retrying after a `401`
    ///     response — use it to bypass any in-memory cache and force a fresh
    ///     credential fetch.
    public init(
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        timeout: TimeInterval = 120,
        apiKeyProvider: @Sendable @escaping (_ forceRefresh: Bool) async throws -> String
    ) {
        self.baseURL = baseURL
        self.timeout = timeout
        self.apiKeySource = .provider(apiKeyProvider)
    }

    // MARK: - Internal resolver

    /// Called by `ResponseHTTPClient` immediately before building each URL request.
    ///
    /// - Parameter forceRefresh: Pass `true` when retrying after a `401` so that
    ///   a provider-based configuration can skip its cache and fetch a fresh key.
    func resolveAPIKey(forceRefresh: Bool = false) async throws -> String {
        switch apiKeySource {
        case .static(let key):
            return key
        case .provider(let provider):
            return try await provider(forceRefresh)
        }
    }

    // MARK: - Backward-compatibility accessor

    /// The static API key, if this configuration was created with `init(apiKey:)`.
    ///
    /// Returns `nil` when using a provider-based configuration.
    public var apiKey: String? {
        switch apiKeySource {
        case .static(let key): return key
        case .provider: return nil
        }
    }
}

#endif
