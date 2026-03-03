#if OLLAMA_ENABLED
import Testing
import Foundation
@testable import OllamaFoundationModels

// Note on normalization behavior:
// `normalizeMalformedToolCallWrappers` unconditionally strips all </tool_call>,
// </function_call>, etc. closing tags before XML parsing. As a result, the XML
// tag parser never matches (no closing tag present), and tool call extraction
// falls back to the raw JSON parser for content containing JSON objects.
// Pure GLM-style content (no JSON) is not extracted in the current implementation.

@Suite("TextToolCallParser Tests")
struct TextToolCallParserTests {

    // MARK: - Empty / No Tool Calls

    @Test("Empty input returns empty result")
    func emptyInput() {
        let result = TextToolCallParser.parse("")
        #expect(result.toolCalls.isEmpty)
        #expect(result.remainingContent == "")
    }

    @Test("Plain text returns no tool calls and preserves content")
    func plainText() {
        let content = "Hello, this is a plain response."
        let result = TextToolCallParser.parse(content)
        #expect(result.toolCalls.isEmpty)
        #expect(result.remainingContent == content)
    }

    // MARK: - XML <tool_call> Tags (JSON content extracted via raw JSON fallback)
    //
    // Due to normalization stripping </tool_call>, the XML parser does not fire.
    // The JSON payload inside the tag is extracted by the raw JSON fallback parser.

    @Test("Extracts tool call from JSON inside <tool_call> tags (name+arguments format)")
    func xmlToolCallNameArguments() {
        let content = #"<tool_call>{"name": "get_weather", "arguments": {"city": "Tokyo"}}</tool_call>"#
        let result = TextToolCallParser.parse(content)
        #expect(result.toolCalls.count == 1)
        #expect(result.toolCalls[0].function.name == "get_weather")
    }

    @Test("Extracts tool call from JSON inside <tool_call> tags (function.name format)")
    func xmlToolCallFunctionName() {
        let content = #"<tool_call>{"function": {"name": "search", "arguments": {"query": "swift"}}}</tool_call>"#
        let result = TextToolCallParser.parse(content)
        #expect(result.toolCalls.count == 1)
        #expect(result.toolCalls[0].function.name == "search")
    }

    @Test("Extracts tool call from JSON inside <tool_call> tags (type=function format)")
    func xmlToolCallTypeFunction() {
        let content = #"<tool_call>{"type": "function", "function": {"name": "calc", "arguments": {"x": 1}}}</tool_call>"#
        let result = TextToolCallParser.parse(content)
        #expect(result.toolCalls.count == 1)
        #expect(result.toolCalls[0].function.name == "calc")
    }

    @Test("Extracts tool calls from multiple <tool_call> tags")
    func multipleXMLToolCalls() {
        let content = """
        <tool_call>{"name": "tool_a", "arguments": {}}</tool_call>
        <tool_call>{"name": "tool_b", "arguments": {"x": 1}}</tool_call>
        """
        let result = TextToolCallParser.parse(content)
        #expect(result.toolCalls.count == 2)
        let names = result.toolCalls.map { $0.function.name }
        #expect(names.contains("tool_a"))
        #expect(names.contains("tool_b"))
    }

    @Test("GLM-style content without JSON arguments returns no tool calls")
    func glmStyleNoJSONReturnsEmpty() {
        // GLM-style: ToolName<arg_key>key</arg_key><arg_value>value</arg_value>
        // Normalization strips </tool_call>, so XML parser cannot match.
        // No JSON object exists for the raw JSON parser either.
        // Current behavior: 0 tool calls.
        let content = """
        <tool_call>SearchTool<arg_key>query</arg_key><arg_value>swift concurrency</arg_value></tool_call>
        """
        let result = TextToolCallParser.parse(content)
        #expect(result.toolCalls.isEmpty)
    }

    // MARK: - <function_call> Tags (JSON content extracted via raw JSON fallback)

    @Test("Extracts tool call from JSON inside <function_call> tags")
    func functionCallTags() {
        let content = #"<function_call>{"name": "list_files", "arguments": {"dir": "/tmp"}}</function_call>"#
        let result = TextToolCallParser.parse(content)
        #expect(result.toolCalls.count == 1)
        #expect(result.toolCalls[0].function.name == "list_files")
    }

    // MARK: - Code Block Tool Calls (XML parsers not involved)

    @Test("Parses JSON tool call from ```json code block")
    func codeBlockJSONToolCall() {
        let content = """
        ```json
        {"name": "run_query", "arguments": {"sql": "SELECT 1"}}
        ```
        """
        let result = TextToolCallParser.parse(content)
        #expect(result.toolCalls.count == 1)
        #expect(result.toolCalls[0].function.name == "run_query")
    }

    @Test("Parses JSON tool call from plain ``` code block")
    func codeBlockPlainToolCall() {
        let content = """
        ```
        {"name": "do_thing", "arguments": {}}
        ```
        """
        let result = TextToolCallParser.parse(content)
        #expect(result.toolCalls.count == 1)
        #expect(result.toolCalls[0].function.name == "do_thing")
    }

    @Test("Parses JSON array of tool calls from code block")
    func codeBlockToolCallArray() {
        let content = """
        ```json
        [{"name": "tool_x", "arguments": {}}, {"name": "tool_y", "arguments": {}}]
        ```
        """
        let result = TextToolCallParser.parse(content)
        #expect(result.toolCalls.count == 2)
    }

    @Test("Code block remaining content is empty after extraction")
    func codeBlockRemainingEmpty() {
        let content = """
        ```json
        {"name": "ping", "arguments": {}}
        ```
        """
        let result = TextToolCallParser.parse(content)
        #expect(result.toolCalls.count == 1)
        #expect(result.remainingContent.isEmpty)
    }

