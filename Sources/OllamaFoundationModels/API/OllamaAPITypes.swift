#if OLLAMA_ENABLED
import Foundation
import JSONSchema

// MARK: - Generate API Types

/// Request for /api/generate endpoint
public struct GenerateRequest: Codable, Sendable {
    public let model: String
    public let prompt: String
    public let stream: Bool
    public let options: OllamaOptions?
    public let system: String?
    public let template: String?
    public let context: [Int]?
    public let raw: Bool?
    public let format: ResponseFormat?
    public let keepAlive: String?

    public init(
        model: String,
        prompt: String,
        stream: Bool = true,
        options: OllamaOptions? = nil,
        system: String? = nil,
        template: String? = nil,
        context: [Int]? = nil,
        raw: Bool? = nil,
        format: ResponseFormat? = nil,
        keepAlive: String? = nil
    ) {
        self.model = model
        self.prompt = prompt
        self.stream = stream
        self.options = options
        self.system = system
        self.template = template
        self.context = context
        self.raw = raw
        self.format = format
        self.keepAlive = keepAlive
    }

    enum CodingKeys: String, CodingKey {
        case model, prompt, stream, options, system, template, context, raw, format
        case keepAlive = "keep_alive"
    }
}

/// Response from /api/generate endpoint
public struct GenerateResponse: Codable, Sendable {
    public let model: String
    public let createdAt: Date
    public let response: String
    public let done: Bool
    public let context: [Int]?
    public let totalDuration: Int64?
    public let loadDuration: Int64?
    public let promptEvalCount: Int?
    public let promptEvalDuration: Int64?
    public let evalCount: Int?
    public let evalDuration: Int64?

    enum CodingKeys: String, CodingKey {
        case model, response, done, context
        case createdAt = "created_at"
        case totalDuration = "total_duration"
        case loadDuration = "load_duration"
        case promptEvalCount = "prompt_eval_count"
        case promptEvalDuration = "prompt_eval_duration"
        case evalCount = "eval_count"
        case evalDuration = "eval_duration"
    }
}

// MARK: - Thinking Mode

/// Controls thinking output separation in Ollama API.
///
/// When enabled, the Ollama server parses `<think>` tags and separates
/// thinking content from the main response content.
public enum ThinkingMode: Sendable, Equatable {
    /// Enable thinking and let server separate it from content
    case enabled
    /// Disable thinking output
    case disabled
    /// Control thinking effort level
    case effort(ThinkingEffort)

    /// Thinking effort levels
    public enum ThinkingEffort: String, Codable, Sendable {
        case high
        case medium
        case low
    }
}

extension ThinkingMode: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Try to decode as boolean first
        if let boolValue = try? container.decode(Bool.self) {
            self = boolValue ? .enabled : .disabled
            return
        }

        // Try to decode as string (effort level)
        if let stringValue = try? container.decode(String.self) {
            if let effort = ThinkingEffort(rawValue: stringValue) {
                self = .effort(effort)
            } else if stringValue == "true" {
                self = .enabled
            } else {
                self = .disabled
            }
            return
        }

        self = .disabled
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .enabled:
            try container.encode(true)
        case .disabled:
            try container.encode(false)
        case .effort(let level):
            try container.encode(level.rawValue)
        }
    }
}

// MARK: - Chat API Types (Internal - for Ollama API communication)

/// Request for /api/chat endpoint
struct ChatRequest: Codable, Sendable {
    let model: String
    let messages: [Message]
    let stream: Bool
    let options: OllamaOptions?
    let format: ResponseFormat?
    let keepAlive: String?
    let tools: [Tool]?
    /// Controls thinking output separation.
    /// When enabled, Ollama server parses `<think>` tags and separates thinking from content.
    let think: ThinkingMode?

