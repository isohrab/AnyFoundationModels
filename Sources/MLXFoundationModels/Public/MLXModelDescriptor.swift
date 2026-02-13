#if MLX_ENABLED
import Foundation

/// Declarative model selection for MLX-backed language models.
///
/// - Important: The default model is `mlx-community/Nanbeige4.1-3B-8bit`.
public struct MLXModelDescriptor: Sendable, Equatable {
    /// Prompt/rendering strategy for a model.
    public enum PromptStyle: String, Sendable, Equatable {
        case auto
        case llama
        case llama3
        case gptOSS
        case functionGemma
    }

    /// Hugging Face model identifier (or local registry id).
    public let id: String

    /// Prompt strategy for model card creation.
    public let promptStyle: PromptStyle

    public init(
        id: String,
        promptStyle: PromptStyle = .auto
    ) {
        self.id = id
        self.promptStyle = promptStyle
    }

    /// Default runtime model for this package.
    public static let `default` = MLXModelDescriptor.nanbeige41_3B_8bit

    /// Recommended default profile (fast + strong quality for current setup).
    public static let nanbeige41_3B_8bit = MLXModelDescriptor(
        id: "mlx-community/Nanbeige4.1-3B-8bit",
        promptStyle: .llama3
    )

    /// Build an appropriate ModelProfile for the descriptor.
    public func makeModelProfile() -> any ModelProfile {
        switch resolvedPromptStyle() {
        case .llama:
            return LlamaModelProfile(id: id)
        case .llama3:
            return Llama3ModelProfile(id: id)
        case .gptOSS:
            return GPTOSSModelProfile(id: id)
        case .functionGemma:
            return FunctionGemmaModelProfile(id: id)
        case .auto:
            // `auto` is resolved above and should not reach this branch.
            return Llama3ModelProfile(id: id)
        }
    }

    private func resolvedPromptStyle() -> PromptStyle {
        if promptStyle != .auto {
            return promptStyle
        }

        let normalized = id.lowercased()
        if normalized.contains("functiongemma") {
            return .functionGemma
        }
        if normalized.contains("gpt-oss") || normalized.contains("gpt_oss") {
            return .gptOSS
        }
        if normalized.contains("llama-2") || normalized.contains("llama2") {
            return .llama
        }
        return .llama3
    }
}
#endif
