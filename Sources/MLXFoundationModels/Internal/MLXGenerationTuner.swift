#if MLX_ENABLED
import Foundation
import OpenFoundationModels
@preconcurrency import MLXLMCommon

struct MLXGenerationProfile: Sendable {
    let prefillStepSize: Int
    let kvBits: Int?
    let kvGroupSize: Int
    let quantizedKVStart: Int
    let maxKVSize: Int?
}

struct MLXRunDiagnostics: Sendable {
    let modelID: String
    let runtimeFamily: MLXRuntimeFamily
    let toolPolicy: MLXToolPolicy
    let promptTokenCount: Int
    let cacheOutcome: String
    let parametersSummary: String
    let firstChunkLatency: TimeInterval?
    let totalLatency: TimeInterval
    let outputCharacterCount: Int
    let usedNativeToolCalls: Bool
}

struct MLXGenerationTuner {

    func makeProfile(
        plan: MLXExecutionPlan,
        metadata: MLXModelMetadata,
        promptTokenCount: Int?
    ) -> MLXGenerationProfile {
        let tokenCount = promptTokenCount ?? plan.promptTokenEstimate ?? 0

        var prefillStepSize = 512
        if tokenCount > 8192 {
            prefillStepSize = 1536
        } else if tokenCount > 2048 {
            prefillStepSize = 1024
        }
        if metadata.runtimeFamily == .vlm {
            prefillStepSize = min(prefillStepSize, 1024)
        }

        let kvBits: Int? = tokenCount > 8192 ? 4 : nil
        let quantizedKVStart = kvBits == nil ? 0 : 4096

        return MLXGenerationProfile(
            prefillStepSize: prefillStepSize,
            kvBits: kvBits,
            kvGroupSize: 64,
            quantizedKVStart: quantizedKVStart,
            maxKVSize: nil
        )
    }

    func makeParameters(
        options: GenerationOptions?,
        profile: MLXGenerationProfile
    ) -> GenerateParameters {
        GenerateParameters(
            maxTokens: options?.maximumResponseTokens ?? 2048,
            maxKVSize: profile.maxKVSize,
            kvBits: profile.kvBits,
            kvGroupSize: profile.kvGroupSize,
            quantizedKVStart: profile.quantizedKVStart,
            temperature: options?.temperature.map { Float($0) } ?? 0,
            topP: 0.9,
            repetitionPenalty: 1.05,
            repetitionContextSize: 64,
            prefillStepSize: profile.prefillStepSize
        )
    }
}
#endif
