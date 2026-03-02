#if OLLAMA_ENABLED
import Foundation
import OpenFoundationModels
import OpenFoundationModelsCore
import OpenFoundationModelsExtra

/// Converts OpenFoundationModels Transcript to Ollama API formats
internal struct TranscriptConverter {

    // MARK: - Message Building

    /// Build Ollama messages from Transcript
    static func buildMessages(from transcript: Transcript) -> [Message] {
        var messages: [Message] = []

        // Use _entries from OpenFoundationModelsExtra for direct access
        for entry in transcript._entries {
            switch entry {
            case .instructions(let instructions):
                // Convert instructions to system message
                let content = extractText(from: instructions.segments)
                if !content.isEmpty {
                    messages.append(Message(role: .system, content: content))
                }

            case .prompt(let prompt):
                // Convert prompt to user message
                let content = extractText(from: prompt.segments)
                let images = extractImages(from: prompt.segments)
                messages.append(Message(role: .user, content: content, images: images))

            case .response(let response):
                // Convert response to assistant message
                let content = extractText(from: response.segments)
                messages.append(Message(role: .assistant, content: content))

            case .toolCalls(let toolCalls):
                // Convert tool calls to assistant message with tool calls
                let ollamaToolCalls = convertToolCalls(toolCalls)
                messages.append(Message(
                    role: .assistant,
                    content: "",
                    toolCalls: ollamaToolCalls
                ))

            case .toolOutput(let toolOutput):
                // Convert tool output to tool message
                let content = extractText(from: toolOutput.segments)
                messages.append(Message(
                    role: .tool,
                    content: content,
                    toolName: toolOutput.toolName
                ))
            }
        }

        return messages
    }

    // MARK: - Tool Extraction

    /// Extract tool definitions from Transcript
    /// Uses the most recent instructions with toolDefinitions (consistent with extractOptions and extractResponseFormat)
    static func extractTools(from transcript: Transcript) -> [Tool]? {
        for entry in transcript._entries.reversed() {
            if case .instructions(let instructions) = entry,
               !instructions.toolDefinitions.isEmpty {
                return instructions.toolDefinitions.map { convertToolDefinition($0) }
            }
        }
        return nil
    }

    // MARK: - Response Format Extraction

    /// Extract response format with schema from the most recent prompt
    static func extractResponseFormatWithSchema(from transcript: Transcript) -> ResponseFormat? {
        for entry in transcript._entries.reversed() {
            if case .prompt(let prompt) = entry,
               let responseFormat = prompt.responseFormat,
               let schema = responseFormat._schema {
                return .jsonSchema(schema._jsonSchema)
            } else if case .prompt(let prompt) = entry,
                      let _ = prompt.responseFormat {
                return .json
            }
        }
        return nil
    }

    /// Extract response format from the most recent prompt (simplified version)
    static func extractResponseFormat(from transcript: Transcript) -> ResponseFormat? {
        return extractResponseFormatWithSchema(from: transcript)
    }

    // MARK: - Generation Options Extraction

    /// Extract generation options from the most recent prompt
    static func extractOptions(from transcript: Transcript) -> GenerationOptions? {
        // Use _entries from OpenFoundationModelsExtra for direct access
        for entry in transcript._entries.reversed() {
            if case .prompt(let prompt) = entry {
                return prompt.options
            }
        }
        return nil
    }

    // MARK: - Private Helper Methods

    /// Extract text from segments
    /// Image segments are represented as `[Image #N]` placeholders to indicate their position
    private static func extractText(from segments: [Transcript.Segment]) -> String {
        var texts: [String] = []
        var imageIndex = 1

        for segment in segments {
            switch segment {
            case .text(let textSegment):
                texts.append(textSegment.content)

            case .structure(let structuredSegment):
                // Convert structured content to string
                let content = structuredSegment.content
                texts.append(formatGeneratedContent(content))

            case .image:
                texts.append("[Image #\(imageIndex)]")
                imageIndex += 1
            }
        }

        return texts.joined(separator: " ")
    }

    /// Extract base64 image data from segments
    /// Ollama accepts base64-encoded images via the `images` field
    private static func extractImages(from segments: [Transcript.Segment]) -> [String]? {
        let images = segments.compactMap { segment -> String? in
            guard case .image(let imageSegment) = segment else { return nil }
            switch imageSegment.source {
            case .base64(let data, _):
                return data
            case .url:
                return nil
            }
        }
        return images.isEmpty ? nil : images
    }

    /// Format GeneratedContent as string
    private static func formatGeneratedContent(_ content: GeneratedContent) -> String {
        // Try to get JSON representation first
        if let jsonData = try? JSONEncoder().encode(content),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }

        // Fallback to string representation
        return "[GeneratedContent]"
    }

    /// Convert Transcript.ToolDefinition to Ollama Tool
    private static func convertToolDefinition(_ definition: Transcript.ToolDefinition) -> Tool {
        Tool(
            type: "function",
            function: Tool.Function(
                name: definition.name,
                description: definition.description,
                parameters: definition.parameters._jsonSchema
            )
        )
    }

    /// Convert Transcript.ToolCalls to Ollama ToolCalls
    private static func convertToolCalls(_ toolCalls: Transcript.ToolCalls) -> [ToolCall] {
        toolCalls._calls.compactMap { toolCall in
            guard let data = toolCall.arguments.jsonString.data(using: .utf8),
                  let arguments = try? JSONDecoder().decode(JSONValue.self, from: data) else {
                return nil
            }
            return ToolCall(
                function: ToolCall.FunctionCall(
                    name: toolCall.toolName,
                    arguments: arguments
                )
            )
        }
    }
}
#endif
