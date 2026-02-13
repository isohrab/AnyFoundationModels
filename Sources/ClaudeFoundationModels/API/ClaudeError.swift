#if CLAUDE_ENABLED
import Foundation

/// Error response from Claude API
public struct ClaudeErrorResponse: Codable, Error, LocalizedError, Sendable {
    public let type: String
    public let error: ErrorDetail

    public struct ErrorDetail: Codable, Sendable {
        public let type: String
        public let message: String
    }

    public var errorDescription: String? {
        return "\(error.type): \(error.message)"
    }
}

#endif
