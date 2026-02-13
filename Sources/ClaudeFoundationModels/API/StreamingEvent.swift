#if CLAUDE_ENABLED
import Foundation

/// Streaming event from Claude API
enum StreamingEvent: Sendable {
    case messageStart(MessageStartEvent)
    case contentBlockStart(ContentBlockStartEvent)
    case contentBlockDelta(ContentBlockDeltaEvent)
    case contentBlockStop(ContentBlockStopEvent)
    case messageDelta(MessageDeltaEvent)
    case messageStop(MessageStopEvent)
    case ping
    case error(ErrorEvent)
}

struct MessageStartEvent: Codable, Sendable {
    let type: String
    let message: PartialMessage

    struct PartialMessage: Codable, Sendable {
        let id: String
        let type: String
        let role: String
        let model: String
        let usage: Usage?
    }
}

struct ContentBlockStartEvent: Codable, Sendable {
    let type: String
    let index: Int
    let contentBlock: StartContentBlock

    enum CodingKeys: String, CodingKey {
        case type, index
        case contentBlock = "content_block"
    }

    enum StartContentBlock: Codable, Sendable {
        case text(TextStartBlock)
        case toolUse(ToolUseStartBlock)
        case thinking(ThinkingStartBlock)

        enum CodingKeys: String, CodingKey {
            case type
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)

            switch type {
            case "text":
                let block = try TextStartBlock(from: decoder)
                self = .text(block)
            case "tool_use":
                let block = try ToolUseStartBlock(from: decoder)
                self = .toolUse(block)
            case "thinking":
                let block = try ThinkingStartBlock(from: decoder)
                self = .thinking(block)
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "Unknown start content block type: \(type)"
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
            }
        }
    }

    struct TextStartBlock: Codable, Sendable {
        let type: String
        let text: String
    }

    struct ToolUseStartBlock: Codable, Sendable {
        let type: String
        let id: String
        let name: String
    }

    struct ThinkingStartBlock: Codable, Sendable {
        let type: String
        let thinking: String
    }
}

struct ContentBlockDeltaEvent: Codable, Sendable {
    let type: String
    let index: Int
    let delta: Delta

    enum Delta: Codable, Sendable {
        case textDelta(TextDelta)
        case inputJSONDelta(InputJSONDelta)
        case thinkingDelta(ThinkingDelta)
        case signatureDelta(SignatureDelta)

        enum CodingKeys: String, CodingKey {
            case type
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)

            switch type {
            case "text_delta":
                let delta = try TextDelta(from: decoder)
                self = .textDelta(delta)
            case "input_json_delta":
                let delta = try InputJSONDelta(from: decoder)
                self = .inputJSONDelta(delta)
            case "thinking_delta":
                let delta = try ThinkingDelta(from: decoder)
                self = .thinkingDelta(delta)
            case "signature_delta":
                let delta = try SignatureDelta(from: decoder)
                self = .signatureDelta(delta)
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "Unknown delta type: \(type)"
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .textDelta(let delta):
                try delta.encode(to: encoder)
            case .inputJSONDelta(let delta):
                try delta.encode(to: encoder)
            case .thinkingDelta(let delta):
                try delta.encode(to: encoder)
            case .signatureDelta(let delta):
                try delta.encode(to: encoder)
            }
        }
    }

    struct TextDelta: Codable, Sendable {
        let type: String
        let text: String
    }

    struct InputJSONDelta: Codable, Sendable {
        let type: String
        let partialJson: String

        enum CodingKeys: String, CodingKey {
            case type
            case partialJson = "partial_json"
        }
    }

    struct ThinkingDelta: Codable, Sendable {
        let type: String
        let thinking: String
    }

    struct SignatureDelta: Codable, Sendable {
        let type: String
        let signature: String
    }
}

struct ContentBlockStopEvent: Codable, Sendable {
    let type: String
    let index: Int
}

struct MessageDeltaEvent: Codable, Sendable {
    let type: String
    let delta: DeltaInfo
    let usage: Usage?

    struct DeltaInfo: Codable, Sendable {
        let stopReason: String?
        let stopSequence: String?

        enum CodingKeys: String, CodingKey {
            case stopReason = "stop_reason"
            case stopSequence = "stop_sequence"
        }
    }
}

struct MessageStopEvent: Codable, Sendable {
    let type: String
}

struct ErrorEvent: Codable, Sendable {
    let type: String
    let error: ErrorInfo

    struct ErrorInfo: Codable, Sendable {
        let type: String
        let message: String
    }
}

#endif