    init(
        model: String,
        messages: [Message],
        stream: Bool = true,
        options: OllamaOptions? = nil,
        format: ResponseFormat? = nil,
        keepAlive: String? = nil,
        tools: [Tool]? = nil,
        think: ThinkingMode? = nil
    ) {
        self.model = model
        self.messages = messages
        self.stream = stream
        self.options = options
        self.format = format
        self.keepAlive = keepAlive
        self.tools = tools
        self.think = think
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, options, format, tools, think
        case keepAlive = "keep_alive"
    }
}

/// Response from /api/chat endpoint
struct ChatResponse: Codable, Sendable {
    let model: String
    let createdAt: Date
    let message: Message?
    let done: Bool
    let totalDuration: Int64?
    let loadDuration: Int64?
    let promptEvalCount: Int?
    let promptEvalDuration: Int64?
    let evalCount: Int?
    let evalDuration: Int64?

    enum CodingKeys: String, CodingKey {
        case model, message, done
        case createdAt = "created_at"
        case totalDuration = "total_duration"
        case loadDuration = "load_duration"
        case promptEvalCount = "prompt_eval_count"
        case promptEvalDuration = "prompt_eval_duration"
        case evalCount = "eval_count"
        case evalDuration = "eval_duration"
    }
}

/// Chat message
struct Message: Codable, Sendable {
    let role: Role
    let content: String
    let toolCalls: [ToolCall]?
    let thinking: String?
    let toolName: String?
    let images: [String]?

    init(
        role: Role,
        content: String,
        toolCalls: [ToolCall]? = nil,
        thinking: String? = nil,
        toolName: String? = nil,
        images: [String]? = nil
    ) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.thinking = thinking
        self.toolName = toolName
        self.images = images
    }

    enum CodingKeys: String, CodingKey {
        case role, content, thinking, images
        case toolCalls = "tool_calls"
        case toolName = "tool_name"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Role (default: assistant)
        if let roleString = try? container.decode(String.self, forKey: .role), !roleString.isEmpty {
            self.role = Role(rawValue: roleString) ?? .assistant
        } else {
            self.role = .assistant
        }

        // Pure decoding - no normalization or parsing
        // ResponseProcessor handles all normalization logic
        self.content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        self.thinking = try container.decodeIfPresent(String.self, forKey: .thinking)
        self.toolCalls = try container.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
        self.toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        self.images = try container.decodeIfPresent([String].self, forKey: .images)
    }
}

/// Message role
enum Role: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
    case think
}

// MARK: - Tool Types (Internal - users should use FoundationModels.Tool)

/// Tool definition for Ollama API communication
struct Tool: Codable, Sendable {
    let type: String
    let function: Function

    init(type: String = "function", function: Function) {
        self.type = type
        self.function = function
    }

    struct Function: Codable, Sendable {
        let name: String
        let description: String
        let parameters: Parameters

        init(
            name: String,
            description: String,
            parameters: Parameters
        ) {
            self.name = name
            self.description = description
            self.parameters = parameters
        }

        struct Parameters: Codable, Sendable {
            let type: String
            let properties: [String: Property]
            let required: [String]

            init(
                type: String = "object",
                properties: [String: Property],
                required: [String]
            ) {
                self.type = type
                self.properties = properties
                self.required = required
            }

            struct Property: Codable, Sendable {
                let type: String
                let description: String
                /// Enum values for string types with restricted values (anyOf)
                let `enum`: [String]?
                /// For array types, the schema of array elements (uses Box for recursive reference)
                let items: Box<Property>?
                /// For object types, nested property definitions
                let properties: [String: Property]?
                /// Required fields for nested objects
                let required: [String]?

                init(
                    type: String,
                    description: String,
                    `enum`: [String]? = nil,
                    items: Property? = nil,
                    properties: [String: Property]? = nil,
                    required: [String]? = nil
                ) {
                    self.type = type
                    self.description = description
                    self.enum = `enum`
                    self.items = items.map { Box($0) }
                    self.properties = properties
                    self.required = required
                }
            }

