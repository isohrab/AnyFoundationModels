#if MLX_ENABLED
import Foundation
import OpenFoundationModels

/// Responsible only for rendering a model-specific prompt from transcript data.
public protocol PromptRenderer: Sendable {
    func renderPrompt(transcript: Transcript, options: GenerationOptions?) -> Prompt
}
#endif
