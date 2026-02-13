#if RESPONSE_ENABLED
import Foundation
import OpenFoundationModels

/// Language model provider using the OpenAI Responses API (POST /v1/responses)
public final class ResponseLanguageModel: LanguageModel, @unchecked Sendable {

    private let httpClient: ResponseHTTPClient
    private let modelName: String
    private let configuration: ResponseConfiguration

    // MARK: - LanguageModel Protocol

    public var isAvailable: Bool { true }

    // MARK: - Initialization

    /// Initialize with configuration and model name
    /// - Parameters:
    ///   - configuration: API configuration (base URL, API key, timeout)
    ///   - model: Model identifier (e.g. "gpt-4.1", "o4-mini")
    public init(configuration: ResponseConfiguration, model: String) {
        self.configuration = configuration
        self.modelName = model
        self.httpClient = ResponseHTTPClient(configuration: configuration)
    }

    // MARK: - Generate

    public func generate(
        transcript: Transcript,
        options: GenerationOptions?
    ) async throws -> Transcript.Entry {
        let request = buildRequest(from: transcript, options: options, stream: false)
        let response = try await httpClient.send(request)
        return ResponseConverter.convert(response)
    }

    // MARK: - Stream

    public func stream(
        transcript: Transcript,
        options: GenerationOptions?
    ) -> AsyncThrowingStream<Transcript.Entry, Error> {
        let request = buildRequest(from: transcript, options: options, stream: true)
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

    // MARK: - Private

    private func buildRequest(
        from transcript: Transcript,
        options: GenerationOptions?,
        stream: Bool
    ) -> ResponsesRequest {
        let inputItems = TranscriptConverter.buildInputItems(from: transcript)
        let tools = TranscriptConverter.extractToolDefinitions(from: transcript)
        let textFormat = TranscriptConverter.extractResponseFormat(from: transcript)
        let resolvedOptions = options ?? TranscriptConverter.extractOptions(from: transcript)

        // Extract instructions from the first system message if present
        var instructions: String?
        var filteredItems = inputItems
        if let first = inputItems.first,
           case .message(let msg) = first, msg.role == "system" {
            instructions = msg.content
            filteredItems = Array(inputItems.dropFirst())
        }

        var request = ResponsesRequest(
            model: modelName,
            input: filteredItems,
            instructions: instructions,
            tools: tools,
            stream: stream
        )

        // Apply generation options
        if let opts = resolvedOptions {
            request.maxOutputTokens = opts.maximumResponseTokens
            if let temperature = opts.temperature {
                request.temperature = temperature
            }
        }

        // Apply text format
        if let format = textFormat {
            request.text = format
        }

        return request
    }
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