            /// Box type for indirect storage (enables recursive types in structs)
            ///
            /// ## @unchecked Sendable Justification
            /// This class is marked `@unchecked Sendable` because:
            /// - It is a `final class` (cannot be subclassed)
            /// - The only property `value` is immutable (`let`)
            /// - The wrapped type `T` is constrained to `Sendable`
            /// - All state is effectively immutable after initialization
            ///
            /// This provides value-semantic behavior through a reference type,
            /// which is necessary to break the recursive cycle in JSON schema types.
            final class Box<T: Codable & Sendable>: Codable, @unchecked Sendable {
                let value: T

                init(_ value: T) {
                    self.value = value
                }

                init(from decoder: Decoder) throws {
                    let container = try decoder.singleValueContainer()
                    self.value = try container.decode(T.self)
                }

                func encode(to encoder: Encoder) throws {
                    var container = encoder.singleValueContainer()
                    try container.encode(value)
                }
            }
        }
    }
}

/// Tool call from Ollama API response
struct ToolCall: Codable, Sendable {
    let function: FunctionCall

    init(function: FunctionCall) {
        self.function = function
    }

    struct FunctionCall: Codable, Sendable {
        let name: String
        let arguments: JSONValue

        init(name: String, arguments: JSONValue) {
            self.name = name
            self.arguments = arguments
        }

        enum CodingKeys: String, CodingKey {
            case name, arguments
        }
    }
}

// MARK: - Model Management Types

/// Response from /api/tags endpoint
public struct ModelsResponse: Codable, Sendable {
    public let models: [Model]

    public struct Model: Codable, Sendable {
        public let name: String
        public let model: String
        public let modifiedAt: Date
        public let size: Int64
        public let digest: String
        public let details: Details?

        enum CodingKeys: String, CodingKey {
            case name, model, size, digest, details
            case modifiedAt = "modified_at"
        }

        public struct Details: Codable, Sendable {
            public let parentModel: String?
            public let format: String?
            public let family: String?
            public let families: [String]?
            public let parameterSize: String?
            public let quantizationLevel: String?

            enum CodingKeys: String, CodingKey {
                case parentModel = "parent_model"
                case format, family, families
                case parameterSize = "parameter_size"
                case quantizationLevel = "quantization_level"
            }
        }
    }
}

/// Request for /api/show endpoint
struct ShowRequest: Codable, Sendable {
    let name: String
    let verbose: Bool?

    init(name: String, verbose: Bool? = nil) {
        self.name = name
        self.verbose = verbose
    }
}

/// Response from /api/show endpoint
struct ShowResponse: Codable, Sendable {
    let license: String?
    let modelfile: String?
    let parameters: String?
    let template: String?
    let details: ModelsResponse.Model.Details?
    let messages: [Message]?
}

// MARK: - Options

/// Ollama generation options
public struct OllamaOptions: Codable, Sendable {
    // Generation parameters
    public let numPredict: Int?
    public let temperature: Double?
    public let topK: Int?
    public let topP: Double?
    public let minP: Double?
    public let seed: Int?
    public let stop: [String]?

    // Penalties
    public let repeatPenalty: Double?
    public let presencePenalty: Double?
    public let frequencyPenalty: Double?

    // Context management
    public let numCtx: Int?
    public let numBatch: Int?
    public let numKeep: Int?

    // Model behavior
    public let typicalP: Double?
    public let tfsZ: Double?
    public let penalizeNewline: Bool?
    public let mirostat: Int?
    public let mirostatTau: Double?
    public let mirostatEta: Double?

