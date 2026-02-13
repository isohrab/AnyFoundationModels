#if RESPONSE_ENABLED
import Testing
import Foundation
@testable import ResponseFoundationModels

@Suite("AnyCodable Tests")
struct AnyCodableTests {

    // MARK: - Helpers

    private func roundTrip(_ value: Any) throws -> Any {
        let codable = AnyCodable(value)
        let data = try JSONEncoder().encode(codable)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        return decoded.value
    }

    // MARK: - Round Trip

    @Test("Bool round trip preserves value")
    func boolRoundTrip() throws {
        let result = try roundTrip(true)
        let boolValue = try #require(result as? Bool)
        #expect(boolValue == true)
    }

    @Test("Int round trip preserves value")
    func intRoundTrip() throws {
        let result = try roundTrip(42)
        let intValue = try #require(result as? Int)
        #expect(intValue == 42)
    }

    @Test("Double round trip preserves value")
    func doubleRoundTrip() throws {
        let result = try roundTrip(3.14)
        let doubleValue = try #require(result as? Double)
        #expect(abs(doubleValue - 3.14) < 0.001)
    }

    @Test("String round trip preserves value")
    func stringRoundTrip() throws {
        let result = try roundTrip("hello")
        let stringValue = try #require(result as? String)
        #expect(stringValue == "hello")
    }

    @Test("Array round trip preserves values")
    func arrayRoundTrip() throws {
        let result = try roundTrip([1, 2, 3])
        let array = try #require(result as? [Any])
        #expect(array.count == 3)
    }

    @Test("Dictionary round trip preserves values")
    func dictRoundTrip() throws {
        let result = try roundTrip(["key": "value"] as [String: Any])
        let dict = try #require(result as? [String: Any])
        #expect(dict["key"] as? String == "value")
    }

    @Test("Nested structure round trip")
    func nestedRoundTrip() throws {
        let input: [String: Any] = [
            "name": "test",
            "tags": ["a", "b"],
            "meta": ["count": 5] as [String: Any],
        ]
        let result = try roundTrip(input)
        let dict = try #require(result as? [String: Any])
        #expect(dict["name"] as? String == "test")
        let tags = try #require(dict["tags"] as? [Any])
        #expect(tags.count == 2)
        let meta = try #require(dict["meta"] as? [String: Any])
        #expect(meta["count"] as? Int == 5)
    }

    @Test("Null encoding produces JSON null")
    func nullEncoding() throws {
        let codable = AnyCodable(NSNull())
        let data = try JSONEncoder().encode(codable)
        let json = String(data: data, encoding: .utf8)
        #expect(json == "null")
    }
}

#endif
