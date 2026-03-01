#if CLAUDE_ENABLED
import Foundation
import OpenFoundationModels
import OpenFoundationModelsExtra
import JSONSchema

/// Errors that can occur during transcript conversion
internal enum TranscriptConverterError: Error {
    case invalidSchemaFormat
}

/// Converts OpenFoundationModels Transcript to Claude API formats
internal struct TranscriptConverter {

    // MARK: - Message Building

    /// Build Claude messages from Transcript
    /// Returns (messages, systemPrompt)
    static func buildMessages(from transcript: Transcript) -> ([Message], String?) {
        var messages: [Message] = []
        var systemPrompt: String? = nil
        var pendingToolResults: [ContentBlock] = []
        // Track tool call IDs to match with tool outputs
        // Claude requires tool_result to reference the tool_use ID, not a separate ID
        var pendingToolCallIds: [String] = []

        for entry in transcript {
            switch entry {
            case .instructions(let instructions):
                // Convert instructions to system prompt (Claude uses separate system param)
                let content = extractText(from: instructions.segments)
                if !content.isEmpty {
                    systemPrompt = content
                }

            case .prompt(let prompt):
                // If there are pending tool results, add them first
                if !pendingToolResults.isEmpty {
                    messages.append(Message(role: .user, content: pendingToolResults))
                    pendingToolResults = []
                }

                // Convert prompt to user message
                // Use content blocks when images are present for native image support
                let hasImages = prompt.segments.contains { if case .image = $0 { return true }; return false }
                if hasImages {
                    let blocks = convertSegmentsToContentBlocks(prompt.segments)
                    messages.append(Message(role: .user, content: blocks))
                } else {
                    let content = extractText(from: prompt.segments)
                    messages.append(Message(role: .user, content: content))
                }

            case .response(let response):
                // Flush pending tool results before adding assistant message
                if !pendingToolResults.isEmpty {
                    messages.append(Message(role: .user, content: pendingToolResults))
                    pendingToolResults = []
                }
                // Convert response to assistant message
                let content = extractText(from: response.segments)
                messages.append(Message(role: .assistant, content: content))

            case .toolCalls(let toolCalls):
                // Flush pending tool results from previous round before adding new tool_use message
                if !pendingToolResults.isEmpty {
                    messages.append(Message(role: .user, content: pendingToolResults))
                    pendingToolResults = []
                }
                // Convert tool calls to assistant message with tool_use blocks
                let blocks = convertToolCallsToBlocks(toolCalls)
                messages.append(Message(role: .assistant, content: blocks))
                // Store the tool call IDs for matching with subsequent tool outputs
                pendingToolCallIds = toolCalls.map { $0.id }

            case .toolOutput(let toolOutput):
                // Accumulate tool results to be sent as a user message
                // Use the tool call ID from the pending list, not the tool output's own ID
                let content = extractText(from: toolOutput.segments)
                let toolUseId: String
                if !pendingToolCallIds.isEmpty {
                    toolUseId = pendingToolCallIds.removeFirst()
                } else {
                    // Fallback: try to find matching tool call by tool name
                    toolUseId = toolOutput.id
                }
                let resultBlock = ContentBlock.toolResult(ToolResultBlock(
                    toolUseId: toolUseId,
                    content: content
                ))
                pendingToolResults.append(resultBlock)
            }
        }

        // Add any remaining tool results
        if !pendingToolResults.isEmpty {
            messages.append(Message(role: .user, content: pendingToolResults))
        }

        return (messages, systemPrompt)
    }

    // MARK: - Tool Extraction

    /// Extract tool definitions from Transcript
    static func extractTools(from transcript: Transcript) throws -> [Tool]? {
        for entry in transcript.reversed() {
            if case .instructions(let instructions) = entry,
               !instructions.toolDefinitions.isEmpty {
                return try instructions.toolDefinitions.map { try convertToolDefinition($0) }
            }
        }
        return nil
    }

    // MARK: - Response Format Extraction

    /// Extract response format with schema from the most recent prompt
    static func extractResponseFormat(from transcript: Transcript) -> GenerationSchema? {
        for entry in transcript.reversed() {
            if case .prompt(let prompt) = entry,
               let responseFormat = prompt.responseFormat,
               let schema = responseFormat._schema {
                return schema
            }
        }
        return nil
    }

    // MARK: - Generation Options Extraction

    /// Extract generation options from the most recent prompt
    static func extractOptions(from transcript: Transcript) -> GenerationOptions? {
        for entry in transcript.reversed() {
            if case .prompt(let prompt) = entry {
                return prompt.options
            }
        }
        return nil
    }

    // MARK: - Private Helper Methods

    /// Extract text from segments
    /// Image segments are represented as `[Image #N]` placeholders
    private static func extractText(from segments: [Transcript.Segment]) -> String {
        var texts: [String] = []
        var imageIndex = 1

        for segment in segments {
            switch segment {
            case .text(let textSegment):
                texts.append(textSegment.content)

            case .structure(let structuredSegment):
                let content = structuredSegment.content
                texts.append(formatGeneratedContent(content))

            case .image:
                texts.append("[Image #\(imageIndex)]")
                imageIndex += 1
            }
        }

        return texts.joined(separator: " ")
    }

