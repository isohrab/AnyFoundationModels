#if RESPONSE_ENABLED
import Foundation
import OpenFoundationModels
import OpenFoundationModelsExtra

/// Converts OpenFoundationModels Transcript to Responses API input items
struct TranscriptConverter {

    /// Build input items from a Transcript
    static func buildInputItems(from transcript: Transcript) -> [InputItem] {
        // Try JSON-based extraction first
        if let items = buildInputItemsFromJSON(transcript), !items.isEmpty {
            return items
        }
        // Fallback to entry-based
        return buildInputItemsFromEntries(transcript)
    }

    /// Extract tool definitions from Transcript
    static func extractToolDefinitions(from transcript: Transcript) -> [ToolDefinition]? {
        for entry in transcript {
            if case .instructions(let instructions) = entry,
               !instructions.toolDefinitions.isEmpty {
                return instructions.toolDefinitions.map { convertToolDefinition($0) }
            }
        }
        return nil
    }

    /// Extract generation options from the most recent prompt
    static func extractOptions(from transcript: Transcript) -> GenerationOptions? {
        for entry in transcript.reversed() {
            if case .prompt(let prompt) = entry {
                return prompt.options
            }
        }
        return nil
    }

    /// Extract response format from the most recent prompt
    static func extractResponseFormat(from transcript: Transcript) -> TextFormat? {
        for entry in transcript.reversed() {
            guard case .prompt(let prompt) = entry,
                  let responseFormat = prompt.responseFormat else {
                continue
            }

            // Use Extra accessors for direct access to internal schema
            if let schema = responseFormat._schema {
                let schemaDict = convertSchemaToDict(schema)
                let name = responseFormat.name
                return TextFormat(format: .jsonSchema(name: name, schema: schemaDict, strict: true))
            }

            if responseFormat._type != nil {
                return TextFormat(format: .jsonObject)
            }
        }
        return nil
    }

