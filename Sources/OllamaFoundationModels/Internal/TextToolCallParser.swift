#if OLLAMA_ENABLED
import Foundation
import JSONSchema

/// Parses text-based tool calls from model responses.
/// Some models output tool calls as XML-style tags, code blocks, or raw JSON
/// instead of using Ollama's native tool_calls field.
/// This parser detects and extracts tool calls from text content as a fallback mechanism.
///
/// ## Detection priority
/// 1. `<tool_call>...</tool_call>` XML tags (Qwen/GLM style)
/// 2. `<function_call>...</function_call>` tags
/// 3. Code blocks: ``` ```json {"name":...} ``` ```
/// 4. Raw JSON objects: `{"name": "...", "arguments": {...}}`
internal struct TextToolCallParser: Sendable {

    /// Result of parsing tool calls from text
    struct ParseResult: Sendable {
        /// Successfully parsed tool calls
        let toolCalls: [ToolCall]
        /// Remaining text content after removing tool call tags
        let remainingContent: String
    }

    // MARK: - Main Parsing Entry Point

    /// Parse tool calls from text content
    /// - Parameter content: The text content that may contain tool calls
    /// - Returns: ParseResult with extracted tool calls and remaining content
    static func parse(_ content: String) -> ParseResult {
        guard !content.isEmpty else {
            return ParseResult(toolCalls: [], remainingContent: "")
        }

        // Normalize malformed tool-call wrappers first.
        // Example: "<tool_call{...}" (missing '>') should not leak to UI.
        let normalizedContent = normalizeMalformedToolCallWrappers(content)

        // Try XML-style tool_call tags first (most common for Qwen/GLM)
        let xmlResult = parseXMLStyleToolCalls(normalizedContent)
        if !xmlResult.toolCalls.isEmpty {
            return xmlResult
        }

        // Try function_call tags
        let funcResult = parseFunctionCallTags(normalizedContent)
        if !funcResult.toolCalls.isEmpty {
            return funcResult
        }

        // Try code block wrapped JSON
        let codeBlockResult = parseCodeBlockToolCalls(normalizedContent)
        if !codeBlockResult.toolCalls.isEmpty {
            return codeBlockResult
        }

        // Try raw JSON tool calls
        let rawResult = parseRawJSONToolCalls(normalizedContent)
        if !rawResult.toolCalls.isEmpty {
            return rawResult
        }

        // No tool calls found
        return ParseResult(toolCalls: [], remainingContent: normalizedContent)
    }

    // MARK: - XML-Style Parsing (<tool_call>...</tool_call>)

    /// Parse tool calls from XML-style tags
    /// Supports multiple formats:
    /// - JSON: `<tool_call>{"name": "tool_name", "arguments": {...}}</tool_call>`
    /// - GLM-style: `<tool_call>ToolName<arg_key>key</arg_key><arg_value>value</arg_value></tool_call>`
    private static func parseXMLStyleToolCalls(_ content: String) -> ParseResult {
        var toolCalls: [ToolCall] = []
        var remainingContent = content

        // Pattern matches <tool_call>...</tool_call> (non-greedy)
        let pattern = #"<tool_call>\s*([\s\S]*?)\s*</tool_call>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return ParseResult(toolCalls: [], remainingContent: content)
        }