    /// Convert segments to Claude content blocks for native image support
    private static func convertSegmentsToContentBlocks(
        _ segments: [Transcript.Segment]
    ) -> [ContentBlock] {
        segments.compactMap { segment in
            switch segment {
            case .text(let textSegment):
                return .text(TextBlock(text: textSegment.content))
            case .structure(let structuredSegment):
                return .text(TextBlock(text: formatGeneratedContent(structuredSegment.content)))
            case .image(let imageSegment):
                switch imageSegment.source {
                case .base64(let data, let mediaType):
                    return .image(ImageBlock(source: .init(
                        type: "base64", mediaType: mediaType, data: data, url: nil
                    )))
                case .url(let url):
                    return .image(ImageBlock(source: .init(
                        type: "url", mediaType: nil, data: nil, url: url.absoluteString
                    )))
                }
            }
        }
    }

    /// Format GeneratedContent as string
    private static func formatGeneratedContent(_ content: GeneratedContent) -> String {
        content.jsonString
    }

    /// Convert Transcript.ToolDefinition to Claude Tool
    private static func convertToolDefinition(_ definition: Transcript.ToolDefinition) throws -> Tool {
        // Convert GenerationSchema to JSONValue via Codable round-trip
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let jsonData = try encoder.encode(definition.parameters)
        var schemaValue = try JSONDecoder().decode(JSONValue.self, from: jsonData)

        // Apply Claude API requirements
        schemaValue = setAdditionalPropertiesFalse(schemaValue)
        schemaValue = stripNonStandardSchemaKeys(schemaValue)

        // Remove root-level "description" from input_schema
        // (e.g. "Generated Arguments" from @Generable) - Claude API doesn't expect it here
        if case .object(var dict) = schemaValue {
            dict.removeValue(forKey: "description")
            schemaValue = .object(dict)
        }

        return Tool(
            name: definition.name,
            description: definition.description,
            inputSchema: schemaValue
        )
    }

    /// Convert Transcript.ToolCalls to Claude content blocks
    private static func convertToolCallsToBlocks(_ toolCalls: Transcript.ToolCalls) -> [ContentBlock] {
        var blocks: [ContentBlock] = []

        for toolCall in toolCalls {
            let inputValue = convertGeneratedContentToJSONValue(toolCall.arguments)

            let block = ContentBlock.toolUse(ToolUseBlock(
                id: toolCall.id,
                name: toolCall.toolName,
                input: inputValue
            ))

            blocks.append(block)
        }

        return blocks
    }

    /// Convert GeneratedContent to JSONValue
    private static func convertGeneratedContentToJSONValue(_ content: GeneratedContent) -> JSONValue {
        switch content.kind {
        case .null:
            return .null
        case .bool(let value):
            return .bool(value)
        case .number(let value):
            // Preserve integer values when possible
            if value == Double(Int(value)) && !value.isNaN && !value.isInfinite {
                return .int(Int(value))
            }
            return .double(value)
        case .string(let value):
            return .string(value)
        case .array(let elements):
            return .array(elements.map { convertGeneratedContentToJSONValue($0) })
        case .structure(let properties, _):
            var dict: [String: JSONValue] = [:]
            for (key, value) in properties {
                dict[key] = convertGeneratedContentToJSONValue(value)
            }
            return .object(dict)
        }
    }
}

// MARK: - Claude API Schema Fixup

/// Recursively strips non-standard JSON Schema keys that Claude API rejects.
/// FoundationModels @Generable generates `title` and `x-order` which are not
/// part of JSON Schema draft 2020-12 as accepted by Claude tool input_schema.
internal func stripNonStandardSchemaKeys(_ value: JSONValue) -> JSONValue {
    guard case .object(var dict) = value else { return value }

    dict.removeValue(forKey: "title")
    dict.removeValue(forKey: "x-order")

    if let properties = dict["properties"], case .object(var propDict) = properties {
        for (key, propValue) in propDict {
            propDict[key] = stripNonStandardSchemaKeys(propValue)
        }
        dict["properties"] = .object(propDict)
    }

    if let items = dict["items"] {
        dict["items"] = stripNonStandardSchemaKeys(items)
    }

    if let anyOf = dict["anyOf"], case .array(let schemas) = anyOf {
        dict["anyOf"] = .array(schemas.map { stripNonStandardSchemaKeys($0) })
    }

    return .object(dict)
}

/// Recursively sets `"additionalProperties": false` on all object schemas
/// with `"properties"`, as required by the Claude API for structured outputs and tool input schemas.
internal func setAdditionalPropertiesFalse(_ value: JSONValue) -> JSONValue {
    guard case .object(var dict) = value else { return value }

    // Check if this schema represents an object type.
    // Handles both `"type": "object"` and `"type": ["object", "null"]` (nullable object).
    let isObjectType: Bool
    if case .string("object") = dict["type"] {
        isObjectType = true
    } else if case .array(let types) = dict["type"], types.contains(.string("object")) {
        isObjectType = true
    } else {
        isObjectType = false
    }

    if isObjectType, dict["properties"] != nil {
        dict["additionalProperties"] = .bool(false)
    }

    if let properties = dict["properties"], case .object(var propDict) = properties {
        for (key, propValue) in propDict {
            propDict[key] = setAdditionalPropertiesFalse(propValue)
        }
        dict["properties"] = .object(propDict)
    }

    if let items = dict["items"] {
        dict["items"] = setAdditionalPropertiesFalse(items)
    }

    if let anyOf = dict["anyOf"], case .array(let schemas) = anyOf {
        dict["anyOf"] = .array(schemas.map { setAdditionalPropertiesFalse($0) })
    }

    return .object(dict)
}

#endif
