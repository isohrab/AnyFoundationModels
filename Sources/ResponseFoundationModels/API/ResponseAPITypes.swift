#if RESPONSE_ENABLED
import Foundation
import JSONSchema

// MARK: - Request Types

/// Request body for POST /v1/responses
struct ResponsesRequest: Encodable, Sendable {
    let model: String
    let input: [InputItem]
    var instructions: String?
    var tools: [ToolDefinition]?
    var toolChoice: ToolChoice?
    var stream: Bool?
    var temperature: Double?
    var topP: Double?
    var maxOutputTokens: Int?
    var text: TextFormat?

    enum CodingKeys: String, CodingKey {
        case model, input, instructions, tools, stream, temperature, text
        case toolChoice = "tool_choice"
        case topP = "top_p"
        case maxOutputTokens = "max_output_tokens"
    }
}

/// Union type for input items
enum InputItem: Encodable, Sendable {
    case message(MessageItem)
    case functionCall(FunctionCallItem)
    case functionCallOutput(FunctionCallOutputItem)

    func encode(to encoder: Encoder) throws {
        switch self {
        case .message(let item):
            try item.encode(to: encoder)
        case .functionCall(let item):
            try item.encode(to: encoder)
        case .functionCallOutput(let item):
            try item.encode(to: encoder)
        }
    }
}

/// Message input item (system, user, assistant)
struct MessageItem: Encodable, Sendable {
    let type: String = "message"
    let role: String
    let content: MessageItemContent

    init(role: String, content: String) {
        self.role = role
        self.content = .text(content)
    }

    init(role: String, content: [InputContentPart]) {
        self.role = role
        self.content = .parts(content)
    }

    enum MessageItemContent: Encodable, Sendable, Equatable {
        case text(String)
        case parts([InputContentPart])

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let text):
                try container.encode(text)
            case .parts(let parts):
                try container.encode(parts)
            }
        }
    }
}

/// Content part for multi-modal input
struct InputContentPart: Encodable, Sendable, Equatable {
    enum PartType: Equatable {
        case inputText(String)
        case inputImage(url: String)
    }

    let part: PartType

    enum CodingKeys: String, CodingKey {
        case type, text
        case imageUrl = "image_url"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch part {
        case .inputText(let text):
            try container.encode("input_text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .inputImage(let url):
            try container.encode("input_image", forKey: .type)
            try container.encode(url, forKey: .imageUrl)
        }
    }

    static func text(_ text: String) -> InputContentPart {
        InputContentPart(part: .inputText(text))
    }

    static func image(url: String) -> InputContentPart {
        InputContentPart(part: .inputImage(url: url))
    }
}

/// Function call item in input (for multi-turn)
struct FunctionCallItem: Encodable, Sendable {
    let type: String = "function_call"
    let id: String?
    let callId: String
    let name: String
    let arguments: String
    let status: String?

    enum CodingKeys: String, CodingKey {
        case type, id, name, arguments, status
        case callId = "call_id"
    }
}

/// Function call output item in input (for multi-turn)
struct FunctionCallOutputItem: Encodable, Sendable {
    let type: String = "function_call_output"
    let callId: String
    let output: String

    enum CodingKeys: String, CodingKey {
        case type, output
        case callId = "call_id"
    }
}

/// Tool definition
struct ToolDefinition: Encodable, Sendable {
    let type: String = "function"
    let name: String
    let description: String?
    let parameters: JSONSchemaObject?
    let strict: Bool?
}

/// JSON Schema object for tool parameters
struct JSONSchemaObject: Encodable, Sendable {
    let type: String
    let properties: [String: JSONSchemaProperty]?
    let required: [String]?
    let additionalProperties: Bool?
}

/// JSON Schema property (indirect via class to avoid recursive struct)
final class JSONSchemaProperty: Encodable, Sendable {
    let type: String
    let description: String?
    let enumValues: [String]?
    let items: JSONSchemaProperty?
    let properties: [String: JSONSchemaProperty]?
    let required: [String]?

    init(
        type: String,
        description: String? = nil,
        enumValues: [String]? = nil,
        items: JSONSchemaProperty? = nil,
        properties: [String: JSONSchemaProperty]? = nil,
        required: [String]? = nil
    ) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
        self.items = items
        self.properties = properties
        self.required = required
    }

    enum CodingKeys: String, CodingKey {
        case type, description, items, properties, required
        case enumValues = "enum"
    }
}

/// Tool choice
enum ToolChoice: Encodable, Sendable {
    case auto
    case none
    case required
    case function(name: String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .auto:
            try container.encode("auto")
        case .none:
            try container.encode("none")
        case .required:
            try container.encode("required")
        case .function(let name):
            try container.encode(["type": "function", "name": name])
        }
    }
}

/// Text format for structured output
struct TextFormat: Encodable, Sendable {
    let format: FormatType

    enum FormatType: Encodable, Sendable {
        case text
        case jsonObject
        case jsonSchema(name: String, schema: JSONValue, strict: Bool?)

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text:
                try container.encode("text", forKey: .type)
            case .jsonObject:
                try container.encode("json_object", forKey: .type)
            case .jsonSchema(let name, let schema, let strict):
                try container.encode("json_schema", forKey: .type)
                try container.encode(name, forKey: .name)
                try container.encode(schema, forKey: .schema)
                if let strict = strict {
                    try container.encode(strict, forKey: .strict)
                }
            }

            enum CodingKeys: String, CodingKey {
                case type, name, schema, strict
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case format
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(format, forKey: .format)
    }
}

// MARK: - Response Types

/// Response object from POST /v1/responses
struct ResponseObject: Decodable {
    let id: String
    let object: String
    let status: String?
    let output: [OutputItem]
    let usage: Usage?

    struct Usage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let totalTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

/// Output item in response
enum OutputItem: Decodable {
    case message(MessageOutput)
    case functionCall(FunctionCallOutput)

    struct MessageOutput: Decodable {
        let id: String?
        let type: String
        let role: String?
        let content: [ContentPart]?
    }

    struct ContentPart: Decodable {
        let type: String
        let text: String?
    }

    struct FunctionCallOutput: Decodable {
        let id: String?
        let type: String
        let callId: String?
        let name: String?
        let arguments: String?
        let status: String?

        enum CodingKeys: String, CodingKey {
            case id, type, name, arguments, status
            case callId = "call_id"
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "function_call":
            let output = try FunctionCallOutput(from: decoder)
            self = .functionCall(output)
        default:
            let output = try MessageOutput(from: decoder)
            self = .message(output)
        }
    }
}

#endif