        let nsRange = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, options: [], range: nsRange)

        for match in matches {
            guard let innerRange = Range(match.range(at: 1), in: content) else { continue }
            let innerContent = String(content[innerRange])

            // Try JSON format first
            if let toolCall = parseToolCallJSON(innerContent) {
                toolCalls.append(toolCall)
            }
            // Try GLM-style XML format: ToolName<arg_key>key</arg_key><arg_value>value</arg_value>
            else if let toolCall = parseGLMStyleToolCall(innerContent) {
                toolCalls.append(toolCall)
            }
        }

        // Remove matched tool_call tags from content
        if !toolCalls.isEmpty {
            remainingContent = regex.stringByReplacingMatches(
                in: content,
                options: [],
                range: nsRange,
                withTemplate: ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return ParseResult(toolCalls: toolCalls, remainingContent: remainingContent)
    }

    // MARK: - GLM-Style XML Parsing

    /// Parse GLM-style tool call format
    /// Format: `ToolName<arg_key>key1</arg_key><arg_value>value1</arg_value><arg_key>key2</arg_key><arg_value>value2</arg_value>`
    private static func parseGLMStyleToolCall(_ content: String) -> ToolCall? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if it contains arg_key/arg_value pattern
        guard trimmed.contains("<arg_key>") && trimmed.contains("<arg_value>") else {
            return nil
        }

        // Extract tool name (everything before first <arg_key>)
        guard let firstArgKeyIndex = trimmed.range(of: "<arg_key>")?.lowerBound else {
            return nil
        }

        let toolName = String(trimmed[..<firstArgKeyIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !toolName.isEmpty else {
            return nil
        }

        // Extract all key-value pairs
        var arguments: [String: Any] = [:]

        // Pattern for <arg_key>key</arg_key><arg_value>value</arg_value>
        let argPattern = #"<arg_key>\s*(.*?)\s*</arg_key>\s*<arg_value>\s*([\s\S]*?)\s*</arg_value>"#
        guard let argRegex = try? NSRegularExpression(pattern: argPattern, options: []) else {
            return nil
        }

        let nsRange = NSRange(trimmed.startIndex..., in: trimmed)
        let matches = argRegex.matches(in: trimmed, options: [], range: nsRange)

        for match in matches {
            guard match.numberOfRanges >= 3,
                  let keyRange = Range(match.range(at: 1), in: trimmed),
                  let valueRange = Range(match.range(at: 2), in: trimmed) else {
                continue
            }

            let key = String(trimmed[keyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(trimmed[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            arguments[key] = value
        }

        guard !arguments.isEmpty else {
            return nil
        }

        return createToolCall(name: toolName, arguments: arguments)
    }

    // MARK: - Function Call Tags Parsing (<function_call>...</function_call>)

    /// Parse tool calls from function_call tags
    private static func parseFunctionCallTags(_ content: String) -> ParseResult {
        var toolCalls: [ToolCall] = []
        var remainingContent = content

        let pattern = #"<function_call>\s*([\s\S]*?)\s*</function_call>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return ParseResult(toolCalls: [], remainingContent: content)
        }

        let nsRange = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, options: [], range: nsRange)

        for match in matches {
            guard let innerRange = Range(match.range(at: 1), in: content) else { continue }
            let innerContent = String(content[innerRange])

            if let toolCall = parseToolCallJSON(innerContent) {
                toolCalls.append(toolCall)
            }
        }

        if !toolCalls.isEmpty {
            remainingContent = regex.stringByReplacingMatches(
                in: content,
                options: [],
                range: nsRange,
                withTemplate: ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return ParseResult(toolCalls: toolCalls, remainingContent: remainingContent)
    }

    // MARK: - Code Block Tool Call Parsing

    /// Parse tool calls from markdown code blocks
    /// Handles: ```json {"name":...} ``` and ``` {"name":...} ```
    private static func parseCodeBlockToolCalls(_ content: String) -> ParseResult {
        var toolCalls: [ToolCall] = []
        var remainingContent = content

        let pattern = #"```(?:json)?\s*\n?([\s\S]*?)```"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return ParseResult(toolCalls: [], remainingContent: content)
        }

        let nsRange = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, options: [], range: nsRange)

        for match in matches {
            guard let innerRange = Range(match.range(at: 1), in: content) else { continue }
            let innerContent = String(content[innerRange]).trimmingCharacters(in: .whitespacesAndNewlines)

            // Try as single tool call
            if let toolCall = parseToolCallJSON(innerContent) {
                toolCalls.append(toolCall)
            }
            // Try as array of tool calls
            else if let arrayToolCalls = parseToolCallJSONArray(innerContent) {
                toolCalls.append(contentsOf: arrayToolCalls)
            }
        }

        if !toolCalls.isEmpty {
            remainingContent = regex.stringByReplacingMatches(
                in: content,
                options: [],
                range: nsRange,
                withTemplate: ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return ParseResult(toolCalls: toolCalls, remainingContent: remainingContent)
    }

    // MARK: - Raw JSON Tool Call Parsing

    /// Parse tool calls from raw JSON in content
    /// Handles bare JSON objects and arrays without any wrapping tags
    private static func parseRawJSONToolCalls(_ content: String) -> ParseResult {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try as JSON array first: [{"name":...}, {"name":...}]
        if trimmed.hasPrefix("[") {
            if let toolCalls = parseToolCallJSONArray(trimmed) {
                return ParseResult(toolCalls: toolCalls, remainingContent: "")
            }
        }

        // Extract individual balanced JSON objects
        let jsonObjects = extractBalancedJSONObjects(from: trimmed)
        var toolCalls: [ToolCall] = []
        var matchedRanges: [Range<String.Index>] = []

        for (jsonString, range) in jsonObjects {
            if let toolCall = parseToolCallJSON(jsonString) {
                toolCalls.append(toolCall)
                matchedRanges.append(range)
            }
        }

        guard !toolCalls.isEmpty else {
            return ParseResult(toolCalls: [], remainingContent: content)
        }

        // Remove matched JSON from content (reverse order to preserve indices)
        var remaining = trimmed
        for range in matchedRanges.reversed() {
            remaining.removeSubrange(range)
        }
        remaining = remaining.trimmingCharacters(in: .whitespacesAndNewlines)

        return ParseResult(toolCalls: toolCalls, remainingContent: remaining)
    }

    // MARK: - Balanced JSON Extraction

    /// Extract all balanced JSON objects from text content
    /// Uses brace depth tracking with string escape handling
    private static func extractBalancedJSONObjects(from content: String) -> [(String, Range<String.Index>)] {
        var results: [(String, Range<String.Index>)] = []
        var index = content.startIndex

        while index < content.endIndex {
            if content[index] == "{" {
                if let endIndex = findMatchingBrace(in: content, from: index) {
                    let afterEnd = content.index(after: endIndex)
                    let range = index..<afterEnd
                    let jsonStr = String(content[range])

                    // Validate as JSON before accepting
                    if let data = jsonStr.data(using: .utf8),
                       (try? JSONSerialization.jsonObject(with: data)) != nil {
                        results.append((jsonStr, range))
                        index = afterEnd
                        continue
                    }
                }
            }
            index = content.index(after: index)
        }

        return results
    }

    /// Find the matching closing brace for an opening brace
    /// Handles string escaping correctly
    private static func findMatchingBrace(in content: String, from startIndex: String.Index) -> String.Index? {
        var depth = 0
        var inString = false
        var escape = false
        var index = startIndex

        while index < content.endIndex {
            let char = content[index]

            if escape {
                escape = false
            } else if char == "\\" && inString {
                escape = true
            } else if char == "\"" {
                inString = !inString
            } else if !inString {
                if char == "{" {
                    depth += 1
                } else if char == "}" {
                    depth -= 1
                    if depth == 0 {
                        return index
                    }
                }
            }

            index = content.index(after: index)
        }

        return nil
    }

    // MARK: - JSON Parsing Helpers

    /// Parse a single tool call from JSON content
    /// Supports formats:
    /// - `{"name": "tool_name", "arguments": {...}}`
    /// - `{"function": {"name": "tool_name", "arguments": {...}}}`
    /// - `{"type": "function", "function": {"name": "tool_name", "arguments": {...}}}`
    private static func parseToolCallJSON(_ jsonString: String) -> ToolCall? {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Format 1: {"name": "...", "arguments": {...}}
        if let name = json["name"] as? String {
            let arguments = json["arguments"] as? [String: Any] ?? [:]
            return createToolCall(name: name, arguments: arguments)
        }

        // Format 2: {"function": {"name": "...", "arguments": {...}}}
        if let function = json["function"] as? [String: Any],
           let name = function["name"] as? String {
            let arguments = function["arguments"] as? [String: Any] ?? [:]
            return createToolCall(name: name, arguments: arguments)
        }

        // Format 3: {"type": "function", "function": {...}}
        if json["type"] as? String == "function",
           let function = json["function"] as? [String: Any],
           let name = function["name"] as? String {
            let arguments = function["arguments"] as? [String: Any] ?? [:]
            return createToolCall(name: name, arguments: arguments)
        }

        return nil
    }

    /// Parse an array of tool calls from JSON content
    /// Format: `[{"name": "...", "arguments": {...}}, ...]`
    private static func parseToolCallJSONArray(_ jsonString: String) -> [ToolCall]? {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = trimmed.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        var toolCalls: [ToolCall] = []
        for item in array {
            // Format 1: {"name": "...", "arguments": {...}}
            if let name = item["name"] as? String {
                let arguments = item["arguments"] as? [String: Any] ?? [:]
                toolCalls.append(createToolCall(name: name, arguments: arguments))
            }
            // Format 2: {"function": {"name": "...", "arguments": {...}}}
            else if let function = item["function"] as? [String: Any],
                    let name = function["name"] as? String {
                let arguments = function["arguments"] as? [String: Any] ?? [:]
                toolCalls.append(createToolCall(name: name, arguments: arguments))
            }
        }

        return toolCalls.isEmpty ? nil : toolCalls
    }

    /// Create a ToolCall from name and arguments
    private static func createToolCall(name: String, arguments: [String: Any]) -> ToolCall {
        // Convert [String: Any] to JSONValue via JSONSerialization + Codable round-trip
        let jsonValue: JSONValue
        if let data = try? JSONSerialization.data(withJSONObject: arguments),
           let decoded = try? JSONDecoder().decode(JSONValue.self, from: data) {
            jsonValue = decoded
        } else {
            jsonValue = .object([:])
        }
        return ToolCall(
            function: ToolCall.FunctionCall(
                name: name,
                arguments: jsonValue
            )
        )
    }

    // MARK: - Detection

    /// Check if content appears to contain text-based tool calls
    /// This is a fast pre-filter to avoid full parsing on every response.
    /// False positives are acceptable (parse() will reject non-tool-call content).
    /// False negatives are bugs (tool calls silently dropped).
    static func containsToolCallPatterns(_ content: String) -> Bool {
        // 1. XML tag patterns
        if content.contains("<tool_call")
            || content.contains("<tool-call")
            || content.contains("<function_call")
            || content.contains("<function-call") {
            return true
        }

        // 2. Code blocks — always try to parse
        if content.contains("```") {
            return true
        }

        // 3. Raw JSON with tool-call structure
        if content.contains("{") {
            // {"name": ..., "arguments": ...}
            if content.contains("\"name\"") && content.contains("\"arguments\"") {
                return true
            }
            // {"function": {"name": ...}}
            if content.contains("\"function\"") && content.contains("\"name\"") {
                return true
            }
        }

        // 4. JSON array
        if content.contains("[{") && content.contains("\"name\"") {
            return true
        }

        return false
    }

    // MARK: - Normalization

    /// Remove malformed tool call wrappers so they don't leak into user-visible text.
    /// Handles prefixes like `<tool_call{...}` and stray closing tags.
    private static func normalizeMalformedToolCallWrappers(_ content: String) -> String {
        var output = content
        output = removeMalformedToolCallPrefix(from: output, tagName: "tool_call")
        output = removeMalformedToolCallPrefix(from: output, tagName: "tool-call")
        output = removeMalformedToolCallPrefix(from: output, tagName: "function_call")
        output = removeMalformedToolCallPrefix(from: output, tagName: "function-call")
        output = output.replacingOccurrences(of: "</tool_call>", with: "")
        output = output.replacingOccurrences(of: "</tool-call>", with: "")
        output = output.replacingOccurrences(of: "</function_call>", with: "")
        output = output.replacingOccurrences(of: "</function-call>", with: "")
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Remove malformed opening tag prefix that starts with `<tagName` but misses a valid `>`.
    private static func removeMalformedToolCallPrefix(from content: String, tagName: String) -> String {
        guard let openRange = content.range(of: "<\(tagName)") else {
            return content
        }

        let suffix = content[openRange.lowerBound...]
        guard let braceIndex = suffix.firstIndex(of: "{") else {
            return content
        }

        let between = suffix[..<braceIndex]
        // If '>' exists before '{', this is a normal tag and should be handled elsewhere.
        guard !between.contains(">") else {
            return content
        }

        var output = content
        output.removeSubrange(openRange.lowerBound..<braceIndex)
        return output
    }
}

#endif
