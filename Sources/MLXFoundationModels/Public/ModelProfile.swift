#if MLX_ENABLED
import Foundation

/// Aggregates model-specific responsibilities for MLX execution.
public protocol ModelProfile: Identifiable, Sendable, PromptRenderer, ResponseDecoder, SamplingPolicy where ID == String {
    var id: String { get }
}
#endif
