#if CLAUDE_ENABLED
import Foundation
import OpenFoundationModels

/// Provides schema-aware JSON parsing for GeneratedContent construction.
internal struct SchemaConverter {

    // MARK: - Schema-Aware JSON Parsing

    /// Parse JSON using schema information to construct correct GeneratedContent.
    /// Handles Claude's behavior of returning {} for empty arrays.
    static func parseJSONWithSchema(_ json: String, schema: GenerationSchema) -> GeneratedContent? {
        guard let jsonData = json.data(using: .utf8) else { return nil }

        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: jsonData)
        } catch {
            return nil
        }

        let schemaDict: [String: Any]
        do {
            let schemaData = try JSONEncoder().encode(schema)
            guard let dict = try JSONSerialization.jsonObject(with: schemaData) as? [String: Any] else {
                return nil
            }
            schemaDict = dict
        } catch {
            return nil
        }

        return convertToGeneratedContent(jsonObject, schemaDict: schemaDict)
    }

    /// Convert a JSON value to GeneratedContent using JSON Schema dictionary
    static func convertToGeneratedContent(_ value: Any, schemaDict: [String: Any]) -> GeneratedContent {
        if isArraySchema(schemaDict) {
            // Claude returns {} for empty arrays - convert to []
            if let dict = value as? [String: Any], dict.isEmpty {
                return GeneratedContent(kind: .array([]))
            }
            if let array = value as? [Any] {
                let itemsSchema = schemaDict["items"] as? [String: Any] ?? [:]
                let elements = array.map { convertToGeneratedContent($0, schemaDict: itemsSchema) }
                return GeneratedContent(kind: .array(elements))
            }
            if value is NSNull {
                return GeneratedContent(kind: .null)
            }
            return GeneratedContent(kind: .array([]))
        }

        if isObjectSchema(schemaDict) {
            guard let dict = value as? [String: Any] else {
                if value is NSNull {
                    return GeneratedContent(kind: .null)
                }
                return GeneratedContent(kind: .structure(properties: [:], orderedKeys: []))
            }

            let propertiesSchema = schemaDict["properties"] as? [String: [String: Any]] ?? [:]
            let requiredFields = schemaDict["required"] as? [String] ?? []

            var converted: [String: GeneratedContent] = [:]
            var orderedKeys: [String] = []

            for (propName, propSchema) in propertiesSchema.sorted(by: { $0.key < $1.key }) {
                orderedKeys.append(propName)
                if let propValue = dict[propName] {
                    converted[propName] = convertToGeneratedContent(propValue, schemaDict: propSchema)
                } else if !requiredFields.contains(propName) {
                    converted[propName] = GeneratedContent(kind: .null)
                }
            }
            return GeneratedContent(kind: .structure(properties: converted, orderedKeys: orderedKeys))
        }

        // Handle anyOf schema (union types including optional arrays)
        if let anyOfSchemas = schemaDict["anyOf"] as? [[String: Any]] {
            for subSchema in anyOfSchemas {
                if isArraySchema(subSchema) {
                    if let dict = value as? [String: Any], dict.isEmpty {
                        return GeneratedContent(kind: .array([]))
                    }
                    if let array = value as? [Any] {
                        let itemsSchema = subSchema["items"] as? [String: Any] ?? [:]
                        let elements = array.map { convertToGeneratedContent($0, schemaDict: itemsSchema) }
                        return GeneratedContent(kind: .array(elements))
                    }
                }
            }
            for subSchema in anyOfSchemas {
                let result = convertToGeneratedContent(value, schemaDict: subSchema)
                if case .null = result.kind {
                    continue
                }
                return result
            }
            return convertPrimitiveToGeneratedContent(value)
        }

        return convertPrimitiveToGeneratedContent(value)
    }

    // MARK: - Schema Type Checks

    /// Check if schema expects an array type
    static func isArraySchema(_ schema: [String: Any]) -> Bool {
        if let type = schema["type"] as? String {
            return type == "array"
        }
        if let types = schema["type"] as? [String] {
            return types.contains("array")
        }
        return false
    }

    /// Check if schema expects an object type
    static func isObjectSchema(_ schema: [String: Any]) -> Bool {
        if let type = schema["type"] as? String {
            return type == "object"
        }
        if let types = schema["type"] as? [String] {
            return types.contains("object")
        }
        return false
    }

    // MARK: - Primitive Conversion

    /// Convert a primitive JSON value to GeneratedContent
    static func convertPrimitiveToGeneratedContent(_ value: Any) -> GeneratedContent {
        switch value {
        case let str as String:
            return GeneratedContent(kind: .string(str))
        case let num as NSNumber:
            // JSONSerialization returns all values as NSNumber (including booleans).
            // CFBooleanGetTypeID distinguishes true booleans from numeric NSNumbers.
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                return GeneratedContent(kind: .bool(num.boolValue))
            }
            return GeneratedContent(kind: .number(num.doubleValue))
        case is NSNull:
            return GeneratedContent(kind: .null)
        case let dict as [String: Any]:
            var converted: [String: GeneratedContent] = [:]
            let orderedKeys = Array(dict.keys).sorted()
            for key in orderedKeys {
                if let propValue = dict[key] {
                    converted[key] = convertPrimitiveToGeneratedContent(propValue)
                }
            }
            return GeneratedContent(kind: .structure(properties: converted, orderedKeys: orderedKeys))
        case let array as [Any]:
            let elements = array.map { convertPrimitiveToGeneratedContent($0) }
            return GeneratedContent(kind: .array(elements))
        default:
            return GeneratedContent(String(describing: value))
        }
    }
}

#endif
