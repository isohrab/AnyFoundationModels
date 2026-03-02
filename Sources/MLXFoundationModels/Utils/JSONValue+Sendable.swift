#if MLX_ENABLED
import OpenFoundationModelsExtra

/// Bridge JSONValue (type-safe, Sendable) to [String: any Sendable] for swift-transformers ToolSpec.
///
/// swift-transformers' `UserInput(chat:, tools:)` requires `[[String: any Sendable]]`.
/// JSONValue provides a well-defined, exhaustive conversion without Any-type ambiguity.
extension JSONValue {
    /// Convert to a Sendable-compatible Foundation value for ToolSpec dictionaries
    var sendableValue: any Sendable {
        switch self {
        case .null: return Optional<String>.none as any Sendable
        case .bool(let b): return b
        case .int(let i): return i
        case .double(let d): return d
        case .string(let s): return s
        case .array(let a): return a.map(\.sendableValue) as [any Sendable]
        case .object(let o): return o.mapValues(\.sendableValue) as [String: any Sendable]
        }
    }
}
#endif
