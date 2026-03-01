#if CLAUDE_ENABLED
import Foundation
import Testing
import JSONSchema
@testable import ClaudeFoundationModels

@Suite("JSONValue - Type-safe JSON encoding via Codable")
struct JSONValueTests {

    // MARK: - Core: Codable round-trip preserves Bool vs Int distinction

    @Test("JSON true decodes as .bool(true), not .int(1)")
    func jsonTrueIsBool() throws {
        let json = #"{"flag": true}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(JSONValue.self, from: json)
        guard case .object(let dict) = decoded else {
            Issue.record("Expected .object, got \(decoded)")
            return
        }
        #expect(dict["flag"] == .bool(true))
    }

    @Test("JSON false decodes as .bool(false), not .int(0)")
    func jsonFalseIsBool() throws {
        let json = #"{"flag": false}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(JSONValue.self, from: json)
        guard case .object(let dict) = decoded else {
            Issue.record("Expected .object, got \(decoded)")
            return
        }
        #expect(dict["flag"] == .bool(false))
    }

    @Test("JSON integer 1 decodes as .int(1), not .bool(true)")
    func jsonIntegerIsInt() throws {
        let json = #"{"minimum": 1}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(JSONValue.self, from: json)
        guard case .object(let dict) = decoded else {
            Issue.record("Expected .object, got \(decoded)")
            return
        }
        #expect(dict["minimum"] == .int(1))
    }

    @Test("JSON integer 0 decodes as .int(0), not .bool(false)")
    func jsonZeroIsInt() throws {
        let json = #"{"value": 0}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(JSONValue.self, from: json)
        guard case .object(let dict) = decoded else {
            Issue.record("Expected .object, got \(decoded)")
            return
        }
        #expect(dict["value"] == .int(0))
    }

    // MARK: - Numeric types

    @Test("Negative integer stays .int")
    func negativeInt() throws {
        let json = #"{"v": -90}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(JSONValue.self, from: json)
        guard case .object(let dict) = decoded else {
            Issue.record("Expected .object, got \(decoded)")
            return
        }
        #expect(dict["v"] == .int(-90))
    }

    @Test("Large integer stays .int")
    func largeInt() throws {
        let json = #"{"v": 100000}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(JSONValue.self, from: json)
        guard case .object(let dict) = decoded else {
            Issue.record("Expected .object, got \(decoded)")
            return
        }
        #expect(dict["v"] == .int(100000))
    }

    @Test("Floating point becomes .double")
    func floatingPoint() throws {
        let json = #"{"v": 3.14}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(JSONValue.self, from: json)
        guard case .object(let dict) = decoded else {
            Issue.record("Expected .object, got \(decoded)")
            return
        }
        #expect(dict["v"] == .double(3.14))
    }

    // MARK: - Other types

    @Test("String stays .string")
    func stringType() throws {
        let json = #"{"v": "hello"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(JSONValue.self, from: json)
        guard case .object(let dict) = decoded else {
            Issue.record("Expected .object, got \(decoded)")
            return
        }
        #expect(dict["v"] == .string("hello"))
    }

    @Test("Null becomes .null")
    func nullType() throws {
        let json = #"{"v": null}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(JSONValue.self, from: json)
        guard case .object(let dict) = decoded else {
            Issue.record("Expected .object, got \(decoded)")
            return
        }
        #expect(dict["v"] == .null)
    }

    // MARK: - Round-trip: encode → decode preserves types

    @Test("Tool schema round-trip: JSONValue encodes minimum:1 as integer in JSON")
    func toolSchemaRoundTrip() throws {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "radius": .object([
                    "type": .string("number"),
                    "minimum": .int(1),
                    "maximum": .int(100000)
                ]),
                "consent": .object([
                    "type": .string("boolean")
                ])
            ]),
            "required": .array([.string("radius"), .string("consent")])
        ])

        let encoded = try JSONEncoder().encode(schema)
        let jsonString = String(data: encoded, encoding: .utf8)!

        // The encoded JSON must contain "minimum":1 (integer), not "minimum":true (boolean)
        #expect(jsonString.contains("\"minimum\":1") || jsonString.contains("\"minimum\" : 1"))
        #expect(!jsonString.contains("\"minimum\":true"))
        #expect(!jsonString.contains("\"minimum\" : true"))
    }
}

#endif
