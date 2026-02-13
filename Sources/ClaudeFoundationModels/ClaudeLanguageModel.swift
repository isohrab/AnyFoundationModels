#if CLAUDE_ENABLED
import Foundation
import OpenFoundationModels

/// Claude Language Model Provider for OpenFoundationModels
public final class ClaudeLanguageModel: LanguageModel, Sendable {

    // MARK: - Properties
    internal let httpClient: ClaudeHTTPClient
    internal let modelName: String
    internal let configuration: ClaudeConfiguration

    /// Default max tokens for text output (excluding thinking budget)
    public let defaultMaxTokens: Int

    /// Extended thinking budget in tokens.
    /// When set, enables extended thinking for all requests from this model instance.
    ///
    /// Constraints enforced by the Claude API:
    /// - Minimum: 1024 tokens
    /// - Must be less than `max_tokens` sent in the request
    /// - Incompatible with `temperature` and `top_k` (they will be omitted)
    /// - Only `tool_choice: auto` or `none` is allowed (not `any` or specific tool)
    public let thinkingBudgetTokens: Int?

    /// Manages pending thinking blocks for tool-use conversations with extended thinking.
    private let thinkingBlockManager = ThinkingBlockManager()

    // MARK: - LanguageModel Protocol Compliance
    public var isAvailable: Bool { true }

    // MARK: - Initialization

    /// Initialize with configuration and model name
    /// - Parameters:
    ///   - configuration: Claude configuration
    ///   - modelName: Name of the model (e.g., "claude-sonnet-4-20250514", "claude-3-5-haiku-20241022")
    ///   - defaultMaxTokens: Default max tokens for text output (default: 4096)
    ///   - thinkingBudgetTokens: Extended thinking budget. nil disables thinking. Minimum 1024.
    public init(
        configuration: ClaudeConfiguration,
        modelName: String,
        defaultMaxTokens: Int = 4096,
        thinkingBudgetTokens: Int? = nil
    ) {
        self.configuration = configuration
        self.modelName = modelName
        self.defaultMaxTokens = defaultMaxTokens
        self.thinkingBudgetTokens = thinkingBudgetTokens
        self.httpClient = ClaudeHTTPClient(configuration: configuration)
    }

    // MARK: - LanguageModel Protocol Implementation

    public func generate(transcript: Transcript, options: GenerationOptions?) async throws -> Transcript.Entry {
        let buildResult = try RequestBuilder.build(
            transcript: transcript,
            options: options,
            modelName: modelName,
            defaultMaxTokens: defaultMaxTokens,
            thinkingBudgetTokens: thinkingBudgetTokens,
            pendingThinkingBlocks: thinkingBlockManager.take(),
            stream: false
        )

        let response: MessagesResponse = try await httpClient.send(
            buildResult.request,
            to: "/v1/messages",
            betaHeaders: buildResult.betaHeaders
        )

        // Check for tool calls
        let toolUseBlocks = response.content.compactMap { block -> ToolUseBlock? in
            if case .toolUse(let toolUse) = block {
                return toolUse
            }
            return nil
        }

        if !toolUseBlocks.isEmpty {
            // Store thinking blocks for the next request in the tool use loop
            thinkingBlockManager.store(from: response.content)
            return ResponseConverter.createToolCallsEntry(from: toolUseBlocks)
        }

        // Convert response to Transcript.Entry
        // Use schema-aware parsing if response format was specified
        if let schema = buildResult.responseSchema {
            return ResponseConverter.createResponseEntry(from: response, schema: schema)
        }
        return ResponseConverter.createResponseEntry(from: response)
    }

    public func stream(transcript: Transcript, options: GenerationOptions?) -> AsyncThrowingStream<Transcript.Entry, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let buildResult = try RequestBuilder.build(
                        transcript: transcript,
                        options: options,
                        modelName: self.modelName,
                        defaultMaxTokens: self.defaultMaxTokens,
                        thinkingBudgetTokens: self.thinkingBudgetTokens,
                        pendingThinkingBlocks: self.thinkingBlockManager.take(),
                        stream: true
                    )

                    let streamResponse = await self.httpClient.stream(
                        buildResult.request,
                        to: "/v1/messages",
                        betaHeaders: buildResult.betaHeaders
                    )

                    var accumulatedText = ""
                    var accumulatedToolCalls: [(id: String, name: String, input: String)] = []
                    var currentToolCallIndex: Int? = nil
                    var hasYieldedContent = false

                    // Accumulate thinking blocks for tool use conversations
                    var accumulatedThinkingText = ""
                    var accumulatedSignature = ""
                    var isInThinkingBlock = false
                    var streamThinkingBlocks: [ResponseContentBlock] = []

