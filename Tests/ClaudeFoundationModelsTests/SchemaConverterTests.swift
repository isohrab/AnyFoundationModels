#if CLAUDE_ENABLED
import Testing
import Foundation
import JSONSchema
@testable import ClaudeFoundationModels

@Suite("SchemaConverter Tests")
struct SchemaConverterTests {

    // MARK: - isArraySchema

    @Test("type=array schema returns true")
    func arraySchemaStringType() {
        let schema = JSONValue.object(["type": .string("array")])
        #expect(SchemaConverter.isArraySchema(schema))
    }

    @Test("type=object schema returns false for isArraySchema")
    func objectSchemaNotArray() {
        let schema = JSONValue.object(["type": .string("object")])
        #expect(!SchemaConverter.isArraySchema(schema))
    }

    @Test("Non-object JSONValue returns false for isArraySchema")
    func nonObjectNotArray() {
        #expect(!SchemaConverter.isArraySchema(.string("array")))
        #expect(!SchemaConverter.isArraySchema(.null))
    }

    @Test("Array of types containing 'array' returns true for isArraySchema")
    func arrayTypeContainingArray() {
        let schema = JSONValue.object(["type": .array([.string("array"), .string("null")])])
        #expect(SchemaConverter.isArraySchema(schema))
    }

    @Test("Array of types not containing 'array' returns false")
    func arrayTypeNotContainingArray() {
        let schema = JSONValue.object(["type": .array([.string("string"), .string("null")])])
        #expect(!SchemaConverter.isArraySchema(schema))
    }

    // MARK: - isObjectSchema

    @Test("type=object schema returns true")
    func objectSchemaStringType() {
        let schema = JSONValue.object(["type": .string("object")])
        #expect(SchemaConverter.isObjectSchema(schema))
    }

    @Test("type=array schema returns false for isObjectSchema")
    func arraySchemaNotObject() {
        let schema = JSONValue.object(["type": .string("array")])
        #expect(!SchemaConverter.isObjectSchema(schema))
    }

    @Test("Non-object JSONValue returns false for isObjectSchema")
    func nonObjectNotObject() {
        #expect(!SchemaConverter.isObjectSchema(.string("object")))
        #expect(!SchemaConverter.isObjectSchema(.null))
    }

    @Test("Array of types containing 'object' returns true for isObjectSchema")
    func arrayTypeContainingObject() {
        let schema = JSONValue.object(["type": .array([.string("object"), .string("null")])])
        #expect(SchemaConverter.isObjectSchema(schema))
    }

    // MARK: - convertPrimitiveToGeneratedContent

    @Test("String JSONValue converts to string GeneratedContent")
    func primitiveString() {
        let result = SchemaConverter.convertPrimitiveToGeneratedContent(.string("hello"))
        if case .string(let s) = result.kind {
            #expect(s == "hello")
        } else {
            Issue.record("Expected .string, got \(result.kind)")
        }
    }

    @Test("Int JSONValue converts to number GeneratedContent")
    func primitiveInt() {
        let result = SchemaConverter.convertPrimitiveToGeneratedContent(.int(42))
        if case .number(let d) = result.kind {
            #expect(d == 42.0)
        } else {
            Issue.record("Expected .number, got \(result.kind)")
        }
    }

    @Test("Double JSONValue converts to number GeneratedContent")
    func primitiveDouble() {
        let result = SchemaConverter.convertPrimitiveToGeneratedContent(.double(3.14))
        if case .number(let d) = result.kind {
            #expect(abs(d - 3.14) < 0.001)
        } else {
            Issue.record("Expected .number, got \(result.kind)")
        }
    }

    @Test("Bool true JSONValue converts to bool GeneratedContent")
    func primitiveBoolTrue() {
        let result = SchemaConverter.convertPrimitiveToGeneratedContent(.bool(true))
        if case .bool(let b) = result.kind {
            #expect(b == true)
        } else {
            Issue.record("Expected .bool, got \(result.kind)")
        }
    }

