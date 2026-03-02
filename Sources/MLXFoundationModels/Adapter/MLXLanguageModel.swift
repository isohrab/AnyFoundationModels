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

        // Tool definitions appended to system message
        if !ext.toolDefs.isEmpty {
            var toolText = "\n\nAvailable tools:\n"
            for def in ext.toolDefs {
                toolText += "- \(def.name)"
                if let desc = def.description {
                    toolText += ": \(desc)"
                }
                if let params = def.parametersJSON {
                    toolText += "\n  Parameters: \(params)"
                }
                toolText += "\n"
            }
            toolText += "\nWhen calling a tool, respond ONLY with JSON: {\"tool_calls\": [{\"name\": \"<tool>\", \"arguments\": {...}}]}\nDo NOT describe the tool call in natural language. Output ONLY the JSON object."

            #if DEBUG
            print("[MLXLanguageModel] Tool prompt:\n\(toolText)")
            #endif

            if chatMessages.isEmpty {
                chatMessages.append(.system(toolText))
            } else {
                // Prepend tool text to existing system message
                let first = chatMessages[0]
                chatMessages[0] = .system(first.content + toolText)
            }
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

        return UserInput(chat: chatMessages)
    }
}

#endif
