#if CLAUDE_ENABLED
import Foundation
import OpenFoundationModels

/// Builds MessagesRequest from Transcript, eliminating duplication between generate() and stream().
internal struct RequestBuilder {

    /// Result of building a request, containing all data needed to send and process the response.
    struct BuildResult: Sendable {
        let request: MessagesRequest
        let betaHeaders: [String]?
        let responseSchema: GenerationSchema?
    }

    /// Build a MessagesRequest from the given transcript and model parameters.
    /// - Parameters:
    ///   - transcript: The conversation transcript
    ///   - options: Generation options (overrides transcript-embedded options if provided)
    ///   - modelName: Claude model identifier
    ///   - defaultMaxTokens: Default max tokens for text output
    ///   - thinkingBudgetTokens: Extended thinking budget (nil = disabled)
    ///   - pendingThinkingBlocks: Thinking blocks to inject from previous tool-use turn
    ///   - stream: Whether this is a streaming request
    static func build(
        transcript: Transcript,
        options: GenerationOptions?,
        modelName: String,
        defaultMaxTokens: Int,
        thinkingBudgetTokens: Int?,
        pendingThinkingBlocks: [ResponseContentBlock],
        stream: Bool
    ) throws -> BuildResult {
        // Convert Transcript to Claude format
        var (messages, systemPrompt) = TranscriptConverter.buildMessages(from: transcript)
        let tools = try TranscriptConverter.extractTools(from: transcript)

        // Inject pending thinking blocks into the last assistant message
        if !pendingThinkingBlocks.isEmpty {
            messages = ThinkingBlockManager.inject(pendingThinkingBlocks, into: messages)
        }

        // Resolve generation options
        let finalOptions = options ?? TranscriptConverter.extractOptions(from: transcript)
        let claudeOptions = finalOptions?.toClaudeOptions() ?? ClaudeOptions(temperature: nil, topK: nil, topP: nil)

        // Resolve thinking, maxTokens, and temperature based on thinking mode
        let (thinking, maxTokens, temperature, topK) = resolveThinkingParameters(
            claudeOptions: claudeOptions,
            requestedMaxTokens: finalOptions?.maximumResponseTokens,
            defaultMaxTokens: defaultMaxTokens,
            thinkingBudgetTokens: thinkingBudgetTokens
        )

        // Check for response format (structured output)
        let responseSchema = TranscriptConverter.extractResponseFormat(from: transcript)

        // Convert GenerationSchema to Claude OutputFormat if present
        let outputFormat = try responseSchema.map { try OutputFormat(schema: $0) }
        let betaHeaders: [String]? = outputFormat != nil ? ["structured-outputs-2025-11-13"] : nil

        // Build request
        let request = MessagesRequest(
            model: modelName,
            messages: messages,
            maxTokens: maxTokens,
            system: systemPrompt,
            tools: tools,
            toolChoice: tools != nil ? .auto() : nil,
            stream: stream,
            temperature: temperature,
            topK: topK,
            topP: claudeOptions.topP,
            thinking: thinking,
            outputFormat: outputFormat
        )

        return BuildResult(
            request: request,
            betaHeaders: betaHeaders,
            responseSchema: responseSchema
        )
    }

    // MARK: - Thinking Parameter Resolution

    /// Resolve thinking configuration and adjust maxTokens, temperature, topK
    /// per Claude API constraints.
    private static func resolveThinkingParameters(
        claudeOptions: ClaudeOptions,
        requestedMaxTokens: Int?,
        defaultMaxTokens: Int,
        thinkingBudgetTokens: Int?
    ) -> (ThinkingConfig?, Int, Double?, Int?) {
        guard let budget = thinkingBudgetTokens else {
            let maxTokens = requestedMaxTokens ?? defaultMaxTokens
            return (nil, maxTokens, claudeOptions.temperature, claudeOptions.topK)
        }

        let textTokens = requestedMaxTokens ?? defaultMaxTokens
        let maxTokens = budget + textTokens

        return (.enabled(budgetTokens: budget), maxTokens, nil, nil)
    }
}

// MARK: - Claude Options

internal struct ClaudeOptions: Sendable {
    let temperature: Double?
    let topK: Int?
    let topP: Double?
}

// MARK: - GenerationOptions Extension

internal extension GenerationOptions {
    func toClaudeOptions() -> ClaudeOptions {
        return ClaudeOptions(
            temperature: temperature,
            topK: nil,
            topP: nil
        )
    }
}

#endif
