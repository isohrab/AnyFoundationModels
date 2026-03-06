#if MLX_ENABLED
import Foundation

enum MLXRuntimeFamily: String, Sendable {
    case llm
    case vlm
    case unknown
}

enum MLXModalityFamily: String, Sendable {
    case text
    case conditionalGeneration
    case unknown
}

struct MLXModelMetadata: Sendable {
    let modelID: String
    let runtimeFamily: MLXRuntimeFamily
    let modalityFamily: MLXModalityFamily
    let qwen35Variant: Qwen35Variant?

    var prefersThinkingDisabled: Bool {
        qwen35Variant != nil || modelID.lowercased().contains("qwen")
    }

    var prefersConservativeToolUse: Bool {
        if let variant = qwen35Variant {
            return variant.parameterFamily == .denseSmall || variant.runtime == .vlm
        }

        let lowercased = modelID.lowercased()
        return runtimeFamily == .vlm || lowercased.contains("2b") || lowercased.contains("4b")
    }

    static func fallback(modelID: String) -> Self {
        Self(
            modelID: modelID,
            runtimeFamily: .unknown,
            modalityFamily: .unknown,
            qwen35Variant: nil
        )
    }
}

actor MLXModelMetadataRegistry {
    static let shared = MLXModelMetadataRegistry()

    private var metadataByModelID: [String: MLXModelMetadata] = [:]

    func register(_ metadata: MLXModelMetadata) {
        metadataByModelID[metadata.modelID] = metadata
    }

    func metadata(for modelID: String) -> MLXModelMetadata? {
        metadataByModelID[modelID]
    }
}
#endif
