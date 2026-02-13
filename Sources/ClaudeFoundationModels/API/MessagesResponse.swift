#if CLAUDE_ENABLED
import Foundation

/// Service tier for the request
enum ServiceTier: String, Codable, Sendable {
    case standard
    case priority
    case batch
}

/// Response from /v1/messages endpoint
struct MessagesResponse: Codable, Sendable {
    let id: String
    let type: String
    let role: String
    let content: [ResponseContentBlock]
    let model: String
    let stopReason: String?
    let stopSequence: String?
    let usage: Usage
    let serviceTier: ServiceTier?

    enum CodingKeys: String, CodingKey {
        case id, type, role, content, model, usage
        case stopReason = "stop_reason"
        case stopSequence = "stop_sequence"
        case serviceTier = "service_tier"
    }
}

/// Content block in response
enum ResponseContentBlock: Codable, Sendable {
    case text(TextBlock)
    case toolUse(ToolUseBlock)
    case thinking(ThinkingBlock)
    case redactedThinking(RedactedThinkingBlock)

    enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            let block = try TextBlock(from: decoder)
            self = .text(block)
        case "tool_use":
            let block = try ToolUseBlock(from: decoder)
            self = .toolUse(block)
        case "thinking":
            let block = try ThinkingBlock(from: decoder)
            self = .thinking(block)
        case "redacted_thinking":
            let block = try RedactedThinkingBlock(from: decoder)
            self = .redactedThinking(block)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown response content block type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let block):
            try block.encode(to: encoder)
        case .toolUse(let block):
            try block.encode(to: encoder)
        case .thinking(let block):
            try block.encode(to: encoder)
        case .redactedThinking(let block):
            try block.encode(to: encoder)
        }
    }
}

/// Cache creation breakdown by TTL
struct CacheCreation: Codable, Sendable {
    let ephemeral1hInputTokens: Int?
    let ephemeral5mInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case ephemeral1hInputTokens = "ephemeral_1h_input_tokens"
        case ephemeral5mInputTokens = "ephemeral_5m_input_tokens"
    }
}

/// Token usage information
struct Usage: Codable, Sendable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreation: CacheCreation?
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreation = "cache_creation"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
    }
}

#endif
