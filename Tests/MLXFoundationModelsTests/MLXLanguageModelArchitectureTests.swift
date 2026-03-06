#if MLX_ENABLED
import Foundation
import OpenFoundationModels
import OpenFoundationModelsCore
import MLXLMCommon
import Testing
@testable import MLXFoundationModels

@Suite("MLXLanguageModel Architecture Tests")
struct MLXLanguageModelArchitectureTests {
    private let planner = MLXTranscriptPlanner()
    private let tuner = MLXGenerationTuner()
    private let assembler = MLXResponseAssembler()

    @Test("Planner omits tools for plain conversational turns")
    func plannerOmitsToolsForPlainConversation() throws {
        let transcript = Transcript(entries: [
            .instructions(.init(segments: [.text(.init(content: "You are helpful."))], toolDefinitions: [searchToolDefinition()])),
            .prompt(.init(segments: [.text(.init(content: "こんにちは"))])),
        ])

        let plan = try planner.plan(
            transcript: transcript,
            options: nil,
            metadata: denseSmallMetadata()
        )

        #expect(plan.toolPolicy == .disabled)
        #expect(plan.responseMode == .text)
        #expect(plan.plannerDiagnostics.toolDefinitionCount == 0)
        #expect(plan.cachePlan.reuseScope == .prefixReusable)
    }

