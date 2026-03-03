#if CLAUDE_ENABLED
import Foundation
import OpenFoundationModels
import OpenFoundationModelsExtra

/// Provides schema-aware JSON parsing for GeneratedContent construction.
internal struct SchemaConverter {

    // MARK: - Schema-Aware JSON Parsing

    /// Parse JSON using schema information to construct correct GeneratedContent.
    /// Handles Claude's behavior of returning {} for empty arrays.
    static func parseJSONWithSchema(_ json: String, schema: GenerationSchema) -> GeneratedContent? {
        guard let jsonData = json.data(using: .utf8) else { return nil }

        let jsonValue: JSONValue
        do {
            jsonValue = try JSONDecoder().decode(JSONValue.self, from: jsonData)
        } catch {
            return nil
        }

        let schemaValue: JSONValue
        do {
            let schemaData = try JSONEncoder().encode(schema)
            schemaValue = try JSONDecoder().decode(JSONValue.self, from: schemaData)
        } catch {
            return nil
        }

        return convertToGeneratedContent(jsonValue, schemaDict: schemaValue)
    }

    /// Convert a JSONValue to GeneratedContent using a JSONValue schema representation.
    /// Handles Claude's behavior of returning {} for empty arrays.
    static func convertToGeneratedContent(_ value: JSONValue, schemaDict: JSONValue) -> GeneratedContent {
        guard case .object(let schemaObjDict) = schemaDict else {
            return convertPrimitiveToGeneratedContent(value)
        }

        if isArraySchema(schemaDict) {
            // Claude returns {} for empty arrays - convert to []
            if case .object(let d) = value, d.isEmpty {
                return GeneratedContent(kind: .array([]))
            }
            if case .array(let array) = value {
                let itemsSchema = schemaObjDict["items"] ?? .object([:])
                let elements = array.map { convertToGeneratedContent($0, schemaDict: itemsSchema) }
                return GeneratedContent(kind: .array(elements))
            }
            if case .null = value {
                return GeneratedContent(kind: .null)
            }
            return GeneratedContent(kind: .array([]))
        }

        if isObjectSchema(schemaDict) {
            guard case .object(let dict) = value else {
                if case .null = value {
                    return GeneratedContent(kind: .null)
                }
                return GeneratedContent(kind: .structure(properties: [:], orderedKeys: []))
            }

            let propertiesSchema: [String: JSONValue]
            if case .object(let props) = schemaObjDict["properties"] {
                propertiesSchema = props
            } else {
                propertiesSchema = [:]
            }

            let requiredFields: [String]
            if case .array(let req) = schemaObjDict["required"] {
                requiredFields = req.compactMap {
                    if case .string(let s) = $0 { return s }
                    return nil
                }
            } else {
                requiredFields = []
            }

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
        if case .array(let anyOfSchemas) = schemaObjDict["anyOf"] {
            for subSchema in anyOfSchemas {
                if isArraySchema(subSchema) {
                    if case .object(let d) = value, d.isEmpty {
                        return GeneratedContent(kind: .array([]))
                    }
                    if case .array(let array) = value {
                        let itemsSchema: JSONValue
                        if case .object(let sd) = subSchema, let items = sd["items"] {
                            itemsSchema = items
                        } else {
                            itemsSchema = .object([:])
                        }
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
    static func isArraySchema(_ schema: JSONValue) -> Bool {
        guard case .object(let dict) = schema else { return false }
        if case .string(let t) = dict["type"], t == "array" { return true }
        if case .array(let types) = dict["type"] {
            return types.contains(.string("array"))
        }
        return false
    }

    /// Check if schema expects an object type
    static func isObjectSchema(_ schema: JSONValue) -> Bool {
        guard case .object(let dict) = schema else { return false }
        if case .string(let t) = dict["type"], t == "object" { return true }
        if case .array(let types) = dict["type"] {
            return types.contains(.string("object"))
        }
        return false
    }

    // MARK: - Primitive Conversion

    /// Convert a primitive JSONValue to GeneratedContent
    static func convertPrimitiveToGeneratedContent(_ value: JSONValue) -> GeneratedContent {
        switch value {
        case .string(let s):
            return GeneratedContent(kind: .string(s))
        case .int(let i):
            return GeneratedContent(kind: .number(Double(i)))
        case .double(let d):
            return GeneratedContent(kind: .number(d))
        case .bool(let b):
            return GeneratedContent(kind: .bool(b))
        case .null:
            return GeneratedContent(kind: .null)
        case .object(let dict):
            var converted: [String: GeneratedContent] = [:]
            let orderedKeys = Array(dict.keys).sorted()
            for key in orderedKeys {
                if let propValue = dict[key] {
                    converted[key] = convertPrimitiveToGeneratedContent(propValue)
                }
            }
            return GeneratedContent(kind: .structure(properties: converted, orderedKeys: orderedKeys))
        case .array(let array):
            let elements = array.map { convertPrimitiveToGeneratedContent($0) }
            return GeneratedContent(kind: .array(elements))
        }
    }
}

#endif