    @Test("Bool false JSONValue converts to bool GeneratedContent")
    func primitiveBoolFalse() {
        let result = SchemaConverter.convertPrimitiveToGeneratedContent(.bool(false))
        if case .bool(let b) = result.kind {
            #expect(b == false)
        } else {
            Issue.record("Expected .bool, got \(result.kind)")
        }
    }

    @Test("Null JSONValue converts to null GeneratedContent")
    func primitiveNull() {
        let result = SchemaConverter.convertPrimitiveToGeneratedContent(.null)
        if case .null = result.kind {
            // pass
        } else {
            Issue.record("Expected .null, got \(result.kind)")
        }
    }

    @Test("Object JSONValue converts to structure GeneratedContent")
    func primitiveObject() {
        let value = JSONValue.object(["name": .string("Alice"), "age": .int(30)])
        let result = SchemaConverter.convertPrimitiveToGeneratedContent(value)
        if case .structure(let props, let keys) = result.kind {
            #expect(props["name"] != nil)
            #expect(props["age"] != nil)
            // orderedKeys should be sorted
            #expect(keys == keys.sorted())
        } else {
            Issue.record("Expected .structure, got \(result.kind)")
        }
    }

    @Test("Array JSONValue converts to array GeneratedContent")
    func primitiveArray() {
        let value = JSONValue.array([.string("a"), .string("b")])
        let result = SchemaConverter.convertPrimitiveToGeneratedContent(value)
        if case .array(let elements) = result.kind {
            #expect(elements.count == 2)
        } else {
            Issue.record("Expected .array, got \(result.kind)")
        }
    }

    // MARK: - convertToGeneratedContent — Array Schema

    @Test("Array schema converts .array JSONValue correctly")
    func arraySchemaWithArray() {
        let schema = JSONValue.object([
            "type": .string("array"),
            "items": .object(["type": .string("string")])
        ])
        let value = JSONValue.array([.string("x"), .string("y")])
        let result = SchemaConverter.convertToGeneratedContent(value, schemaDict: schema)
        if case .array(let elements) = result.kind {
            #expect(elements.count == 2)
        } else {
            Issue.record("Expected .array, got \(result.kind)")
        }
    }

    @Test("Array schema with empty object {} value returns empty array (Claude quirk)")
    func arraySchemaEmptyObjectReturnsEmptyArray() {
        let schema = JSONValue.object(["type": .string("array")])
        // Claude returns {} when it means []
        let value = JSONValue.object([:])
        let result = SchemaConverter.convertToGeneratedContent(value, schemaDict: schema)
        if case .array(let elements) = result.kind {
            #expect(elements.isEmpty)
        } else {
            Issue.record("Expected empty .array, got \(result.kind)")
        }
    }

    @Test("Array schema with null value returns null")
    func arraySchemaWithNull() {
        let schema = JSONValue.object(["type": .string("array")])
        let result = SchemaConverter.convertToGeneratedContent(.null, schemaDict: schema)
        if case .null = result.kind {
            // pass
        } else {
            Issue.record("Expected .null, got \(result.kind)")
        }
    }

    @Test("Array schema with no array value returns empty array")
    func arraySchemaWithNonArray() {
        let schema = JSONValue.object(["type": .string("array")])
        let result = SchemaConverter.convertToGeneratedContent(.string("oops"), schemaDict: schema)
        if case .array(let elements) = result.kind {
            #expect(elements.isEmpty)
        } else {
            Issue.record("Expected empty .array, got \(result.kind)")
        }
    }

    // MARK: - convertToGeneratedContent — Object Schema

    @Test("Object schema converts .object JSONValue to structure")
    func objectSchemaWithObject() {
        let schema = JSONValue.object([
            "type": .string("object"),
            "properties": .object([
                "name": .object(["type": .string("string")])
            ])
        ])
        let value = JSONValue.object(["name": .string("Bob")])
        let result = SchemaConverter.convertToGeneratedContent(value, schemaDict: schema)
        if case .structure(let props, _) = result.kind {
            if case .string(let s) = props["name"]?.kind {
                #expect(s == "Bob")
            } else {
                Issue.record("Expected .string for 'name'")
            }
        } else {
            Issue.record("Expected .structure, got \(result.kind)")
        }
    }

