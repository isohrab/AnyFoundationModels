#if OLLAMA_ENABLED
import Testing
import Foundation
@testable import OllamaFoundationModels

@Suite("JSONExtractor Tests")
struct JSONExtractorTests {

    // MARK: - isValidJSON

    @Test("Valid JSON object returns true")
    func validJSONObject() {
        #expect(JSONExtractor.isValidJSON(#"{"key": "value"}"#))
    }

    @Test("Valid JSON array returns true")
    func validJSONArray() {
        #expect(JSONExtractor.isValidJSON("[1, 2, 3]"))
    }

    @Test("Valid JSON string returns true")
    func validJSONString() {
        #expect(JSONExtractor.isValidJSON(#""hello""#))
    }

    @Test("Invalid JSON returns false")
    func invalidJSON() {
        #expect(!JSONExtractor.isValidJSON("not json"))
    }

    @Test("Empty string returns false")
    func emptyString() {
        #expect(!JSONExtractor.isValidJSON(""))
    }

    @Test("Truncated JSON returns false")
    func truncatedJSON() {
        #expect(!JSONExtractor.isValidJSON(#"{"key":"#))
    }

    // MARK: - extractFromCodeBlock

    @Test("Extracts JSON from ```json block")
    func extractFromJSONCodeBlock() {
        let content = """
        ```json
        {"key": "value"}
        ```
        """
        let result = JSONExtractor.extractFromCodeBlock(content)
        #expect(result == #"{"key": "value"}"#)
    }

    @Test("Extracts JSON from plain ``` block")
    func extractFromPlainCodeBlock() {
        let content = """
        ```
        {"key": "value"}
        ```
        """
        let result = JSONExtractor.extractFromCodeBlock(content)
        #expect(result == #"{"key": "value"}"#)
    }

    @Test("Case-insensitive: extracts from ```JSON block")
    func extractFromUppercaseJSONBlock() {
        let content = "```JSON\n{\"k\": 1}\n```"
        let result = JSONExtractor.extractFromCodeBlock(content)
        #expect(result == #"{"k": 1}"#)
    }

    @Test("Returns nil for empty code block")
    func emptyCodeBlock() {
        let result = JSONExtractor.extractFromCodeBlock("```\n```")
        #expect(result == nil)
    }

    @Test("Returns nil for code block with invalid JSON")
    func codeBlockWithInvalidJSON() {
        let result = JSONExtractor.extractFromCodeBlock("```\nnot json\n```")
        #expect(result == nil)
    }

    @Test("Returns nil when no code block present")
    func noCodeBlock() {
        let result = JSONExtractor.extractFromCodeBlock(#"{"key": "value"}"#)
        #expect(result == nil)
    }

    @Test("Extracts nested JSON from code block")
    func nestedJSONInCodeBlock() {
        let content = "```json\n{\"outer\": {\"inner\": 42}}\n```"
        let result = JSONExtractor.extractFromCodeBlock(content)
        #expect(result == #"{"outer": {"inner": 42}}"#)
    }

    // MARK: - extractRawJSON

    @Test("Extracts bare JSON object from surrounding text")
    func extractBareJSON() {
        let content = #"Here is the result: {"name": "Alice"} hope this helps"#
        let result = JSONExtractor.extractRawJSON(content)
        #expect(result == #"{"name": "Alice"}"#)
    }

    @Test("Returns nil when no JSON object present")
    func noJSONObject() {
        let result = JSONExtractor.extractRawJSON("just plain text")
        #expect(result == nil)
    }

    @Test("Returns nil for invalid JSON braces")
    func invalidJSONBraces() {
        let result = JSONExtractor.extractRawJSON("{not: valid}")
        #expect(result == nil)
    }

    @Test("Greedy pattern spans both objects, returns nil for multiple top-level objects")
    func multipleTopLevelObjectsReturnNil() {
        // jsonObjectPattern uses \{[\s\S]*\} which is greedy.
        // For `{"a": 1} {"b": 2}`, it spans from the first { to the last },
        // yielding the invalid string `{"a": 1} {"b": 2}`, so isValidJSON fails and result is nil.
        let content = #"{"a": 1} {"b": 2}"#
        let result = JSONExtractor.extractRawJSON(content)
        #expect(result == nil)
    }

    // MARK: - extract (priority: code block > raw JSON)

    @Test("Prefers code block over raw JSON when both present")
    func prefersCodeBlock() {
        let content = """
        Extra: {"raw": "json"}
        ```json
        {"code": "block"}
        ```
        """
        let result = JSONExtractor.extract(from: content)
        #expect(result == #"{"code": "block"}"#)
    }

    @Test("Falls back to raw JSON when no code block")
    func fallsBackToRawJSON() {
        let content = #"Result: {"key": "value"}"#
        let result = JSONExtractor.extract(from: content)
        #expect(result == #"{"key": "value"}"#)
    }

    @Test("Returns nil when no JSON found anywhere")
    func returnsNilWhenNoJSON() {
        let result = JSONExtractor.extract(from: "just plain text with no json")
        #expect(result == nil)
    }

    @Test("Returns nil for empty input")
    func emptyInput() {
        let result = JSONExtractor.extract(from: "")
        #expect(result == nil)
    }

    @Test("Extracts complex nested structure from code block")
    func complexNestedStructure() {
        let content = """
        ```json
        {"users": [{"id": 1, "name": "Alice"}, {"id": 2, "name": "Bob"}]}
        ```
        """
        let result = JSONExtractor.extract(from: content)
        #expect(result != nil)
        #expect(result!.contains("users"))
        #expect(result!.contains("Alice"))
    }
}

#endif
