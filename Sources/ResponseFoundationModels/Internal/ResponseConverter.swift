#if RESPONSE_ENABLED
import Foundation
import OpenFoundationModels
import JSONSchema

/// Converts Responses API output to Transcript entries
struct ResponseConverter {

    /// Convert a ResponseObject to Transcript entries
    /// Returns tool calls entry if function calls exist, otherwise returns text response.
    /// When both exist, returns tool calls (text is typically not meaningful alongside tool calls).
    static func convert(_ response: ResponseObject) -> Transcript.Entry {
        var functionCalls: [Transcript.ToolCall] = []
        var textParts: [String] = []

        for item in response.output {
            switch item {
            case .functionCall(let fc):
                let argumentsContent = parseArguments(fc.arguments ?? "{}")
                functionCalls.append(
                    Transcript.ToolCall(
                        id: fc.callId ?? fc.id ?? UUID().uuidString,
                        toolName: fc.name ?? "",
                        arguments: argumentsContent
                    )
                )
            case .message(let msg):
                if let content = msg.content {
                    for part in content {
                        if let text = part.text {
                            textParts.append(text)
                        }
                    }
                }
            }
        }

        if !functionCalls.isEmpty {
            return .toolCalls(Transcript.ToolCalls(functionCalls))
        }

        let text = textParts.joined()
        return .response(
            Transcript.Response(
                assetIDs: [],
                segments: [.text(Transcript.TextSegment(content: text))]
            )
        )
    }

    /// Parse JSON arguments string into GeneratedContent
    /// Uses JSONValue (Codable-based) to avoid NSNumber Bool/Int ambiguity.
    static func parseArguments(_ json: String) -> GeneratedContent {
        guard let data = json.data(using: .utf8),
              let jsonValue = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return GeneratedContent(kind: .structure(properties: [:], orderedKeys: []))
        }
        return convertJSONValueToGeneratedContent(jsonValue)
    }

    /// Convert JSONValue to GeneratedContent (type-safe, no NSNumber ambiguity)
    static func convertJSONValueToGeneratedContent(_ value: JSONValue) -> GeneratedContent {
        switch value {
        case .null:
            return GeneratedContent(kind: .null)
        case .bool(let boolValue):
            return GeneratedContent(kind: .bool(boolValue))
        case .int(let intValue):
            return GeneratedContent(kind: .number(Double(intValue)))
        case .double(let doubleValue):
            return GeneratedContent(kind: .number(doubleValue))
        case .string(let stringValue):
            return GeneratedContent(kind: .string(stringValue))
        case .array(let elements):
            let converted = elements.map { convertJSONValueToGeneratedContent($0) }
            return GeneratedContent(kind: .array(converted))
        case .object(let dict):
            let properties = dict.mapValues { convertJSONValueToGeneratedContent($0) }
            let orderedKeys = Array(dict.keys).sorted()
            return GeneratedContent(kind: .structure(properties: properties, orderedKeys: orderedKeys))
        }
    }
}

#endif
