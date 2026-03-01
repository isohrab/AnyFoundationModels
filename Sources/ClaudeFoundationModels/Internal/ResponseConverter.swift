#if CLAUDE_ENABLED
import Foundation
import OpenFoundationModels

/// Converts Claude API responses to OpenFoundationModels Transcript.Entry values.
internal struct ResponseConverter {

    /// Create a text response entry from a content string.
    static func createTextResponseEntry(content: String) -> Transcript.Entry {
        .response(
            Transcript.Response(
                id: UUID().uuidString,
                assetIDs: [],
                segments: [.text(Transcript.TextSegment(
                    id: UUID().uuidString,
                    content: content
                ))]
            )
        )
    }

    /// Create a structured response entry from accumulated text and schema.
    /// Used by both generate() and stream() paths.
    static func createResponseEntry(fromText text: String, schema: GenerationSchema) -> Transcript.Entry? {
        guard let generatedContent = SchemaConverter.parseJSONWithSchema(text, schema: schema) else {
            return nil
        }
        return .response(
            Transcript.Response(
                id: UUID().uuidString,
                assetIDs: [],
                segments: [.structure(Transcript.StructuredSegment(
                    id: UUID().uuidString,
                    source: "claude",
                    content: generatedContent
                ))]
            )
        )
    }

    /// Create a response entry from MessagesResponse (no schema).
    static func createResponseEntry(from response: MessagesResponse) -> Transcript.Entry {
        let textContent = extractTextContent(from: response)
        return createTextResponseEntry(content: textContent)
    }

    /// Create a response entry from MessagesResponse with schema-aware parsing.
    static func createResponseEntry(from response: MessagesResponse, schema: GenerationSchema) -> Transcript.Entry {
        let textContent = extractTextContent(from: response)
        if let entry = createResponseEntry(fromText: textContent, schema: schema) {
            return entry
        }
        return createTextResponseEntry(content: textContent)
    }

    /// Extract concatenated text content from a MessagesResponse.
    private static func extractTextContent(from response: MessagesResponse) -> String {
        response.content.compactMap { block in
            if case .text(let textBlock) = block { return textBlock.text }
            return nil
        }.joined()
    }

    /// Create a tool calls entry from ToolUseBlock array (non-streaming).
    static func createToolCallsEntry(from toolUseBlocks: [ToolUseBlock]) -> Transcript.Entry {
        let transcriptToolCalls = toolUseBlocks.map { toolUse in
            let argumentsContent: GeneratedContent
            do {
                let jsonData = try JSONEncoder().encode(toolUse.input)
                let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
                argumentsContent = try GeneratedContent(json: jsonString)
            } catch {
                argumentsContent = GeneratedContent(kind: .structure(properties: [:], orderedKeys: []))
            }

            return Transcript.ToolCall(
                id: toolUse.id,
                toolName: toolUse.name,
                arguments: argumentsContent
            )
        }

        return .toolCalls(
            Transcript.ToolCalls(
                id: UUID().uuidString,
                transcriptToolCalls
            )
        )
    }

    /// Create a tool calls entry from accumulated streaming data.
    static func createToolCallsEntry(from toolCalls: [(id: String, name: String, input: String)]) -> Transcript.Entry {
        let transcriptToolCalls = toolCalls.map { toolCall in
            let argumentsContent: GeneratedContent
            do {
                argumentsContent = try GeneratedContent(json: toolCall.input)
            } catch {
                argumentsContent = GeneratedContent(kind: .structure(properties: [:], orderedKeys: []))
            }

            return Transcript.ToolCall(
                id: toolCall.id,
                toolName: toolCall.name,
                arguments: argumentsContent
            )
        }

        return .toolCalls(
            Transcript.ToolCalls(
                id: UUID().uuidString,
                transcriptToolCalls
            )
        )
    }
}

#endif