    @Test("Object schema with null value returns null")
    func objectSchemaWithNull() {
        let schema = JSONValue.object(["type": .string("object")])
        let result = SchemaConverter.convertToGeneratedContent(.null, schemaDict: schema)
        if case .null = result.kind {
            // pass
        } else {
            Issue.record("Expected .null, got \(result.kind)")
        }
    }

    @Test("Object schema with non-object value returns empty structure")
    func objectSchemaWithNonObject() {
        let schema = JSONValue.object(["type": .string("object")])
        let result = SchemaConverter.convertToGeneratedContent(.string("oops"), schemaDict: schema)
        if case .structure(let props, _) = result.kind {
            #expect(props.isEmpty)
        } else {
            Issue.record("Expected empty .structure, got \(result.kind)")
        }
    }

    @Test("Object schema missing optional field stores null")
    func objectSchemaMissingOptionalField() {
        let schema = JSONValue.object([
            "type": .string("object"),
            "properties": .object([
                "name": .object(["type": .string("string")]),
                "email": .object(["type": .string("string")])
            ]),
            "required": .array([.string("name")])
        ])
        // Only "name" is provided; "email" is optional and missing
        let value = JSONValue.object(["name": .string("Alice")])
        let result = SchemaConverter.convertToGeneratedContent(value, schemaDict: schema)
        if case .structure(let props, _) = result.kind {
            // "email" optional → stored as null
            if let emailContent = props["email"] {
                if case .null = emailContent.kind {
                    // pass
                } else {
                    Issue.record("Expected .null for missing optional 'email', got \(emailContent.kind)")
                }
            } else {
                Issue.record("Expected 'email' key to exist in structure")
            }
        } else {
            Issue.record("Expected .structure, got \(result.kind)")
        }
    }

    // MARK: - convertToGeneratedContent — No Schema Type

    @Test("Schema without type falls through to primitive conversion")
    func schemaWithoutType() {
        let schema = JSONValue.object(["description": .string("some field")])
        let result = SchemaConverter.convertToGeneratedContent(.string("value"), schemaDict: schema)
        if case .string(let s) = result.kind {
            #expect(s == "value")
        } else {
            Issue.record("Expected .string, got \(result.kind)")
        }
    }

    @Test("Non-object schema falls through to primitive conversion")
    func nonObjectSchema() {
        let result = SchemaConverter.convertToGeneratedContent(.int(7), schemaDict: .null)
        if case .number(let d) = result.kind {
            #expect(d == 7.0)
        } else {
            Issue.record("Expected .number, got \(result.kind)")
        }
    }

    // MARK: - convertToGeneratedContent — anyOf Schema

    @Test("anyOf schema with array subschema handles array value")
    func anyOfArraySubschema() {
        let schema = JSONValue.object([
            "anyOf": .array([
                .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                .object(["type": .string("null")])
            ])
        ])
        let value = JSONValue.array([.string("a"), .string("b")])
        let result = SchemaConverter.convertToGeneratedContent(value, schemaDict: schema)
        if case .array(let elements) = result.kind {
            #expect(elements.count == 2)
        } else {
            Issue.record("Expected .array, got \(result.kind)")
        }
    }

    @Test("anyOf schema with array subschema treats {} as empty array")
    func anyOfArrayEmptyObject() {
        let schema = JSONValue.object([
            "anyOf": .array([
                .object(["type": .string("array")]),
                .object(["type": .string("null")])
            ])
        ])
        let value = JSONValue.object([:])
        let result = SchemaConverter.convertToGeneratedContent(value, schemaDict: schema)
        if case .array(let elements) = result.kind {
            #expect(elements.isEmpty)
        } else {
            Issue.record("Expected empty .array for anyOf array+null schema with {}, got \(result.kind)")
        }
    }
}

#endif
