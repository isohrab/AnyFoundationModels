#if CLAUDE_ENABLED
import Foundation
import OpenFoundationModelsExtra

/// Cache control for prompt caching
struct CacheControlEphemeral: Codable, Sendable {
    let type: String
    let ttl: String?

    /// Create ephemeral cache control with default TTL (5 minutes)
    static var `default`: CacheControlEphemeral {
        CacheControlEphemeral(type: "ephemeral", ttl: nil)
    }

    /// Create ephemeral cache control with 5 minute TTL
    static var fiveMinutes: CacheControlEphemeral {
        CacheControlEphemeral(type: "ephemeral", ttl: "5m")
    }

    /// Create ephemeral cache control with 1 hour TTL
    static var oneHour: CacheControlEphemeral {
        CacheControlEphemeral(type: "ephemeral", ttl: "1h")
    }
}

/// Tool definition for Claude API
struct Tool: Codable, Sendable {
    let name: String
    let description: String?
    let inputSchema: JSONValue
    let cacheControl: CacheControlEphemeral?

    init(name: String, description: String? = nil, inputSchema: JSONValue, cacheControl: CacheControlEphemeral? = nil) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.cacheControl = cacheControl
    }

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
        case cacheControl = "cache_control"
    }
}

/// Tool choice specification
enum ToolChoice: Codable, Sendable {
    /// Model automatically decides whether to use tools
    case auto(disableParallelToolUse: Bool = false)
    /// Model will use any available tools
    case any(disableParallelToolUse: Bool = false)
    /// Model will not be allowed to use tools
    case none
    /// Model will use the specified tool
    case tool(name: String, disableParallelToolUse: Bool = false)

    enum CodingKeys: String, CodingKey {
        case type, name
        case disableParallelToolUse = "disable_parallel_tool_use"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let disableParallel = try container.decodeIfPresent(Bool.self, forKey: .disableParallelToolUse) ?? false

        switch type {
        case "auto":
            self = .auto(disableParallelToolUse: disableParallel)
        case "any":
            self = .any(disableParallelToolUse: disableParallel)
        case "none":
            self = .none
        case "tool":
            let name = try container.decode(String.self, forKey: .name)
            self = .tool(name: name, disableParallelToolUse: disableParallel)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown tool choice type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .auto(let disableParallel):
            try container.encode("auto", forKey: .type)
            if disableParallel {
                try container.encode(disableParallel, forKey: .disableParallelToolUse)
            }
        case .any(let disableParallel):
            try container.encode("any", forKey: .type)
            if disableParallel {
                try container.encode(disableParallel, forKey: .disableParallelToolUse)
            }
        case .none:
            try container.encode("none", forKey: .type)
        case .tool(let name, let disableParallel):
            try container.encode("tool", forKey: .type)
            try container.encode(name, forKey: .name)
            if disableParallel {
                try container.encode(disableParallel, forKey: .disableParallelToolUse)
            }
        }
    }
}

#endif
