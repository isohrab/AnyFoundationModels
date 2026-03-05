#if OLLAMA_ENABLED
import Foundation
import OpenFoundationModels
import OpenFoundationModelsCore

/// Session for streaming Generable responses with automatic retry.
///
/// The transcript must already contain the latest prompt entry before
/// being passed to this session. The session applies the structured
/// output response format and retry context to the last prompt entry
/// internally on each attempt.
///
/// ## @unchecked Sendable Justification
/// This class is marked `@unchecked Sendable` because:
/// - All properties are immutable (`let`)
/// - `model: OllamaLanguageModel` - Sendable
/// - `options: GenerableStreamOptions` - Sendable
/// - `parser: GenerableParser<T>` - Sendable
/// - `transcript: Transcript` - Sendable
/// - No mutable state after initialization
/// - Thread-safe access is guaranteed by immutability
public final class GenerableStreamSession<T: Generable & Sendable & Decodable>: @unchecked Sendable {
    /// The language model to use
    private let model: OllamaLanguageModel

    /// Stream options
    private let options: GenerableStreamOptions

    /// Parser for the Generable type
    private let parser: GenerableParser<T>

    /// Full transcript including the latest prompt entry
    private let transcript: Transcript

    public init(
        model: OllamaLanguageModel,
        transcript: Transcript,
        options: GenerableStreamOptions = .default
    ) {
        self.model = model
        self.options = options
        self.parser = GenerableParser<T>()
        self.transcript = transcript
    }

    // MARK: - Public Streaming Methods