    // MARK: - Raw JSON Tool Calls

    @Test("Parses bare name+arguments JSON object")
    func rawJSONNameArguments() {
        let content = #"{"name": "ping", "arguments": {"host": "localhost"}}"#
        let result = TextToolCallParser.parse(content)
        #expect(result.toolCalls.count == 1)
        #expect(result.toolCalls[0].function.name == "ping")
    }

    @Test("Parses bare function.name JSON object")
    func rawJSONFunctionName() {
        let content = #"{"function": {"name": "echo", "arguments": {"msg": "hi"}}}"#
        let result = TextToolCallParser.parse(content)
        #expect(result.toolCalls.count == 1)
        #expect(result.toolCalls[0].function.name == "echo")
    }

    @Test("Parses bare type=function JSON object")
    func rawJSONTypeFunction() {
        let content = #"{"type": "function", "function": {"name": "noop", "arguments": {}}}"#
        let result = TextToolCallParser.parse(content)
        #expect(result.toolCalls.count == 1)
        #expect(result.toolCalls[0].function.name == "noop")
    }

    @Test("Parses JSON array of tool calls as raw input")
    func rawJSONArray() {
        let content = #"[{"name": "a", "arguments": {}}, {"name": "b", "arguments": {}}]"#
        let result = TextToolCallParser.parse(content)
        #expect(result.toolCalls.count == 2)
    }

    @Test("Returns no tool calls for plain JSON that is not a tool call")
    func rawJSONNotToolCall() {
        let content = #"{"key": "value", "count": 42}"#
        let result = TextToolCallParser.parse(content)
        #expect(result.toolCalls.isEmpty)
    }

    @Test("Raw JSON remaining content is empty when whole input is a single tool call")
    func rawJSONRemainingEmpty() {
        let content = #"{"name": "reset", "arguments": {}}"#
        let result = TextToolCallParser.parse(content)
        #expect(result.toolCalls.count == 1)
        #expect(result.remainingContent.isEmpty)
    }

    // MARK: - Arguments

    @Test("Tool call with empty arguments object is accepted")
    func emptyArguments() {
        let content = #"{"name": "reset", "arguments": {}}"#
        let result = TextToolCallParser.parse(content)
        #expect(result.toolCalls.count == 1)
        if case .object(let dict) = result.toolCalls[0].function.arguments {
            #expect(dict.isEmpty)
        } else {
            Issue.record("Expected empty .object arguments")
        }
    }

    @Test("Tool call with missing arguments field uses empty object")
    func missingArguments() {
        let content = #"{"name": "trigger"}"#
        let result = TextToolCallParser.parse(content)
        #expect(result.toolCalls.count == 1)
        if case .object(let dict) = result.toolCalls[0].function.arguments {
            #expect(dict.isEmpty)
        } else {
            Issue.record("Expected .object arguments")
        }
    }

    @Test("Nested arguments are preserved")
    func nestedArguments() {
        let content = #"{"name": "create", "arguments": {"user": {"name": "Alice", "age": 30}}}"#
        let result = TextToolCallParser.parse(content)
        #expect(result.toolCalls.count == 1)
        if case .object(let outer) = result.toolCalls[0].function.arguments,
           case .object(let user) = outer["user"] {
            #expect(user["name"] == .string("Alice"))
            #expect(user["age"] == .int(30))
        } else {
            Issue.record("Expected nested .object arguments")
        }
    }

    // MARK: - containsToolCallPatterns

    @Test("Detects <tool_call> tag")
    func detectsToolCallTag() {
        #expect(TextToolCallParser.containsToolCallPatterns("<tool_call>...</tool_call>"))
    }

    @Test("Detects <function_call> tag")
    func detectsFunctionCallTag() {
        #expect(TextToolCallParser.containsToolCallPatterns("<function_call>...</function_call>"))
    }

    @Test("Detects code block")
    func detectsCodeBlock() {
        #expect(TextToolCallParser.containsToolCallPatterns("```json\n{}\n```"))
    }

    @Test("Detects JSON with name and arguments keys")
    func detectsNameArguments() {
        #expect(TextToolCallParser.containsToolCallPatterns(#"{"name": "foo", "arguments": {}}"#))
    }

    @Test("Detects JSON with function and name keys")
    func detectsFunctionName() {
        #expect(TextToolCallParser.containsToolCallPatterns(#"{"function": {"name": "foo"}}"#))
    }

    @Test("Detects JSON array with name key")
    func detectsJSONArray() {
        #expect(TextToolCallParser.containsToolCallPatterns(#"[{"name": "foo"}]"#))
    }

    @Test("Does not detect plain text")
    func doesNotDetectPlainText() {
        #expect(!TextToolCallParser.containsToolCallPatterns("Hello world, no tools here."))
    }

    @Test("Does not detect unrelated JSON")
    func doesNotDetectUnrelatedJSON() {
        #expect(!TextToolCallParser.containsToolCallPatterns(#"{"key": "value"}"#))
    }

    // MARK: - Priority: code block > raw JSON

    @Test("Code block is preferred over raw JSON in same content")
    func codeBlockTakesPriorityOverRaw() {
        let content = """
        Extra: {"name": "raw_tool", "arguments": {}}
        ```json
        {"name": "code_tool", "arguments": {}}
        ```
        """
        let result = TextToolCallParser.parse(content)
        // parseCodeBlockToolCalls fires before parseRawJSONToolCalls
        #expect(result.toolCalls.count == 1)
        #expect(result.toolCalls[0].function.name == "code_tool")
    }
}

#endif
