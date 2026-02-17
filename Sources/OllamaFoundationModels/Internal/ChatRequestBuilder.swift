#if OLLAMA_ENABLED
import Foundation
import OpenFoundationModels

/// Result of building a chat request
struct ChatRequestBuildResult: Sendable {
    let request: ChatRequest
}

/// Builder for creating ChatRequest from Transcript
///
/// This struct consolidates the request building logic that was previously
/// duplicated between `generate()` and `stream()` methods.
struct ChatRequestBuilder: Sendable {
    let configuration: OllamaConfiguration
    let modelName: String
    let thinkingMode: ThinkingMode?

    // MARK: - Structured Output Instructions Template

    /// Instructions template for structured JSON output.
    /// Ensures models (including thinking models) produce valid JSON in a code block.
    private static let structuredOutputInstructionsTemplate = """
        # JSON Response Format

        You MUST respond with a valid JSON object wrapped in a markdown code block.

        ## Schema
        ```json
        {{schema}}
        ```

        ## Required Properties
        {{properties}}

        ## Output Format
        Your response MUST be exactly in this format:
        ```json
        {your JSON here}
        ```

        ## Rules
        1. Output ONLY a single markdown code block with ```json and ``` markers
        2. The JSON must be valid and match the schema exactly
        3. Use double quotes for all strings
        4. Do not include trailing commas
        5. No text before or after the code block
        """

    // MARK: - Build

    /// Build a ChatRequest from a Transcript
    /// - Parameters:
    ///   - transcript: The conversation transcript
    ///   - options: Optional generation options (uses transcript options if nil)
    ///   - streaming: Whether to enable streaming
    /// - Returns: A ChatRequestBuildResult containing the request
    /// - Throws: TranscriptConverterError if tool extraction fails
    func build(
        transcript: Transcript,
        options: GenerationOptions?,
        streaming: Bool
    ) throws -> ChatRequestBuildResult {
        // Convert Transcript to Ollama messages
        var messages = TranscriptConverter.buildMessages(from: transcript)

        #if DEBUG
        print("[ChatRequestBuilder] === Transcript ===")
        for entry in transcript {
            print("[ChatRequestBuilder] \(entry)")
        }
        #endif

        // Extract tools from transcript
        let tools = try TranscriptConverter.extractTools(from: transcript)

        #if DEBUG
        if let tools = tools {
            print("[ChatRequestBuilder] extractTools: \(tools.count) tools")
            for tool in tools {
                print("[ChatRequestBuilder]   \(tool.function.name)")
            }
        } else {
            print("[ChatRequestBuilder] extractTools: nil")
        }
        #endif

        // Extract response format (try full schema first, fallback to simple format)
        let responseFormat = TranscriptConverter.extractResponseFormatWithSchema(from: transcript)
            ?? TranscriptConverter.extractResponseFormat(from: transcript)

        // Use transcript options if not provided
        let finalOptions = options ?? TranscriptConverter.extractOptions(from: transcript)

        // Determine thinking mode based on response format
        // When structured output is required, override to disabled to ensure
        // output goes to content field (not thinking field).
        // Otherwise, use the instance-level thinkingMode.
        let resolvedThinkingMode: ThinkingMode?
        if responseFormat != nil && responseFormat != .text {
            // Add structured output instructions to help model produce valid JSON
            addStructuredOutputInstructions(to: &messages, format: responseFormat!)
            // Disable thinking to force output to content field
            resolvedThinkingMode = .disabled

            #if DEBUG
            print("[ChatRequestBuilder] Structured output mode enabled")
            print("[ChatRequestBuilder] === FINAL SYSTEM MESSAGE ===")
            if let sysMsg = messages.first(where: { $0.role == .system }) {
                print(sysMsg.content)
            }
            print("[ChatRequestBuilder] === END SYSTEM MESSAGE ===")
            #endif
        } else {
            resolvedThinkingMode = thinkingMode
        }

        // Build the request
        let request = ChatRequest(
            model: modelName,
            messages: messages,
            stream: streaming,
            options: finalOptions?.toOllamaOptions(),
            format: responseFormat,
            keepAlive: configuration.keepAlive,
            tools: tools,
            think: resolvedThinkingMode
        )

        #if DEBUG
        if let data = try? JSONEncoder().encode(request),
           let json = String(data: data, encoding: .utf8) {
            print("[ChatRequestBuilder] === HTTP Request Body ===")
            print(json)
            print("[ChatRequestBuilder] === END ===")
        }
        #endif

        return ChatRequestBuildResult(request: request)
    }

    // MARK: - Private Helpers

    /// Add structured output instructions to the messages
    private func addStructuredOutputInstructions(to messages: inout [Message], format: ResponseFormat) {
        let instructions = generateInstructions(for: format)
        guard !instructions.isEmpty else { return }

        // Find existing system message and append instructions
        for i in 0..<messages.count {
            if messages[i].role == .system {
                messages[i] = Message(
                    role: .system,
                    content: messages[i].content + "\n\n" + instructions
                )
                return
            }
        }

        // No system message found, insert one at the beginning
        messages.insert(Message(role: .system, content: instructions), at: 0)
    }

    /// Generate human-readable instructions from ResponseFormat
    private func generateInstructions(for format: ResponseFormat) -> String {
        switch format {
        case .jsonSchema(let container):
            let schema = container.schema
            let schemaString: String
            if let jsonData = try? JSONSerialization.data(withJSONObject: schema, options: [.prettyPrinted, .sortedKeys]),
               let str = String(data: jsonData, encoding: .utf8) {
                schemaString = str
            } else {
                schemaString = "{}"
            }

            // Extract property names and descriptions
            let properties = extractPropertyDescriptions(from: schema)

            return Self.structuredOutputInstructionsTemplate
                .replacingOccurrences(of: "{{schema}}", with: schemaString)
                .replacingOccurrences(of: "{{properties}}", with: properties)

        case .json:
            // Simple JSON format without specific schema
            return Self.structuredOutputInstructionsTemplate
                .replacingOccurrences(of: "{{schema}}", with: #"{"type":"object"}"#)
                .replacingOccurrences(of: "{{properties}}", with: "(dynamic structure)")

        case .text:
            return ""
        }
    }

    /// Extract property descriptions from schema for human-readable output
    private func extractPropertyDescriptions(from schema: [String: Any]) -> String {
        guard let properties = schema["properties"] as? [String: Any] else {
            return "(no properties defined)"
        }

        var descriptions: [String] = []
        let requiredFields = (schema["required"] as? [String]) ?? []

        for (name, propInfo) in properties.sorted(by: { $0.key < $1.key }) {
            guard let propDict = propInfo as? [String: Any] else { continue }

            let type = propDict["type"] as? String ?? "any"
            let description = propDict["description"] as? String ?? ""
            let isRequired = requiredFields.contains(name)

            var line = "- `\(name)` (\(type))"
            if isRequired {
                line += " [required]"
            }
            if !description.isEmpty {
                line += ": \(description)"
            }
            descriptions.append(line)
        }

        return descriptions.isEmpty ? "(no properties defined)" : descriptions.joined(separator: "\n")
    }
}

#endif