    public init(
        numPredict: Int? = nil,
        temperature: Double? = nil,
        topK: Int? = nil,
        topP: Double? = nil,
        minP: Double? = nil,
        seed: Int? = nil,
        stop: [String]? = nil,
        repeatPenalty: Double? = nil,
        presencePenalty: Double? = nil,
        frequencyPenalty: Double? = nil,
        numCtx: Int? = nil,
        numBatch: Int? = nil,
        numKeep: Int? = nil,
        typicalP: Double? = nil,
        tfsZ: Double? = nil,
        penalizeNewline: Bool? = nil,
        mirostat: Int? = nil,
        mirostatTau: Double? = nil,
        mirostatEta: Double? = nil
    ) {
        self.numPredict = numPredict
        self.temperature = temperature
        self.topK = topK
        self.topP = topP
        self.minP = minP
        self.seed = seed
        self.stop = stop
        self.repeatPenalty = repeatPenalty
        self.presencePenalty = presencePenalty
        self.frequencyPenalty = frequencyPenalty
        self.numCtx = numCtx
        self.numBatch = numBatch
        self.numKeep = numKeep
        self.typicalP = typicalP
        self.tfsZ = tfsZ
        self.penalizeNewline = penalizeNewline
        self.mirostat = mirostat
        self.mirostatTau = mirostatTau
        self.mirostatEta = mirostatEta
    }

    enum CodingKeys: String, CodingKey {
        case numPredict = "num_predict"
        case temperature
        case topK = "top_k"
        case topP = "top_p"
        case minP = "min_p"
        case seed, stop
        case repeatPenalty = "repeat_penalty"
        case presencePenalty = "presence_penalty"
        case frequencyPenalty = "frequency_penalty"
        case numCtx = "num_ctx"
        case numBatch = "num_batch"
        case numKeep = "num_keep"
        case typicalP = "typical_p"
        case tfsZ = "tfs_z"
        case penalizeNewline = "penalize_newline"
        case mirostat
        case mirostatTau = "mirostat_tau"
        case mirostatEta = "mirostat_eta"
    }
}

// MARK: - Response Format

/// Sendable container for JSON Schema data using JSONValue for type safety.
public struct JSONSchemaContainer: Codable, Sendable, Equatable {
    /// The schema value
    private let value: JSONValue

    /// Create a container from a JSONValue
    public init(_ value: JSONValue) {
        self.value = value
    }

    /// Create a container from a dictionary (convenience)
    public init(_ dictionary: [String: Any]) {
        // Convert [String: Any] to JSONValue via JSONSerialization + Codable round-trip
        if let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys]),
           let jsonValue = try? JSONDecoder().decode(JSONValue.self, from: data) {
            self.value = jsonValue
        } else {
            self.value = .object([:])
        }
    }

    /// Access the schema as a dictionary (for backward compatibility)
    public var schema: [String: Any] {
        guard let data = try? JSONEncoder().encode(value),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try container.decode(JSONValue.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

/// Response format specification
public enum ResponseFormat: Codable, Sendable, Equatable {
    case text
    case json
    case jsonSchema(JSONSchemaContainer)

    /// Convenience initializer for creating jsonSchema from dictionary
    public static func jsonSchema(_ dictionary: [String: Any]) -> ResponseFormat {
        .jsonSchema(JSONSchemaContainer(dictionary))
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Try to decode as string first
        if let value = try? container.decode(String.self) {
            switch value {
            case "json":
                self = .json
            case "text":
                self = .text
            default:
                self = .text
            }
        } else if let schemaContainer = try? container.decode(JSONSchemaContainer.self) {
            // Decode as JSON Schema object
            self = .jsonSchema(schemaContainer)
        } else {
            self = .text
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text:
            try container.encode("text")
        case .json:
            try container.encode("json")
        case .jsonSchema(let schemaContainer):
            // Encode JSON Schema object directly
            try container.encode(schemaContainer)
        }
    }
}

// MARK: - Error Response

/// Error response from Ollama API
public struct ErrorResponse: Codable, Error, LocalizedError, Sendable {
    public let error: String

    public var errorDescription: String? {
        return error
    }
}

// MARK: - Empty Request

/// Empty request for endpoints that don't require body
public struct EmptyRequest: Codable, Sendable {
    public init() {}
}
#endif
