#if MLX_ENABLED
import Foundation
import OpenFoundationModels
import OpenFoundationModelsExtra
@preconcurrency import MLXLMCommon

/// Builds UserInput from Transcript for MLX on-device inference.
internal struct MLXRequestBuilder: OpenFoundationModelsExtra.RequestBuilder {

    // MARK: - Build Result

    struct BuildResult: Sendable {
        let input: UserInput
        let expectsTool: Bool
    }

    // MARK: - RequestBuilder Protocol

    func build(transcript: Transcript, options: GenerationOptions?, stream: Bool) throws -> BuildResult {
        let resolved = transcript.resolved()
        let expectsTool = !resolved.toolDefinitions.isEmpty
        let input = try buildUserInput(from: resolved)
        #if DEBUG
        print(
            "[MLXRequestBuilder] build stream=\(stream) entries=\(resolved.count) toolDefinitions=\(resolved.toolDefinitions.count) expectsTool=\(expectsTool)"
        )
        #endif
        return BuildResult(input: input, expectsTool: expectsTool)
    }

    // MARK: - UserInput Building

    private func buildUserInput(from resolved: ResolvedTranscript) throws -> UserInput {
        // Extract image segments from prompt entries
        var imageSegments: [Transcript.ImageSegment] = []
        for entry in resolved {
            if case .prompt(let p) = entry {
                for segment in p.segments {
                    if case .image(let img) = segment {
                        imageSegments.append(img)
                    }
                }
            }
        }
        let images = try ImageSourceConverter.convert(imageSegments)

        // Extract schema JSON from response format
        var schemaJSON: String? = nil
        if let schema = resolved.latestResponseFormat?._schema {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            do {
                let schemaData = try encoder.encode(schema)
                schemaJSON = String(data: schemaData, encoding: .utf8)
            } catch {
                // Schema encoding failed — proceed without schema constraint
            }
        }

        // Collect raw messages as (type, content) pairs
        enum MsgType { case system, user, assistant, tool }
        var rawMessages: [(type: MsgType, content: String)] = []

        for entry in resolved {
            switch entry {
            case .instructions(let i):
                let text = segmentsToText(i.segments)
                if !text.isEmpty { rawMessages.append((.system, text)) }
            case .prompt(let p):
                rawMessages.append((.user, segmentsToText(p.segments)))
            case .response(let r):
                rawMessages.append((.assistant, segmentsToText(r.segments)))
            case .tool(let interaction):
                let toolText = interaction.calls
                    .map { "\($0.toolName)(\($0.arguments.jsonString))" }
                    .joined(separator: "\n")
                if !toolText.isEmpty { rawMessages.append((.assistant, toolText)) }
                for output in interaction.outputs {
                    rawMessages.append((.tool, segmentsToText(output.segments)))
                }
            }
        }

        // Build Chat.Message list
        var chatMessages: [Chat.Message] = []

        // System message (merged with schema if present)
        if let firstSystem = rawMessages.first(where: { $0.type == .system }) {
            var systemContent = firstSystem.content
            if let schema = schemaJSON {
                systemContent += "\n\nRespond with JSON matching this schema:\n\(schema)"
            }
            chatMessages.append(.system(systemContent))
        } else if let schema = schemaJSON {
            chatMessages.append(.system("Respond with JSON matching this schema:\n\(schema)"))
        }

        // User/assistant/tool messages — attach images to last user message only
        let nonSystemMessages = rawMessages.filter { $0.type != .system }
        let lastUserIndex = nonSystemMessages.lastIndex(where: { $0.type == .user })

        for (index, msg) in nonSystemMessages.enumerated() {
            switch msg.type {
            case .user:
                if index == lastUserIndex && !images.isEmpty {
                    chatMessages.append(.user(msg.content, images: images))
                } else {
                    chatMessages.append(.user(msg.content))
                }
            case .assistant:
                chatMessages.append(.assistant(msg.content))
            case .tool:
                chatMessages.append(.tool(msg.content))
            case .system:
                break
            }
        }

        let toolSpecs = buildToolSpecs(from: resolved.toolDefinitions)
        #if DEBUG
        print(
            "[MLXRequestBuilder] messages system=\(rawMessages.filter { $0.type == .system }.count) user=\(rawMessages.filter { $0.type == .user }.count) assistant=\(rawMessages.filter { $0.type == .assistant }.count) tool=\(rawMessages.filter { $0.type == .tool }.count) images=\(images.count) toolSpecs=\(toolSpecs?.count ?? 0)"
        )
        #endif
        return UserInput(chat: chatMessages, tools: toolSpecs)
    }

    // MARK: - Tool Specs

    private func buildToolSpecs(
        from toolDefs: [Transcript.ToolDefinition]
    ) -> [[String: any Sendable]]? {
        guard !toolDefs.isEmpty else { return nil }

        let specs: [[String: any Sendable]] = toolDefs.compactMap { def in
            var function: [String: any Sendable] = [
                "name": def.name,
                "description": def.description
            ]
            do {
                let jsonValue = try JSONValue(def.parameters)
                function["parameters"] = jsonValue.sendableValue
            } catch {
                // Skip parameters if conversion fails
            }
            return [
                "type": "function" as any Sendable,
                "function": function as any Sendable
            ]
        }

        return specs.isEmpty ? nil : specs
    }
}

#endif
