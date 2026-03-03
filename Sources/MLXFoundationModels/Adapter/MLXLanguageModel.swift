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
        let requestBuilder = MLXRequestBuilder()
        let buildResult = try requestBuilder.build(transcript: transcript, options: options, stream: false)
        let parameters = makeGenerateParameters(options: options)

        // Capture native .toolCall events alongside the raw text
        let (raw, nativeCalls): (String, [(name: String, argsJSON: String)]) = try await container.perform { (context: ModelContext) in
            let lmInput = try await context.processor.prepare(input: buildResult.input)

            let stream = try MLXLMCommon.generate(
                input: lmInput,
                parameters: parameters,
                context: context
            )

            var result = ""
            var calls: [(name: String, argsJSON: String)] = []
            let encoder = JSONEncoder()
            for await generation in stream {
                switch generation {
                case .chunk(let text):
                    result += text
                case .toolCall(let call):
                    do {
                        let data = try encoder.encode(call.function.arguments)
                        if let json = String(data: data, encoding: .utf8) {
                            calls.append((name: call.function.name, argsJSON: json))
                        }
                    } catch {
                        Logger.error("[MLXLanguageModel] Failed to encode native tool call: \(error)")
                    }
                case .info:
                    break
                }
            }
            return (result, calls)
        }

        Logger.info("[MLXLanguageModel] Generated \(raw.count) characters")
        #if DEBUG
        print("[MLXLanguageModel] Raw output:\n\(raw)")
        if buildResult.expectsTool {
            print("[MLXLanguageModel] Tools registered, ToolCallDetector result: \(ToolCallDetector.entryIfPresent(raw) != nil ? "detected" : "not detected")")
        }
        #endif

        // Prefer native tool calls emitted by the model runtime
        if !nativeCalls.isEmpty,
           let toolEntry = try nativeToolCallEntry(from: nativeCalls) {
            return toolEntry
        }

        // Fallback: parse tool calls from raw text
        if buildResult.expectsTool,
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
        let parameters = makeGenerateParameters(options: options)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let requestBuilder = MLXRequestBuilder()
                    let buildResult = try requestBuilder.build(transcript: transcript, options: options, stream: true)
                    let expectsTool = buildResult.expectsTool

                    try await container.perform { (context: ModelContext) in
                        let lmInput = try await context.processor.prepare(input: buildResult.input)

                        let stream = try MLXLMCommon.generate(
                            input: lmInput,
                            parameters: parameters,
                            context: context
                        )

                        if expectsTool {
                            var buffer = ""
                            var nativeCalls: [(name: String, argsJSON: String)] = []
                            let encoder = JSONEncoder()
                            for await generation in stream {
                                try Task.checkCancellation()
                                switch generation {
                                case .chunk(let text):
                                    buffer += text
                                case .toolCall(let call):
                                    do {
                                        let data = try encoder.encode(call.function.arguments)
                                        if let json = String(data: data, encoding: .utf8) {
                                            nativeCalls.append((name: call.function.name, argsJSON: json))
                                        }
                                    } catch {
                                        Logger.error("[MLXLanguageModel] Failed to encode native tool call: \(error)")
                                    }
                                case .info:
                                    break
                                }
                            }

                            #if DEBUG
                            print("[MLXLanguageModel] Stream buffer (tool mode):\n\(buffer)")
                            print("[MLXLanguageModel] ToolCallDetector result: \(ToolCallDetector.entryIfPresent(buffer) != nil ? "detected" : "not detected")")
                            #endif

                            // Prefer native tool calls emitted by the model runtime
                            if !nativeCalls.isEmpty,
                               let toolEntry = try nativeToolCallEntry(from: nativeCalls) {
                                continuation.yield(toolEntry)
                            } else if let toolEntry = ToolCallDetector.entryIfPresent(buffer) {
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

    /// Convert native MLXLMCommon tool call captures to a Transcript.Entry.
    private func nativeToolCallEntry(
        from infos: [(name: String, argsJSON: String)]
    ) throws -> Transcript.Entry? {
        guard !infos.isEmpty else { return nil }

        let calls: [Transcript.ToolCall] = try infos.map { info in
            let content = try GeneratedContent(json: info.argsJSON)
            return Transcript.ToolCall(id: UUID().uuidString, toolName: info.name, arguments: content)
        }

        let toolCalls = Transcript.ToolCalls(id: UUID().uuidString, calls)
        return .toolCalls(toolCalls)
    }
}

#endif
