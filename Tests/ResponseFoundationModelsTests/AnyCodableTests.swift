#if RESPONSE_ENABLED
import Testing
import Foundation
import JSONSchema

@Suite("JSONValue Round-trip Tests")
struct JSONValueRoundTripTests {

    // MARK: - Helpers

    private func roundTrip(_ value: JSONValue) throws -> JSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    // MARK: - Round Trip

    @Test("Bool round trip preserves value")
    func boolRoundTrip() throws {
        let result = try roundTrip(.bool(true))
        #expect(result == .bool(true))
    }

    @Test("Int round trip preserves value")
    func intRoundTrip() throws {
        let result = try roundTrip(.int(42))
        #expect(result == .int(42))
    }

    @Test("Double round trip preserves value")
    func doubleRoundTrip() throws {
        let result = try roundTrip(.double(3.14))
        #expect(result == .double(3.14))
    }

    @Test("String round trip preserves value")
    func stringRoundTrip() throws {
        let result = try roundTrip(.string("hello"))
        #expect(result == .string("hello"))
    }

    @Test("Array round trip preserves values")
    func arrayRoundTrip() throws {
        let result = try roundTrip(.array([.int(1), .int(2), .int(3)]))
        #expect(result == .array([.int(1), .int(2), .int(3)]))
    }

    @Test("Dictionary round trip preserves values")
    func dictRoundTrip() throws {
        let result = try roundTrip(.object(["key": .string("value")]))
        #expect(result == .object(["key": .string("value")]))
    }

    @Test("Nested structure round trip")
    func nestedRoundTrip() throws {
        let input: JSONValue = .object([
            "name": .string("test"),
            "tags": .array([.string("a"), .string("b")]),
            "meta": .object(["count": .int(5)])
        ])
        let result = try roundTrip(input)
        #expect(result == input)
    }

    @Test("Null encoding produces JSON null")
    func nullEncoding() throws {
        let data = try JSONEncoder().encode(JSONValue.null)
        let json = String(data: data, encoding: .utf8)
        #expect(json == "null")
    }
}

#endif