                    for try await event in streamResponse {
                        switch event {
                        case .messageStart:
                            break

                        case .contentBlockStart(let startEvent):
                            switch startEvent.contentBlock {
                            case .text:
                                break
                            case .toolUse(let toolUseStart):
                                currentToolCallIndex = accumulatedToolCalls.count
                                accumulatedToolCalls.append((
                                    id: toolUseStart.id,
                                    name: toolUseStart.name,
                                    input: ""
                                ))
                            case .thinking:
                                isInThinkingBlock = true
                                accumulatedThinkingText = ""
                                accumulatedSignature = ""
                            }

                        case .contentBlockDelta(let deltaEvent):
                            switch deltaEvent.delta {
                            case .textDelta(let textDelta):
                                accumulatedText += textDelta.text
                                // Yield accumulated content for structured output support
                                let entry = ResponseConverter.createTextResponseEntry(content: accumulatedText)
                                continuation.yield(entry)
                                hasYieldedContent = true

                            case .inputJSONDelta(let jsonDelta):
                                if let index = currentToolCallIndex {
                                    accumulatedToolCalls[index].input += jsonDelta.partialJson
                                }

                            case .thinkingDelta(let thinkingDelta):
                                accumulatedThinkingText += thinkingDelta.thinking

                            case .signatureDelta(let signatureDelta):
                                accumulatedSignature += signatureDelta.signature
                            }

                        case .contentBlockStop:
                            if isInThinkingBlock {
                                let thinkingBlock = ThinkingBlock(
                                    thinking: accumulatedThinkingText,
                                    signature: accumulatedSignature.isEmpty ? nil : accumulatedSignature
                                )
                                streamThinkingBlocks.append(.thinking(thinkingBlock))
                                isInThinkingBlock = false
                            }
                            currentToolCallIndex = nil

                        case .messageDelta:
                            break

                        case .messageStop:
                            // If we accumulated tool calls, store thinking blocks and yield
                            if !accumulatedToolCalls.isEmpty {
                                if !streamThinkingBlocks.isEmpty {
                                    self.thinkingBlockManager.store(streamThinkingBlocks)
                                }
                                let entry = ResponseConverter.createToolCallsEntry(from: accumulatedToolCalls)
                                continuation.yield(entry)
                            }

                            // Yield final content with schema-aware parsing if available
                            if !accumulatedText.isEmpty && accumulatedToolCalls.isEmpty {
                                if let schema = buildResult.responseSchema,
                                   let entry = ResponseConverter.createResponseEntry(fromText: accumulatedText, schema: schema) {
                                    continuation.yield(entry)
                                }
                            }

                            // Handle empty response case
                            if !hasYieldedContent && accumulatedToolCalls.isEmpty {
                                let entry = ResponseConverter.createTextResponseEntry(content: "")
                                continuation.yield(entry)
                            }

                            continuation.finish()
                            return

                        case .error(let errorEvent):
                            throw ClaudeHTTPError.statusError(
                                500,
                                errorEvent.error.message.data(using: .utf8)
                            )

                        case .ping:
                            break
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func supports(locale: Locale) -> Bool {
        // Claude models support multiple languages
        return true
    }

}

// MARK: - Convenience Model Constants

extension ClaudeLanguageModel {
    // MARK: - Model Identifiers (Current)

    /// Claude Opus 4.6 - Most intelligent model for building agents and coding
    public static let opus4_6 = "claude-opus-4-6"

    /// Claude Sonnet 4.5 - Best combination of speed and intelligence
    public static let sonnet4_5 = "claude-sonnet-4-5-20250929"

    /// Claude Haiku 4.5 - Fastest model with near-frontier intelligence
    public static let haiku4_5 = "claude-haiku-4-5-20251001"

    // MARK: - Model Identifiers (Legacy)

    /// Claude Opus 4.5 - Premium model combining maximum intelligence with practical performance (legacy)
    public static let opus4_5 = "claude-opus-4-5-20251101"

    /// Claude Opus 4.1 - High-capability model (legacy)
    public static let opus4_1 = "claude-opus-4-1-20250805"

    /// Claude Sonnet 4 - High-performance model with extended thinking (legacy)
    public static let sonnet4 = "claude-sonnet-4-20250514"

    /// Claude Opus 4 - Capable model (legacy)
    public static let opus4 = "claude-opus-4-20250514"

    /// Claude 3.7 Sonnet - High-performance model with early extended thinking (legacy)
    public static let sonnet3_7 = "claude-3-7-sonnet-20250219"

    /// Claude 3.5 Haiku - Fastest and most compact model for near-instant responsiveness (legacy)
    public static let haiku3_5 = "claude-3-5-haiku-20241022"

    /// Claude 3.5 Sonnet model identifier (legacy)
    public static let sonnet3_5 = "claude-3-5-sonnet-20241022"

    // MARK: - Factory Methods (Current)

    /// Create Claude Opus 4.6 model
    public static func opus4_6(configuration: ClaudeConfiguration, defaultMaxTokens: Int = 4096, thinkingBudgetTokens: Int? = nil) -> ClaudeLanguageModel {
        return ClaudeLanguageModel(configuration: configuration, modelName: opus4_6, defaultMaxTokens: defaultMaxTokens, thinkingBudgetTokens: thinkingBudgetTokens)
    }

    /// Create Claude Sonnet 4.5 model
    public static func sonnet4_5(configuration: ClaudeConfiguration, defaultMaxTokens: Int = 4096, thinkingBudgetTokens: Int? = nil) -> ClaudeLanguageModel {
        return ClaudeLanguageModel(configuration: configuration, modelName: sonnet4_5, defaultMaxTokens: defaultMaxTokens, thinkingBudgetTokens: thinkingBudgetTokens)
    }

    /// Create Claude Haiku 4.5 model
    public static func haiku4_5(configuration: ClaudeConfiguration, defaultMaxTokens: Int = 4096, thinkingBudgetTokens: Int? = nil) -> ClaudeLanguageModel {
        return ClaudeLanguageModel(configuration: configuration, modelName: haiku4_5, defaultMaxTokens: defaultMaxTokens, thinkingBudgetTokens: thinkingBudgetTokens)
    }

    // MARK: - Factory Methods (Legacy)

    /// Create Claude Opus 4.5 model (legacy)
    public static func opus4_5(configuration: ClaudeConfiguration, defaultMaxTokens: Int = 4096, thinkingBudgetTokens: Int? = nil) -> ClaudeLanguageModel {
        return ClaudeLanguageModel(configuration: configuration, modelName: opus4_5, defaultMaxTokens: defaultMaxTokens, thinkingBudgetTokens: thinkingBudgetTokens)
    }

    /// Create Claude Opus 4.1 model (legacy)
    public static func opus4_1(configuration: ClaudeConfiguration, defaultMaxTokens: Int = 4096, thinkingBudgetTokens: Int? = nil) -> ClaudeLanguageModel {
        return ClaudeLanguageModel(configuration: configuration, modelName: opus4_1, defaultMaxTokens: defaultMaxTokens, thinkingBudgetTokens: thinkingBudgetTokens)
    }

    /// Create Claude Sonnet 4 model (legacy)
    public static func sonnet4(configuration: ClaudeConfiguration, defaultMaxTokens: Int = 4096, thinkingBudgetTokens: Int? = nil) -> ClaudeLanguageModel {
        return ClaudeLanguageModel(configuration: configuration, modelName: sonnet4, defaultMaxTokens: defaultMaxTokens, thinkingBudgetTokens: thinkingBudgetTokens)
    }

    /// Create Claude Opus 4 model (legacy)
    public static func opus4(configuration: ClaudeConfiguration, defaultMaxTokens: Int = 4096, thinkingBudgetTokens: Int? = nil) -> ClaudeLanguageModel {
        return ClaudeLanguageModel(configuration: configuration, modelName: opus4, defaultMaxTokens: defaultMaxTokens, thinkingBudgetTokens: thinkingBudgetTokens)
    }

    /// Create Claude 3.7 Sonnet model (legacy)
    public static func sonnet3_7(configuration: ClaudeConfiguration, defaultMaxTokens: Int = 4096, thinkingBudgetTokens: Int? = nil) -> ClaudeLanguageModel {
        return ClaudeLanguageModel(configuration: configuration, modelName: sonnet3_7, defaultMaxTokens: defaultMaxTokens, thinkingBudgetTokens: thinkingBudgetTokens)
    }

    /// Create Claude 3.5 Haiku model (legacy)
    public static func haiku3_5(configuration: ClaudeConfiguration, defaultMaxTokens: Int = 4096, thinkingBudgetTokens: Int? = nil) -> ClaudeLanguageModel {
        return ClaudeLanguageModel(configuration: configuration, modelName: haiku3_5, defaultMaxTokens: defaultMaxTokens, thinkingBudgetTokens: thinkingBudgetTokens)
    }

    /// Create Claude 3.5 Sonnet model (legacy)
    public static func sonnet3_5(configuration: ClaudeConfiguration, defaultMaxTokens: Int = 4096, thinkingBudgetTokens: Int? = nil) -> ClaudeLanguageModel {
        return ClaudeLanguageModel(configuration: configuration, modelName: sonnet3_5, defaultMaxTokens: defaultMaxTokens, thinkingBudgetTokens: thinkingBudgetTokens)
    }
}

#endif