    /// Stream generation with automatic retry on failure
    /// - Returns: AsyncThrowingStream of GenerableStreamResult
    public func stream() -> AsyncThrowingStream<GenerableStreamResult<T>, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await self.executeStream(continuation: continuation)
            }
        }
    }

    /// Generate with retry (non-streaming, returns final result)
    /// - Returns: Generated value or throws error
    public func generate() async throws -> T {
        let retryController = RetryController<T>(policy: options.retryPolicy)

        while true {
            do {
                let (result, _) = try await executeGenerationWithContent(
                    retryController: retryController,
                    attempt: await retryController.currentAttempt
                )
                await retryController.recordSuccess()
                return result
            } catch let error as GenerationErrorWithContent {
                if await retryController.recordFailure(
                    error: error.underlyingError,
                    failedContent: error.content
                ) != nil {
                    let delay = await retryController.getRetryDelay()
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                } else {
                    throw await retryController.getFinalError()
                }
            } catch let error as GenerableError {
                if await retryController.recordFailure(
                    error: error,
                    failedContent: ""
                ) != nil {
                    let delay = await retryController.getRetryDelay()
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                } else {
                    throw await retryController.getFinalError()
                }
            } catch {
                throw GenerableError.unknown(error.localizedDescription)
            }
        }
    }

    /// Internal error type to carry content with error
    private struct GenerationErrorWithContent: Error {
        let underlyingError: GenerableError
        let content: String
    }

    // MARK: - Private Implementation

    /// Execute the streaming with retry logic
    private func executeStream(
        continuation: AsyncThrowingStream<GenerableStreamResult<T>, Error>.Continuation
    ) async {
        let retryController = RetryController<T>(policy: options.retryPolicy)

        var shouldContinue = true
        while shouldContinue {
            let canRetry = await retryController.canRetry
            let currentAttempt = await retryController.currentAttempt

            guard canRetry || currentAttempt == 1 else {
                shouldContinue = false
                break
            }

            let attempt = currentAttempt
            var accumulatedContent = ""
            var lastError: GenerableError?

            do {
                let transcript = await buildTranscript(
                    retryController: retryController,
                    attempt: attempt
                )

                let stream = model.stream(transcript: transcript, options: options.generationOptions)

                for try await entry in stream {
                    if case .response(let response) = entry {
                        for segment in response.segments {
                            if case .text(let textSegment) = segment {
                                accumulatedContent += textSegment.content

                                if options.yieldPartialValues &&
                                   accumulatedContent.count >= options.minContentForParse {
                                    let partialValue = parser.parsePartial(accumulatedContent)
                                    let partialState = PartialState<T>(
                                        accumulatedContent: accumulatedContent,
                                        partialValue: partialValue,
                                        isComplete: false,
                                        progress: nil
                                    )
                                    continuation.yield(.partial(partialState))
                                }
                            }
                        }
                    }
                }

                #if DEBUG
                print("[GenerableStreamSession] Accumulated content length: \(accumulatedContent.count)")
                print("[GenerableStreamSession] Content preview: \(String(accumulatedContent.prefix(500)))")
                if accumulatedContent.contains("<think>") {
                    print("[GenerableStreamSession] WARNING: Content contains <think> tag!")
                }
                #endif

                let parseResult = parser.parse(accumulatedContent)

                switch parseResult {
                case .success(let value):
                    await retryController.recordSuccess()
                    continuation.yield(.complete(value))
                    continuation.finish()
                    return

                case .failure(let parseError):
                    #if DEBUG
                    print("[GenerableStreamSession] Parse failed: \(parseError)")
                    print("[GenerableStreamSession] Full content for debugging:")
                    print("---START---")
                    print(accumulatedContent)
                    print("---END---")
                    #endif
                    lastError = parseError.toGenerableError()
                }
            } catch {
                lastError = mapError(error)
            }

            guard let error = lastError else {
                continuation.finish(throwing: GenerableError.unknown("Unknown error occurred"))
                return
            }

            if let retryContext = await retryController.recordFailure(
                error: error,
                failedContent: accumulatedContent
            ) {
                continuation.yield(.retrying(retryContext))

                let delay = await retryController.getRetryDelay()
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } else {
                let finalError = await retryController.getFinalError()
                continuation.yield(.failed(finalError))
                continuation.finish()
                return
            }
        }

        let finalError = await retryController.getFinalError()
        continuation.finish(throwing: finalError)
    }

    /// Execute a single generation attempt, returning both result and raw content
    private func executeGenerationWithContent(
        retryController: RetryController<T>,
        attempt: Int
    ) async throws -> (T, String) {
        let transcript = await buildTranscript(
            retryController: retryController,
            attempt: attempt
        )

        let response = try await model.generate(transcript: transcript, options: options.generationOptions)

        guard case .response(let resp) = response else {
            throw GenerableError.emptyResponse
        }

        var content = ""
        for segment in resp.segments {
            if case .text(let textSegment) = segment {
                content += textSegment.content
            }
        }

        guard !content.isEmpty else {
            throw GenerableError.emptyResponse
        }

        #if DEBUG
        print("[GenerableStreamSession.generate] Content length: \(content.count)")
        print("[GenerableStreamSession.generate] Content preview: \(String(content.prefix(500)))")
        if content.contains("<think>") {
            print("[GenerableStreamSession.generate] WARNING: Content contains <think> tag!")
        }
        #endif

        let parseResult = parser.parse(content)

        switch parseResult {
        case .success(let value):
            return (value, content)
        case .failure(let parseError):
            #if DEBUG
            print("[GenerableStreamSession.generate] Parse failed: \(parseError)")
            print("[GenerableStreamSession.generate] Full content:")
            print("---START---")
            print(content)
            print("---END---")
            #endif
            throw GenerationErrorWithContent(
                underlyingError: parseError.toGenerableError(),
                content: content
            )
        }
    }

    /// Build transcript for a given attempt.
    ///
    /// Applies the structured output response format to the last prompt entry,
    /// and on retry replaces that entry's text with a retry-augmented version.
    private func buildTranscript(
        retryController: RetryController<T>,
        attempt: Int
    ) async -> Transcript {
        var entries = transcript._entries

        // Find the last prompt entry to apply responseFormat and optional retry context
        guard let lastIndex = entries.indices.reversed().first(where: {
            if case .prompt = entries[$0] { return true }
            return false
        }), case .prompt(var lastPrompt) = entries[lastIndex] else {
            return transcript
        }

        if attempt > 1, let context = await retryController.getLastRetryContext() {
            // Extract original text for retry base
            let originalText = lastPrompt.segments.compactMap { segment -> String? in
                if case .text(let t) = segment { return t.content }
                return nil
            }.joined(separator: " ")

            let retryText = await retryController.buildRetryPrompt(
                originalPrompt: originalText,
                context: context
            )
            lastPrompt.segments = [.text(Transcript.TextSegment(content: retryText))]
        }

        // Apply structured output response format
        lastPrompt.responseFormat = Transcript.ResponseFormat(type: T.self)
        if let generationOptions = options.generationOptions {
            lastPrompt.options = generationOptions
        }

        entries[lastIndex] = .prompt(lastPrompt)
        return Transcript(entries: entries)
    }

    /// Map errors to GenerableError
    private func mapError(_ error: Error) -> GenerableError {
        if let ollamaError = error as? OllamaHTTPError {
            switch ollamaError {
            case .connectionError(let message):
                return .connectionError(message)
            case .invalidResponse:
                return .streamInterrupted("Invalid response")
            case .statusError(let code, _):
                return .connectionError("HTTP \(code)")
            case .networkError(let underlyingError):
                return .connectionError(underlyingError.localizedDescription)
            case .decodingError(let underlyingError):
                return .jsonParsingFailed("", underlyingError: underlyingError.localizedDescription)
            }
        }

        if let generableError = error as? GenerableError {
            return generableError
        }

        return .unknown(error.localizedDescription)
    }
}

// MARK: - Convenience Extension for OllamaLanguageModel

extension OllamaLanguageModel {
    /// Create a Generable streaming session.
    ///
    /// The transcript must already contain the latest prompt entry.
    public func streamGenerable<T: Generable & Sendable & Decodable>(
        transcript: Transcript,
        generating type: T.Type,
        options: GenerableStreamOptions = .default
    ) -> GenerableStreamSession<T> {
        GenerableStreamSession<T>(model: self, transcript: transcript, options: options)
    }

    /// Generate a Generable type with retry.
    ///
    /// The transcript must already contain the latest prompt entry.
    public func generateWithRetry<T: Generable & Sendable & Decodable>(
        transcript: Transcript,
        generating type: T.Type,
        options: GenerableStreamOptions = .default
    ) async throws -> T {
        let session = GenerableStreamSession<T>(model: self, transcript: transcript, options: options)
        return try await session.generate()
    }

    /// Stream Generable generation with retry.
    ///
    /// The transcript must already contain the latest prompt entry.
    public func streamWithRetry<T: Generable & Sendable & Decodable>(
        transcript: Transcript,
        generating type: T.Type,
        options: GenerableStreamOptions = .default
    ) -> AsyncThrowingStream<GenerableStreamResult<T>, Error> {
        let session = GenerableStreamSession<T>(model: self, transcript: transcript, options: options)
        return session.stream()
    }
}

#endif
