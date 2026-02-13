#if CLAUDE_ENABLED
import Foundation

/// A type-safe, Sendable JSON primitive that replaces untyped `Any` wrappers.
enum JSONPrimitive: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONPrimitive])
    case object([String: JSONPrimitive])

    // Decoder union pattern: try? is the only way to probe decode types.
    // This is an accepted exception to the no-try? rule.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONPrimitive].self) {
            self = .array(array)
        } else if let dict = try? container.decode([String: JSONPrimitive].self) {
            self = .object(dict)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    /// Convert to untyped `Any` for interop with JSONSerialization-based code.
    var anyValue: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .string(let v): return v
        case .array(let v): return v.map { $0.anyValue }
        case .object(let v): return v.mapValues { $0.anyValue }
        }
    }

    /// Create from an untyped `Any` value (best-effort conversion).
    ///
    /// Pattern matching order matters due to Foundation bridging:
    /// - `Bool` must precede numeric types (Bool bridges to NSNumber)
    /// - Native Swift `Int`/`Double` are checked before `NSNumber`
    ///   to preserve the caller's original type intent
    /// - `NSNumber` fallback handles values from JSONSerialization
    static func from(_ value: Any) -> JSONPrimitive {
        switch value {
        case is NSNull:
            return .null
        case let bool as Bool:
            return .bool(bool)
        case let int as Int:
            return .int(int)
        case let double as Double:
            return .double(double)
        case let string as String:
            return .string(string)
        case let array as [Any]:
            return .array(array.map { from($0) })
        case let dict as [String: Any]:
            return .object(dict.mapValues { from($0) })
        default:
            return .string(String(describing: value))
        }
    }
}

/// Type-erased JSON value for handling dynamic JSON structures.
/// Stores data as `[String: JSONPrimitive]` for full Sendable safety.
struct JSONValue: Codable, Sendable {
    private let storage: [String: JSONPrimitive]

    init(_ dictionary: [String: Any]) {
        self.storage = dictionary.mapValues { JSONPrimitive.from($0) }
    }

    private init(primitives: [String: JSONPrimitive]) {
        self.storage = primitives
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.storage = try container.decode([String: JSONPrimitive].self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storage)
    }

    /// Access as untyped dictionary for backward compatibility.
    var dictionary: [String: Any] {
        storage.mapValues { $0.anyValue }
    }
}

#endif
