#if RESPONSE_ENABLED
import Foundation
import OpenFoundationModels

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
    static func parseArguments(_ json: String) -> GeneratedContent {
        guard let data = json.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data) else {
            return GeneratedContent(kind: .structure(properties: [:], orderedKeys: []))
        }
        return convertJSONToGeneratedContent(jsonObject)
    }

    /// Convert arbitrary JSON to GeneratedContent
    static func convertJSONToGeneratedContent(_ json: Any) -> GeneratedContent {
        switch json {
        case let string as String:
            return GeneratedContent(kind: .string(string))
        case let number as NSNumber:
            if number.isBool {
                return GeneratedContent(kind: .bool(number.boolValue))
            } else {
                return GeneratedContent(kind: .number(number.doubleValue))
            }
        case let array as [Any]:
            let elements = array.map { convertJSONToGeneratedContent($0) }
            return GeneratedContent(kind: .array(elements))
        case let dict as [String: Any]:
            let properties = dict.mapValues { convertJSONToGeneratedContent($0) }
            let orderedKeys = Array(dict.keys).sorted()
            return GeneratedContent(kind: .structure(properties: properties, orderedKeys: orderedKeys))
        case is NSNull:
            return GeneratedContent(kind: .null)
        default:
            return GeneratedContent(kind: .null)
        }
    }
}

// MARK: - NSNumber Bool Detection

private extension NSNumber {
    var isBool: Bool {
        let boolID = CFBooleanGetTypeID()
        let numID = CFGetTypeID(self)
        return numID == boolID
    }
}

#endif
