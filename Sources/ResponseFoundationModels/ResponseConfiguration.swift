#if RESPONSE_ENABLED
import Foundation

/// Configuration for the OpenAI Responses API backend
public struct ResponseConfiguration: Sendable {
    /// Base URL for the API (e.g. https://api.openai.com/v1)
    public let baseURL: URL
    /// API key for authentication
    public let apiKey: String
    /// Request timeout interval
    public let timeout: TimeInterval

    public init(
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        apiKey: String,
        timeout: TimeInterval = 120
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.timeout = timeout
    }
}

#endif
