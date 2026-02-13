#if MLX_ENABLED
import Foundation
import OpenFoundationModels
import OpenFoundationModelsExtra
import MLXLMCommon
import MLXLLM

/// MLXLanguageModel is the provider adapter that conforms to the
/// OpenFoundationModels LanguageModel protocol, delegating core work to the
/// internal MLXChatEngine. This class focuses exclusively on inference with
/// pre-loaded models and does NOT handle model loading.
public struct MLXLanguageModel: OpenFoundationModels.LanguageModel, Sendable {
    private let profile: any ModelProfile
    private let backend: MLXBackend

    /// Initialize with a pre-loaded ModelContainer and ModelProfile.
    /// The model must be loaded separately using ModelLoader.
    /// - Parameters:
    ///   - modelContainer: Pre-loaded model from ModelLoader
    ///   - profile: ModelProfile that defines prompt, decoding, and sampling policy
    public init(
        modelContainer: ModelContainer,
        profile: any ModelProfile
    ) async throws {
        self.profile = profile

        let backend = MLXBackend()
        await backend.setModel(modelContainer, modelID: profile.id)
        self.backend = backend
    }

    /// Convenience initializer when you have a pre-configured backend
    /// - Parameters:
    ///   - backend: Pre-configured MLXBackend with model already set
    ///   - profile: ModelProfile that defines prompt, decoding, and sampling policy
    public init(backend: MLXBackend, profile: any ModelProfile) {
        self.profile = profile
        self.backend = backend
    }

    public var isAvailable: Bool { true }

    public func supports(locale: Locale) -> Bool { true }

    public func generate(transcript: Transcript, options: GenerationOptions?) async throws -> Transcript.Entry {
        let prompt = profile.renderPrompt(transcript: transcript, options: options)

        // Prepare parameters
        let sampling = OptionsMapper.map(options, modelProfile: profile)

        do {
            // Generate raw text through backend
            let raw = try await backend.orchestratedGenerate(
                prompt: prompt._content,
                sampling: sampling,
                modelProfile: profile
            )

            // Debug: Log generated content before processing
            Logger.info("[MLXLanguageModel] Generated content:")
            Logger.info("[MLXLanguageModel] ========== START ==========")
            Logger.info(raw)
            Logger.info("[MLXLanguageModel] ========== END ==========")

            // Decode raw output through profile decoder
            let entry = profile.decode(raw: raw, options: options)

            // Check for tool calls if needed
            let ext = TranscriptAccess.extract(from: transcript)
            if !ext.toolDefs.isEmpty {
                if case .response(let response) = entry,
                   let segment = response.segments.first,
                   case .text(let textSegment) = segment,
                   let toolEntry = ToolCallDetector.entryIfPresent(textSegment.content) {
                    return toolEntry
                }
            }

            return entry
        } catch let error as CancellationError {
            throw error
        } catch let error as MLXBackend.MLXBackendError {
            throw GenerationError.decodingFailure(.init(debugDescription: "Backend error: \(error.localizedDescription)"))
        } catch {
            throw GenerationError.decodingFailure(.init(debugDescription: String(describing: error)))
        }
    }

    public func stream(transcript: Transcript, options: GenerationOptions?) -> AsyncThrowingStream<Transcript.Entry, Error> {
        let prompt = profile.renderPrompt(transcript: transcript, options: options)
        let ext = TranscriptAccess.extract(from: transcript)
        let expectsTool = ext.toolDefs.isEmpty == false

        // Prepare parameters
        let sampling = OptionsMapper.map(options, modelProfile: profile)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try Task.checkCancellation()

                    // Get raw stream from backend
                    let rawStream = await backend.orchestratedStream(
                        prompt: prompt._content,
                        sampling: sampling,
                        modelProfile: profile
                    )

                    // Convert to AsyncThrowingStream for profile decoder
                    let throwingStream = AsyncThrowingStream<String, Error> { streamContinuation in
                        Task {
                            do {
                                for try await chunk in rawStream {
                                    streamContinuation.yield(chunk)
                                }
                                streamContinuation.finish()
                            } catch {
                                streamContinuation.finish(throwing: error)
                            }
                        }
                    }

                    // Decode streamed output through profile decoder
                    let processedStream = profile.decode(stream: throwingStream, options: options)

                    // Handle tool detection if needed
                    if expectsTool {
                        var buffer = ""
                        var emittedToolCalls = false
                        let bufferLimitBytes = 2 * 1024 * 1024

                        for try await entry in processedStream {
                            try Task.checkCancellation()

                            // Extract text content from entry
                            if case .response(let response) = entry,
                               let segment = response.segments.first,
                               case .text(let textSegment) = segment {
                                buffer += textSegment.content

                                if buffer.utf8.count > bufferLimitBytes {
                                    Logger.warning("[MLXLanguageModel] Tool detection buffer exceeded")
                                    continuation.finish(throwing: GenerationError.decodingFailure(.init(debugDescription: "Stream buffer exceeded during tool detection")))
                                    return
                                }

                                if let toolEntry = ToolCallDetector.entryIfPresent(buffer) {
                                    continuation.yield(toolEntry)
                                    emittedToolCalls = true
                                    continuation.finish()
                                    return
                                }
                            }

                            // Stream the entry if not buffering for tools
                            if !expectsTool {
                                continuation.yield(entry)
                            }
                        }

                        // If we were buffering for tools but found none, emit the buffer
                        if !emittedToolCalls && !buffer.isEmpty {
                            continuation.yield(.response(.init(assetIDs: [], segments: [.text(.init(content: buffer))])))
                        }
                    } else {
                        // No tool detection needed, stream directly
                        for try await entry in processedStream {
                            try Task.checkCancellation()
                            continuation.yield(entry)
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
}

#endif