    /// Convert GenerationSchema to a JSON-compatible dictionary
    private static func convertSchemaToDict(_ schema: GenerationSchema) -> [String: Any] {
        do {
            let data = try JSONEncoder().encode(schema)
            if let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return dict
            }
        } catch {}
        return [:]
    }

    // MARK: - Private: JSON-based

    private static func buildInputItemsFromJSON(_ transcript: Transcript) -> [InputItem]? {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(transcript)

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entries = json["entries"] as? [[String: Any]] else {
                return nil
            }

            var items: [InputItem] = []
            // Track tool call IDs to match with subsequent tool outputs
            var pendingToolCallIds: [String] = []

            for entry in entries {
                guard let type = entry["type"] as? String else { continue }

                switch type {
                case "instructions":
                    if let segments = entry["segments"] as? [[String: Any]] {
                        let content = extractTextFromSegments(segments)
                        if !content.isEmpty {
                            items.append(.message(MessageItem(role: "system", content: content)))
                        }
                    }

                case "prompt":
                    if let segments = entry["segments"] as? [[String: Any]] {
                        let content = extractTextFromSegments(segments)
                        items.append(.message(MessageItem(role: "user", content: content)))
                    }

                case "response":
                    if let segments = entry["segments"] as? [[String: Any]] {
                        let content = extractTextFromSegments(segments)
                        items.append(.message(MessageItem(role: "assistant", content: content)))
                    }

                case "toolCalls":
                    let calls = extractToolCallsFromEntry(entry)
                    pendingToolCallIds = calls.map { $0.callId }
                    for call in calls {
                        items.append(.functionCall(call))
                    }

                case "toolOutput":
                    if let segments = entry["segments"] as? [[String: Any]] {
                        let content = extractTextFromSegments(segments)
                        // Use the matching tool call ID, not the output's own ID
                        let callId: String
                        if !pendingToolCallIds.isEmpty {
                            callId = pendingToolCallIds.removeFirst()
                        } else {
                            callId = entry["id"] as? String ?? UUID().uuidString
                        }
                        items.append(.functionCallOutput(
                            FunctionCallOutputItem(callId: callId, output: content)
                        ))
                    }

                default:
                    break
                }
            }

            return items.isEmpty ? nil : items
        } catch {
            return nil
        }
    }

    // MARK: - Private: Entry-based

    private static func buildInputItemsFromEntries(_ transcript: Transcript) -> [InputItem] {
        var items: [InputItem] = []
        // Track tool call IDs to match with subsequent tool outputs
        // LanguageModelSession creates ToolOutput with a random UUID, not the original call_id
        var pendingToolCallIds: [String] = []

        for entry in transcript {
            switch entry {
            case .instructions(let instructions):
                let content = extractText(from: instructions.segments)
                if !content.isEmpty {
                    items.append(.message(MessageItem(role: "system", content: content)))
                }

            case .prompt(let prompt):
                let hasImages = prompt.segments.contains { if case .image = $0 { return true }; return false }
                if hasImages {
                    let parts = convertSegmentsToContentParts(prompt.segments)
                    items.append(.message(MessageItem(role: "user", content: parts)))
                } else {
                    let content = extractText(from: prompt.segments)
                    items.append(.message(MessageItem(role: "user", content: content)))
                }

            case .response(let response):
                let content = extractText(from: response.segments)
                items.append(.message(MessageItem(role: "assistant", content: content)))

            case .toolCalls(let toolCalls):
                pendingToolCallIds = []
                for toolCall in toolCalls {
                    let argumentsDict = convertGeneratedContentToDict(toolCall.arguments)
                    let jsonData = (try? JSONSerialization.data(withJSONObject: argumentsDict)) ?? Data()
                    let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

                    items.append(.functionCall(FunctionCallItem(
                        id: nil,
                        callId: toolCall.id,
                        name: toolCall.toolName,
                        arguments: jsonString,
                        status: "completed"
                    )))
                    pendingToolCallIds.append(toolCall.id)
                }

            case .toolOutput(let toolOutput):
                let content = extractText(from: toolOutput.segments)
                // Use the matching tool call ID, not the output's own ID
                let callId: String
                if !pendingToolCallIds.isEmpty {
                    callId = pendingToolCallIds.removeFirst()
                } else {
                    callId = toolOutput.id
                }
                items.append(.functionCallOutput(
                    FunctionCallOutputItem(callId: callId, output: content)
                ))
            }
        }

        return items
    }

    // MARK: - Private: Helpers

    private static func extractTextFromSegments(_ segments: [[String: Any]]) -> String {
        var texts: [String] = []
        var imageIndex = 1
        for segment in segments {
            if let type = segment["type"] as? String {
                if type == "text", let content = segment["content"] as? String {
                    texts.append(content)
                } else if type == "structure" {
                    let contentKey = segment["generatedContent"] ?? segment["content"]
                    if let contentObj = contentKey,
                       let jsonData = try? JSONSerialization.data(withJSONObject: contentObj, options: [.sortedKeys]),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        texts.append(jsonString)
                    }
                } else if type == "image" {
                    texts.append("[Image #\(imageIndex)]")
                    imageIndex += 1
                }
            }
        }
        return texts.joined(separator: " ")
    }

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
                if let jsonData = try? JSONEncoder().encode(structuredSegment.content),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    texts.append(jsonString)
                }
            case .image:
                texts.append("[Image #\(imageIndex)]")
                imageIndex += 1
            }
        }
        return texts.joined(separator: " ")
    }

    /// Convert segments to Response API content parts for native image support
    private static func convertSegmentsToContentParts(
        _ segments: [Transcript.Segment]
    ) -> [InputContentPart] {
        segments.compactMap { segment in
            switch segment {
            case .text(let textSegment):
                return .text(textSegment.content)
            case .structure(let structuredSegment):
                if let jsonData = try? JSONEncoder().encode(structuredSegment.content),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    return .text(jsonString)
                }
                return nil
            case .image(let imageSegment):
                switch imageSegment.source {
                case .base64(let data, let mediaType):
                    return .image(url: "data:\(mediaType);base64,\(data)")
                case .url(let url):
                    return .image(url: url.absoluteString)
                }
            }
        }
    }

    private static func extractToolCallsFromEntry(_ entry: [String: Any]) -> [FunctionCallItem] {
        var calls: [FunctionCallItem] = []

        let toolCallsArray: [[String: Any]]?
        if let directArray = entry["toolCalls"] as? [[String: Any]] {
            toolCallsArray = directArray
        } else if let callsArray = entry["calls"] as? [[String: Any]] {
            toolCallsArray = callsArray
        } else {
            toolCallsArray = nil
        }

        guard let toolCalls = toolCallsArray else { return [] }

        for toolCall in toolCalls {
            guard let toolName = toolCall["toolName"] as? String else { continue }
            let id = toolCall["id"] as? String ?? UUID().uuidString

            var argumentsJSON = "{}"
            if let arguments = toolCall["arguments"] {
                if let jsonData = try? JSONSerialization.data(withJSONObject: arguments),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    argumentsJSON = jsonString
                }
            }

            calls.append(FunctionCallItem(
                id: nil,
                callId: id,
                name: toolName,
                arguments: argumentsJSON,
                status: "completed"
            ))
        }

        return calls
    }

    private static func convertToolDefinition(_ definition: Transcript.ToolDefinition) -> ToolDefinition {
        let schema = definition.parameters
        let jsonSchema = convertSchemaToJSONSchema(schema)

        return ToolDefinition(
            name: definition.name,
            description: definition.description,
            parameters: jsonSchema,
            strict: nil
        )
    }

    private static func convertSchemaToJSONSchema(_ schema: GenerationSchema) -> JSONSchemaObject {
        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(schema)
            if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                return parseSchemaJSON(json)
            }
        } catch {
            // Fallback
        }
        return JSONSchemaObject(type: "object", properties: nil, required: nil, additionalProperties: nil)
    }

    private static func parseSchemaJSON(_ json: [String: Any]) -> JSONSchemaObject {
        let type = json["type"] as? String ?? "object"
        var schemaProperties: [String: JSONSchemaProperty]? = nil
        if let properties = json["properties"] as? [String: [String: Any]] {
            var props: [String: JSONSchemaProperty] = [:]
            for (key, propJson) in properties {
                let propType = propJson["type"] as? String ?? "string"
                var items: JSONSchemaProperty?
                if propType == "array",
                   let itemsJson = propJson["items"] as? [String: Any] {
                    items = JSONSchemaProperty(
                        type: itemsJson["type"] as? String ?? "string",
                        description: itemsJson["description"] as? String
                    )
                }
                props[key] = JSONSchemaProperty(
                    type: propType,
                    description: propJson["description"] as? String,
                    enumValues: propJson["enum"] as? [String],
                    items: items
                )
            }
            schemaProperties = props
        }
        let required = json["required"] as? [String]
        return JSONSchemaObject(type: type, properties: schemaProperties, required: required, additionalProperties: nil)
    }

    private static func convertGeneratedContentToDict(_ content: GeneratedContent) -> [String: Any] {
        switch content.kind {
        case .structure(let properties, _):
            var dict: [String: Any] = [:]
            for (key, value) in properties {
                dict[key] = convertGeneratedContentToAny(value)
            }
            return dict
        default:
            return [:]
        }
    }

    private static func convertGeneratedContentToAny(_ content: GeneratedContent) -> Any {
        switch content.kind {
        case .null:
            return NSNull()
        case .bool(let value):
            return value
        case .number(let value):
            return value
        case .string(let value):
            return value
        case .array(let elements):
            return elements.map { convertGeneratedContentToAny($0) }
        case .structure(let properties, _):
            var dict: [String: Any] = [:]
            for (key, value) in properties {
                dict[key] = convertGeneratedContentToAny(value)
            }
            return dict
        }
    }
}

#endif
