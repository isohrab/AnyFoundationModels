#if CLAUDE_ENABLED
import Foundation

/// Content block in messages (request)
enum ContentBlock: Codable, Sendable {
    case text(TextBlock)
    case toolUse(ToolUseBlock)
    case toolResult(ToolResultBlock)
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
        case "tool_result":
            let block = try ToolResultBlock(from: decoder)
            self = .toolResult(block)
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
                debugDescription: "Unknown content block type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let block):
            try block.encode(to: encoder)
        case .toolUse(let block):
            try block.encode(to: encoder)
        case .toolResult(let block):
            try block.encode(to: encoder)
        case .thinking(let block):
            try block.encode(to: encoder)
        case .redactedThinking(let block):
            try block.encode(to: encoder)
        }
    }
}

/// Text content block
struct TextBlock: Codable, Sendable {
    let type: String
    let text: String

    init(text: String) {
        self.type = "text"
        self.text = text
    }
}

/// Tool use content block (in assistant response)
struct ToolUseBlock: Codable, Sendable {
    let type: String
    let id: String
    let name: String
    let input: JSONValue

    init(id: String, name: String, input: JSONValue) {
        self.type = "tool_use"
        self.id = id
        self.name = name
        self.input = input
    }
}

/// Tool result content block (in user message)
struct ToolResultBlock: Codable, Sendable {
    let type: String
    let toolUseId: String
    let content: String
    let isError: Bool?

    init(toolUseId: String, content: String, isError: Bool? = nil) {
        self.type = "tool_result"
        self.toolUseId = toolUseId
        self.content = content
        self.isError = isError
    }

    enum CodingKeys: String, CodingKey {
        case type
        case toolUseId = "tool_use_id"
        case content
        case isError = "is_error"
    }
}

/// Thinking content block (Extended Thinking response)
struct ThinkingBlock: Codable, Sendable {
    let type: String
    let thinking: String
    let signature: String?

    init(thinking: String, signature: String? = nil) {
        self.type = "thinking"
        self.thinking = thinking
        self.signature = signature
    }
}

/// Redacted thinking content block
struct RedactedThinkingBlock: Codable, Sendable {
    let type: String
    let data: String

    init(data: String) {
        self.type = "redacted_thinking"
        self.data = data
    }
}

#endif
