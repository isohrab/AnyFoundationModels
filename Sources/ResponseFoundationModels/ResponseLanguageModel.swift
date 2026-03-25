#if RESPONSE_ENABLED
import Foundation
import OpenFoundationModels

/// Language model provider using the OpenAI Responses API (POST /v1/responses)
public final class ResponseLanguageModel: LanguageModel, @unchecked Sendable {

    private let httpClient: ResponseHTTPClient
    private let modelName: String
    private let configuration: ResponseConfiguration
    private let requestBuilder: ResponseRequestBuilder
    
    /// Reasoning configuration for reasoning models (gpt-5 and o-series).
    /// When set, enables reasoning for all requests from this model instance.
    public let reasoning: Reasoning?

    // MARK: - LanguageModel Protocol

    public var isAvailable: Bool { true }

    // MARK: - Initialization

    /// Initialize with configuration and model name
    /// - Parameters:
    ///   - configuration: API configuration (base URL, API key, timeout)
    ///   - model: Model identifier (e.g. "gpt-4.1", "o4-mini", "gpt-5")
    ///   - reasoning: Reasoning configuration for gpt-5 and o-series models (optional)
    public init(configuration: ResponseConfiguration, model: String, reasoning: Reasoning? = nil) {
        self.configuration = configuration
        self.modelName = model
        self.reasoning = reasoning
        self.httpClient = ResponseHTTPClient(configuration: configuration)
        self.requestBuilder = ResponseRequestBuilder(modelName: model, reasoning: reasoning)
    }

    // MARK: - Generate

    public func generate(
        transcript: Transcript,
        options: GenerationOptions?
    ) async throws -> Transcript.Entry {
        let buildResult = requestBuilder.build(transcript: transcript, options: options, stream: false)
        let response = try await httpClient.send(buildResult.request)
        return ResponseConverter.convert(response)
    }

    // MARK: - Stream

    public func stream(
        transcript: Transcript,
        options: GenerationOptions?
    ) -> AsyncThrowingStream<Transcript.Entry, Error> {
        let buildResult = requestBuilder.build(transcript: transcript, options: options, stream: true)
        let request = buildResult.request
        let client = self.httpClient

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let eventStream = try await client.stream(request)
                    var state = StreamingHandler.StreamState()

                    for try await event in eventStream {
                        try Task.checkCancellation()
                        if let entry = StreamingHandler.processEvent(event, state: &state) {
                            continuation.yield(entry)
                        }

                        if state.isComplete {
                            break
                        }
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Locale Support

    public func supports(locale: Locale) -> Bool { true }

}

// MARK: - Convenience Initializers

extension ResponseLanguageModel {

    /// Initialize with API key and model name, using default OpenAI base URL
    public convenience init(apiKey: String, model: String) {
        let config = ResponseConfiguration(apiKey: apiKey)
        self.init(configuration: config, model: model)
    }
}

#endif