    @Test("Planner requires tools when continuing an unresolved tool loop")
    func plannerRequiresToolsForPendingToolLoop() throws {
        let callArguments = try GeneratedContent(json: #"{"query":"TODO"}"#)
        let transcript = Transcript(entries: [
            .instructions(.init(segments: [.text(.init(content: "Use tools when needed."))], toolDefinitions: [searchToolDefinition()])),
            .prompt(.init(segments: [.text(.init(content: "Search the repository for TODOs"))])),
            .toolCalls(.init([
                Transcript.ToolCall(
                    id: "call-1",
                    toolName: "search_repo",
                    arguments: callArguments
                )
            ])),
        ])

        let plan = try planner.plan(
            transcript: transcript,
            options: nil,
            metadata: denseMidMetadata()
        )

        #expect(plan.toolPolicy == .required)
        #expect(plan.responseMode == .toolCapable)
        #expect(plan.plannerDiagnostics.toolDefinitionCount == 1)
    }

    @Test("Planner cache key changes when schema changes")
    func plannerCacheKeyChangesWhenSchemaChanges() throws {
        let baseEntries: [Transcript.Entry] = [
            .instructions(.init(segments: [.text(.init(content: "Return structured data."))], toolDefinitions: [])),
        ]

        let stringTranscript = Transcript(entries: baseEntries + [
            .prompt(
                .init(
                    segments: [.text(.init(content: "Summarize this"))],
                    responseFormat: .init(schema: GenerationSchema(type: String.self, description: "A summary", properties: []))
                )
            ),
        ])

        let intTranscript = Transcript(entries: baseEntries + [
            .prompt(
                .init(
                    segments: [.text(.init(content: "Summarize this"))],
                    responseFormat: .init(schema: GenerationSchema(type: Int.self, description: "A count", properties: []))
                )
            ),
        ])

        let metadata = denseMidMetadata()
        let stringPlan = try planner.plan(transcript: stringTranscript, options: nil, metadata: metadata)
        let intPlan = try planner.plan(transcript: intTranscript, options: nil, metadata: metadata)

        #expect(stringPlan.cachePlan.cacheKey != nil)
        #expect(intPlan.cachePlan.cacheKey != nil)
        #expect(stringPlan.cachePlan.cacheKey != intPlan.cachePlan.cacheKey)
        #expect(stringPlan.schemaFingerprint != intPlan.schemaFingerprint)
    }

    @Test("Tuner applies prompt length thresholds and VLM cap")
    func tunerAppliesPromptLengthThresholds() {
        let plan = makePlan(responseMode: .text, toolPolicy: .disabled)

        let shortProfile = tuner.makeProfile(
            plan: plan,
            metadata: denseMidMetadata(),
            promptTokenCount: 1024
        )
        #expect(shortProfile.prefillStepSize == 512)
        #expect(shortProfile.kvBits == nil)
        #expect(shortProfile.maxKVSize == nil)

        let midProfile = tuner.makeProfile(
            plan: plan,
            metadata: denseMidMetadata(),
            promptTokenCount: 4096
        )
        #expect(midProfile.prefillStepSize == 1024)
        #expect(midProfile.kvBits == nil)

        let longProfile = tuner.makeProfile(
            plan: plan,
            metadata: denseMidMetadata(),
            promptTokenCount: 9000
        )
        #expect(longProfile.prefillStepSize == 1536)
        #expect(longProfile.kvBits == 4)
        #expect(longProfile.quantizedKVStart == 4096)

        let vlmProfile = tuner.makeProfile(
            plan: plan,
            metadata: vlmMetadata(),
            promptTokenCount: 9000
        )
        #expect(vlmProfile.prefillStepSize == 1024)
        #expect(vlmProfile.kvBits == 4)
    }

    @Test("Assembler strips think blocks from final text responses")
    func assemblerStripsThinkBlocks() throws {
        let entry = try assembler.finalEntry(
            plan: makePlan(responseMode: .text, toolPolicy: .disabled),
            events: [
                .textChunk("<think>secret reasoning</think>\nHello"),
                .textChunk("</think>\nWorld"),
                .completed,
            ]
        )

        #expect(extractText(from: entry) == "Hello\nWorld")
    }

    @Test("Assembler prefers native tool calls over textual fallback")
    func assemblerPrefersNativeToolCalls() throws {
        let entry = try assembler.finalEntry(
            plan: makePlan(responseMode: .toolCapable, toolPolicy: .enabled),
            events: [
                .textChunk(#"{"tool_calls":[{"name":"search_repo","arguments":{"query":"fallback"}}]}"#),
                .nativeToolCall(name: "search_repo", argsJSON: #"{"query":"native"}"#),
                .completed,
            ]
        )

        guard case .toolCalls(let calls) = entry else {
            Issue.record("Expected tool calls entry")
            return
        }

        #expect(calls.count == 1)
        #expect(calls.first?.toolName == "search_repo")
        let query: String? = try calls.first?.arguments.value(String.self, forProperty: "query")
        #expect(query == "native")
    }

    @Test("Assembler falls back to textual tool call detection")
    func assemblerFallsBackToTextualToolCallDetection() throws {
        let entry = try assembler.finalEntry(
            plan: makePlan(responseMode: .toolCapable, toolPolicy: .enabled),
            events: [
                .textChunk(#"{"tool_calls":[{"name":"search_repo","arguments":{"query":"swift"}}]}"#),
                .completed,
            ]
        )

        guard case .toolCalls(let calls) = entry else {
            Issue.record("Expected textual tool call detection")
            return
        }

        #expect(calls.count == 1)
        let query: String? = try calls.first?.arguments.value(String.self, forProperty: "query")
        #expect(query == "swift")
    }

    @Test("Streaming sanitizer never emits think content")
    func streamingSanitizerSuppressesThinkBlocks() {
        var state = MLXStreamingResponseState()
        let firstResult = assembler.streamDelta(state: state, chunk: "<think>secret")
        state = firstResult.state
        let secondResult = assembler.streamDelta(state: state, chunk: "</think>Hello")

        #expect(firstResult.delta.isEmpty)
        #expect(secondResult.delta == "Hello")
        #expect(!secondResult.state.emittedVisibleText.contains("secret"))
    }
}

private func makePlan(
    responseMode: MLXResponseMode,
    toolPolicy: MLXToolPolicy
) -> MLXExecutionPlan {
    let tools: [[String: any Sendable]]? = toolPolicy == .disabled ? nil : [[
        "type": "function" as any Sendable,
        "function": [
            "name": "search_repo" as any Sendable,
            "description": "Search files" as any Sendable,
        ] as any Sendable,
    ]]

    return MLXExecutionPlan(
        input: UserInput(
            chat: [
                .system("You are helpful."),
                .user("Hello"),
            ],
            tools: tools,
            additionalContext: [:]
        ),
        responseMode: responseMode,
        toolPolicy: toolPolicy,
        cachePlan: MLXCachePlan(
            reuseScope: .prefixReusable,
            cacheKey: MLXPrefixCacheKey(rawValue: "cache-key"),
            prefixMessages: [.system("You are helpful.")],
            suffixMessages: [.user("Hello")],
            prefixInput: UserInput(chat: [.system("You are helpful.")], tools: tools, additionalContext: [:])
        ),
        promptTokenEstimate: nil,
        schemaFingerprint: nil,
        additionalContext: [:],
        plannerDiagnostics: .init(
            systemMessageCount: 1,
            userMessageCount: 1,
            assistantMessageCount: 0,
            toolMessageCount: 0,
            imageCount: 0,
            toolDefinitionCount: tools?.count ?? 0
        )
    )
}

private func denseSmallMetadata() -> MLXModelMetadata {
    MLXModelMetadata(
        modelID: "mlx-community/Qwen3.5-4B",
        runtimeFamily: .llm,
        modalityFamily: .text,
        qwen35Variant: nil
    )
}

private func denseMidMetadata() -> MLXModelMetadata {
    MLXModelMetadata(
        modelID: "mlx-community/Qwen3.5-9B",
        runtimeFamily: .llm,
        modalityFamily: .text,
        qwen35Variant: nil
    )
}

private func vlmMetadata() -> MLXModelMetadata {
    MLXModelMetadata(
        modelID: "mlx-community/Qwen3.5-4B-MLX-4bit",
        runtimeFamily: .vlm,
        modalityFamily: .conditionalGeneration,
        qwen35Variant: nil
    )
}

private func searchToolDefinition() -> Transcript.ToolDefinition {
    Transcript.ToolDefinition(
        name: "search_repo",
        description: "Search the repository",
        parameters: GenerationSchema(type: String.self, description: "Search query", properties: [])
    )
}

private func extractText(from entry: Transcript.Entry) -> String? {
    guard case .response(let response) = entry else {
        return nil
    }
    guard response.segments.count == 1 else {
        return nil
    }
    guard case .text(let text) = response.segments[0] else {
        return nil
    }
    return text.content
}

#endif
