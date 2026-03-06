#if MLX_ENABLED
import Foundation
import OpenFoundationModels
@preconcurrency import MLXLMCommon

actor MLXLanguageModelRuntime {
    private let modelContainer: ModelContainer
    private let planner = MLXTranscriptPlanner()
    private let tuner = MLXGenerationTuner()
    private let executor = MLXExecutor()
    private let assembler = MLXResponseAssembler()

    private var metadata: MLXModelMetadata?
    private var tuningProfile: MLXGenerationProfile?
    private var prefixCacheStore = MLXPrefixCacheStore()
    private var lastDiagnostics: MLXRunDiagnostics?

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func generate(
        transcript: Transcript,
        options: GenerationOptions?
    ) async throws -> Transcript.Entry {
        let result = try await execute(transcript: transcript, options: options)
        let entry = try assembler.finalEntry(plan: result.plan, events: result.events)

        if shouldWarmPrefixCache(for: entry, toolPolicy: result.plan.toolPolicy) {
            let nextTranscript = Transcript(entries: Array(transcript) + [entry])
            Task {
                await self.warmPrefixCache(transcript: nextTranscript, options: options)
            }
        }

        return entry
    }

    func stream(
        transcript: Transcript,
        options: GenerationOptions?
    ) -> AsyncThrowingStream<Transcript.Entry, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let metadata = await self.resolveMetadata()
                    let plan = try self.planner.plan(transcript: transcript, options: options, metadata: metadata)
                    let reuseDecision = self.prefixCacheStore.lookup(plan: plan, metadata: metadata)

                    let preparation = try await self.executor.prepareExecution(
                        container: self.modelContainer,
                        plan: plan,
                        reuseDecision: reuseDecision
                    )
                    let profile = self.tuner.makeProfile(
                        plan: plan,
                        metadata: metadata,
                        promptTokenCount: preparation.promptTokenCount
                    )
                    let parameters = self.tuner.makeParameters(options: options, profile: profile)

                    await self.logPlan(
                        metadata: metadata,
                        plan: plan,
                        promptTokenCount: preparation.promptTokenCount,
                        parameters: parameters,
                        cacheOutcome: preparation.cacheOutcome
                    )

                    let startedAt = Date()
                    let stream = try await self.executor.execute(
                        container: self.modelContainer,
                        input: preparation.input,
                        cache: reuseDecision.cache,
                        parameters: parameters,
                        reusedPrefixTokenCount: preparation.reusedPrefixTokenCount
                    )

                    var events: [MLXGenerationEvent] = []
                    var firstChunkLatency: TimeInterval?
                    var streamingState = MLXStreamingResponseState()
                    for try await event in stream {
                        try Task.checkCancellation()
                        events.append(event)

                        if firstChunkLatency == nil,
                           case .textChunk = event {
                            firstChunkLatency = Date().timeIntervalSince(startedAt)
                        }

                        switch event {
                        case .textChunk(let text):
                            if plan.toolPolicy == .disabled {
                                let result = self.assembler.streamDelta(state: streamingState, chunk: text)
                                streamingState = result.state
                                if !result.delta.isEmpty {
                                    continuation.yield(self.assembler.streamEntry(for: result.delta))
                                }
                            } else {
                            }
                        case .nativeToolCall, .info:
                            break
                        case .completed:
                            if plan.toolPolicy != .disabled {
                                let finalEntry = try self.assembler.finalEntry(plan: plan, events: events)
                                continuation.yield(finalEntry)
                                if self.shouldWarmPrefixCache(for: finalEntry, toolPolicy: plan.toolPolicy) {
                                    let nextTranscript = Transcript(entries: Array(transcript) + [finalEntry])
                                    Task {
                                        await self.warmPrefixCache(transcript: nextTranscript, options: options)
                                    }
                                }
                            } else {
                                let finalText = self.assembler.sanitizeAssistantResponse(streamingState.rawText)
                                if !finalText.isEmpty, finalText != streamingState.emittedVisibleText {
                                    let startIndex = finalText.index(
                                        finalText.startIndex,
                                        offsetBy: streamingState.emittedVisibleText.count
                                    )
                                    let trailingText = String(finalText[startIndex...])
                                    if !trailingText.isEmpty {
                                        continuation.yield(self.assembler.streamEntry(for: trailingText))
                                    }
                                }
                            }
                        }
                    }

                    await self.recordDiagnostics(
                        metadata: metadata,
                        plan: plan,
                        promptTokenCount: preparation.promptTokenCount,
                        cacheOutcome: preparation.cacheOutcome,
                        parameters: parameters,
                        startedAt: startedAt,
                        events: events,
                        firstChunkLatency: firstChunkLatency
                    )

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

    private func execute(
        transcript: Transcript,
        options: GenerationOptions?
    ) async throws -> (plan: MLXExecutionPlan, events: [MLXGenerationEvent], firstChunkLatency: TimeInterval?) {
        let metadata = await resolveMetadata()
        let plan = try planner.plan(transcript: transcript, options: options, metadata: metadata)
        let reuseDecision = prefixCacheStore.lookup(plan: plan, metadata: metadata)

        let preparation = try await executor.prepareExecution(
            container: modelContainer,
            plan: plan,
            reuseDecision: reuseDecision
        )
        let profile = tuner.makeProfile(
            plan: plan,
            metadata: metadata,
            promptTokenCount: preparation.promptTokenCount
        )
        tuningProfile = profile
        let parameters = tuner.makeParameters(options: options, profile: profile)

        await logPlan(
            metadata: metadata,
            plan: plan,
            promptTokenCount: preparation.promptTokenCount,
            parameters: parameters,
            cacheOutcome: preparation.cacheOutcome
        )

        let startedAt = Date()
        let stream = try await executor.execute(
            container: modelContainer,
            input: preparation.input,
            cache: reuseDecision.cache,
            parameters: parameters,
            reusedPrefixTokenCount: preparation.reusedPrefixTokenCount
        )

        var events: [MLXGenerationEvent] = []
        var firstChunkLatency: TimeInterval?
        for try await event in stream {
            if firstChunkLatency == nil,
               case .textChunk = event {
                firstChunkLatency = Date().timeIntervalSince(startedAt)
            }
            events.append(event)
        }

        await recordDiagnostics(
            metadata: metadata,
            plan: plan,
            promptTokenCount: preparation.promptTokenCount,
            cacheOutcome: preparation.cacheOutcome,
            parameters: parameters,
            startedAt: startedAt,
            events: events,
            firstChunkLatency: firstChunkLatency
        )

        return (plan, events, firstChunkLatency)
    }

    private func resolveMetadata() async -> MLXModelMetadata {
        if let metadata {
            return metadata
        }

        let configuration = await modelContainer.configuration
        let modelID = configuration.name
        let resolved = await MLXModelMetadataRegistry.shared.metadata(for: modelID) ?? .fallback(modelID: modelID)
        metadata = resolved
        return resolved
    }

    private func shouldWarmPrefixCache(
        for entry: Transcript.Entry,
        toolPolicy: MLXToolPolicy
    ) -> Bool {
        guard toolPolicy == .disabled else {
            return false
        }
        if case .response = entry {
            return true
        }
        return false
    }

    private func warmPrefixCache(
        transcript: Transcript,
        options: GenerationOptions?
    ) async {
        do {
            let metadata = await resolveMetadata()
            guard let warmupPlan = try planner.warmupPlan(
                transcript: transcript,
                options: options,
                metadata: metadata
            ) else {
                return
            }

            let profile = tuner.makeProfile(
                plan: MLXExecutionPlan(
                    input: warmupPlan.input,
                    responseMode: .text,
                    toolPolicy: .disabled,
                    cachePlan: MLXCachePlan(
                        reuseScope: .prefixReusable,
                        cacheKey: warmupPlan.cacheKey,
                        prefixMessages: [],
                        suffixMessages: [],
                        prefixInput: warmupPlan.input
                    ),
                    promptTokenEstimate: nil,
                    schemaFingerprint: nil,
                    additionalContext: [:],
                    plannerDiagnostics: .init(
                        systemMessageCount: 0,
                        userMessageCount: 0,
                        assistantMessageCount: 0,
                        toolMessageCount: 0,
                        imageCount: 0,
                        toolDefinitionCount: 0
                    )
                ),
                metadata: metadata,
                promptTokenCount: nil
            )
            let parameters = tuner.makeParameters(options: options, profile: profile)
            let built = try await executor.buildPrefixCache(
                container: modelContainer,
                input: warmupPlan.input,
                parameters: parameters
            )

            prefixCacheStore.store(
                cacheKey: warmupPlan.cacheKey,
                kvCache: built.cache,
                prefixTokenCount: built.prefixTokenCount,
                metadata: metadata
            )

            #if DEBUG
            print(
                "[MLXLanguageModel] prefixCache stored modelID=\(metadata.modelID) tokens=\(built.prefixTokenCount)"
            )
            #endif
        } catch {
            Logger.warning("[MLXLanguageModel] Failed to warm prefix cache: \(error)")
        }
    }

    private func logPlan(
        metadata: MLXModelMetadata,
        plan: MLXExecutionPlan,
        promptTokenCount: Int,
        parameters: GenerateParameters,
        cacheOutcome: String
    ) async {
        #if DEBUG
        print(
            "[MLXLanguageModel] plan modelID=\(metadata.modelID) runtime=\(metadata.runtimeFamily.rawValue) toolPolicy=\(plan.toolPolicy.rawValue) promptTokens=\(promptTokenCount) cache=\(cacheOutcome) prefillStep=\(parameters.prefillStepSize) kvBits=\(String(describing: parameters.kvBits)) maxKVSize=\(String(describing: parameters.maxKVSize))"
        )
        #endif
    }

    private func recordDiagnostics(
        metadata: MLXModelMetadata,
        plan: MLXExecutionPlan,
        promptTokenCount: Int,
        cacheOutcome: String,
        parameters: GenerateParameters,
        startedAt: Date,
        events: [MLXGenerationEvent],
        firstChunkLatency: TimeInterval?
    ) async {
        let collected = assembler.collect(events: events)
        let parametersSummary =
            "prefillStep=\(parameters.prefillStepSize),kvBits=\(String(describing: parameters.kvBits)),maxKVSize=\(String(describing: parameters.maxKVSize))"

        lastDiagnostics = MLXRunDiagnostics(
            modelID: metadata.modelID,
            runtimeFamily: metadata.runtimeFamily,
            toolPolicy: plan.toolPolicy,
            promptTokenCount: promptTokenCount,
            cacheOutcome: cacheOutcome,
            parametersSummary: parametersSummary,
            firstChunkLatency: firstChunkLatency,
            totalLatency: Date().timeIntervalSince(startedAt),
            outputCharacterCount: collected.text.count,
            usedNativeToolCalls: !collected.nativeToolCalls.isEmpty
        )

        #if DEBUG
        print(
            "[MLXLanguageModel] completed runtime=\(metadata.runtimeFamily.rawValue) toolPolicy=\(plan.toolPolicy.rawValue) promptTokens=\(promptTokenCount) cache=\(cacheOutcome) chars=\(collected.text.count) nativeCalls=\(collected.nativeToolCalls.count)"
        )
        #endif
    }
}
#endif
