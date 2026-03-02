#if MLX_ENABLED
import Foundation
import OpenFoundationModels
import OpenFoundationModelsExtra
import MLXLMCommon

// Extract information needed for prompt construction from Transcript
// using strongly-typed access via OpenFoundationModelsExtra.
package enum TranscriptAccess {
    /// Simple message representation for internal use
    package struct Message: Sendable {
        package enum Role: String, Sendable { case system, user, assistant, tool }
        package let role: Role
        package let content: String
        package let toolName: String?
    }

    package struct Extracted: Sendable {
        package var systemText: String?
        package var messages: [Message]
        package var schemaJSON: String?
        package var toolDefs: [(name: String, description: String?, parameters: JSONSchema)]
        package var imageSegments: [Transcript.ImageSegment]
    }

    package static func extract(from transcript: Transcript) -> Extracted {
        var out = Extracted(systemText: nil, messages: [], schemaJSON: nil, toolDefs: [], imageSegments: [])

        // 1) system (instructions)
        if let firstSystem = firstInstructions(transcript) {
            out.systemText = flattenTextSegments(firstSystem.segments)
            out.toolDefs = toolDefinitions(firstSystem)
        }

        // 2) History (user/assistant) and schema (from most recent prompt)
        var lastPromptRF: Transcript.ResponseFormat? = nil
        for e in transcript {
            switch e {
            case .prompt(let p):
                let text = flattenTextSegments(p.segments)
                out.messages.append(.init(role: .user, content: text, toolName: nil))
                lastPromptRF = p.responseFormat
                for segment in p.segments {
                    if case .image(let imageSegment) = segment {
                        out.imageSegments.append(imageSegment)
                    }
                }
            case .response(let r):
                let text = flattenTextSegments(r.segments)
                if !text.isEmpty {
                    out.messages.append(.init(role: .assistant, content: text, toolName: nil))
                }
            case .toolCalls(let tc):
                let callDescriptions = tc.map { call in
                    "{\"name\": \"\(call.toolName)\", \"arguments\": \(call.arguments.text)}"
                }
                let content = "{\"tool_calls\": [\(callDescriptions.joined(separator: ", "))]}"
                out.messages.append(.init(role: .assistant, content: content, toolName: nil))
            case .toolOutput(let to):
                let text = flattenTextSegments(to.segments)
                out.messages.append(.init(role: .tool, content: text, toolName: to.toolName))
            default:
                continue
            }
        }
        if let rf = lastPromptRF, let schemaJSON = schemaJSONString(from: rf) {
            out.schemaJSON = schemaJSON
        }

        return out
    }

    // MARK: - Helpers

    private static func firstInstructions(_ t: Transcript) -> Transcript.Instructions? {
        for e in t {
            if case .instructions(let inst) = e { return inst }
        }
        return nil
    }

    private static func flattenTextSegments(_ segments: [Transcript.Segment]) -> String {
        var pieces: [String] = []
        for s in segments {
            if case .text(let txt) = s { pieces.append(txt.content) }
        }
        return pieces.joined(separator: "\n")
    }

    private static func schemaJSONString(from responseFormat: Transcript.ResponseFormat?) -> String? {
        guard let responseFormat = responseFormat,
              let schema = responseFormat._schema else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(schema._jsonSchema),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    private static func toolDefinitions(_ inst: Transcript.Instructions) -> [(String, String?, JSONSchema)] {
        inst.toolDefinitions.map { d in
            (d.name, d.description, d.parameters._jsonSchema)
        }
    }
}
#endif
