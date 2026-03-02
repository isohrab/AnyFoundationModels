#if MLX_ENABLED
import Foundation
import OpenFoundationModels
import OpenFoundationModelsExtra
@preconcurrency import MLXLMCommon

public struct MLXLanguageModel: OpenFoundationModels.LanguageModel, Sendable {

    private let container: ModelContainer

    public init(modelContainer: ModelContainer) {
        self.container = modelContainer
    }

    public var isAvailable: Bool { true }

    public func supports(locale: Locale) -> Bool { true }

    // MARK: - Generate

    public func generate(
        transcript: Transcript,
        options: GenerationOptions?
    ) async throws -> Transcript.Entry {
        let ext = TranscriptAccess.extract(from: transcript)
        let parameters = makeGenerateParameters(options: options)
        let userInput = try buildUserInput(from: ext)

        let raw: String = try await container.perform { (context: ModelContext) in
            let lmInput = try await context.processor.prepare(input: userInput)

            let stream = try MLXLMCommon.generate(
                input: lmInput,
                parameters: parameters,
                context: context
            )

            var result = ""
            for await generation in stream {
                switch generation {
                case .chunk(let text):
                    result += text
                case .info, .toolCall:
                    break
                }
            }
            return result
        }

        Logger.info("[MLXLanguageModel] Generated \(raw.count) characters")
        #if DEBUG
        print("[MLXLanguageModel] Raw output:\n\(raw)")
        if !ext.toolDefs.isEmpty {
            print("[MLXLanguageModel] Tools registered: \(ext.toolDefs.map(\.name))")
            print("[MLXLanguageModel] ToolCallDetector result: \(ToolCallDetector.entryIfPresent(raw) != nil ? "detected" : "not detected")")
        }
        #endif

        if !ext.toolDefs.isEmpty,
           let toolEntry = ToolCallDetector.entryIfPresent(raw) {
            return toolEntry
        }

        return .response(.init(assetIDs: [], segments: [.text(.init(content: raw))]))
    }

    // MARK: - Stream

    public func stream(
        transcript: Transcript,
        options: GenerationOptions?
    ) -> AsyncThrowingStream<Transcript.Entry, Error> {
        let ext = TranscriptAccess.extract(from: transcript)
        let expectsTool = !ext.toolDefs.isEmpty
        let parameters = makeGenerateParameters(options: options)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let userInput = try buildUserInput(from: ext)

                    try await container.perform { (context: ModelContext) in
                        let lmInput = try await context.processor.prepare(input: userInput)

                        let stream = try MLXLMCommon.generate(
                            input: lmInput,
                            parameters: parameters,
                            context: context
                        )

                        if expectsTool {
                            var buffer = ""
                            for await generation in stream {
                                try Task.checkCancellation()
                                switch generation {
                                case .chunk(let text):
                                    buffer += text
                                case .info, .toolCall:
                                    break
                                }
                            }

                            #if DEBUG
                            print("[MLXLanguageModel] Stream buffer (tool mode):\n\(buffer)")
                            print("[MLXLanguageModel] ToolCallDetector result: \(ToolCallDetector.entryIfPresent(buffer) != nil ? "detected" : "not detected")")
                            #endif

                            if let toolEntry = ToolCallDetector.entryIfPresent(buffer) {
                                continuation.yield(toolEntry)
                            } else if !buffer.isEmpty {
                                continuation.yield(.response(.init(
                                    assetIDs: [],
                                    segments: [.text(.init(content: buffer))]
                                )))
                            }
                        } else {
                            for await generation in stream {
                                try Task.checkCancellation()
                                switch generation {
                                case .chunk(let text):
                                    continuation.yield(.response(.init(
                                        assetIDs: [],
                                        segments: [.text(.init(content: text))]
                                    )))
                                case .info, .toolCall:
                                    break
                                }
                            }
                        }
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    Logger.error("[MLXLanguageModel] Stream error: \(error)")
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Private

    private func makeGenerateParameters(options: GenerationOptions?) -> GenerateParameters {
        GenerateParameters(
            maxTokens: options?.maximumResponseTokens ?? 2048,
            temperature: options?.temperature.map { Float($0) } ?? 0,
            topP: 0.9,
            repetitionPenalty: 1.2,
            repetitionContextSize: 64
        )
    }

    private func buildUserInput(
        from ext: TranscriptAccess.Extracted
    ) throws -> UserInput {
        let images = try ImageSourceConverter.convert(ext.imageSegments)

        var chatMessages: [Chat.Message] = []

        // System message (with schema appended if present)
        if let systemText = ext.systemText {
            var systemContent = systemText
            if let schema = ext.schemaJSON {
                systemContent += "\n\nRespond with JSON matching this schema:\n\(schema)"
            }
            chatMessages.append(.system(systemContent))
        } else if let schema = ext.schemaJSON {
            chatMessages.append(.system("Respond with JSON matching this schema:\n\(schema)"))
        }

        // User/assistant messages — attach images to last user message only
        let lastUserIndex = ext.messages.lastIndex(where: { $0.role == .user })
        for (index, message) in ext.messages.enumerated() {
            switch message.role {
            case .user:
                if index == lastUserIndex && !images.isEmpty {
                    chatMessages.append(.user(message.content, images: images))
                } else {
                    chatMessages.append(.user(message.content))
                }
            case .assistant:
                chatMessages.append(.assistant(message.content))
            case .tool:
                chatMessages.append(.tool(message.content))
            case .system:
                break
            }
        }

        let toolSpecs = buildToolSpecs(from: ext.toolDefs)
        return UserInput(chat: chatMessages, tools: toolSpecs)
    }

    /// Convert extracted tool definitions to ToolSpec format for the chat template pipeline.
    ///
    /// Each ToolSpec follows the OpenAI function calling format that chat templates expect.
    /// The chat template (Jinja) handles model-specific formatting (LFM2, Qwen3.5, etc.).
    private func buildToolSpecs(
        from toolDefs: [(name: String, description: String?, parameters: JSONSchema)]
    ) -> [[String: any Sendable]]? {
        guard !toolDefs.isEmpty else { return nil }

        let specs: [[String: any Sendable]] = toolDefs.compactMap { def in
            var function: [String: any Sendable] = ["name": def.name]

            if let desc = def.description {
                function["description"] = desc
            }

            if let jsonValue = try? JSONValue(def.parameters) {
                function["parameters"] = jsonValue.sendableValue
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
