#if MLX_ENABLED
import Foundation
import MLXLMCommon

/// Responsible only for model default sampling and stop token policy.
public protocol SamplingPolicy: Sendable {
    var defaultParameters: GenerateParameters { get }
    var stopTokens: Set<String> { get }
}

extension SamplingPolicy {
    public var stopTokens: Set<String> { [] }
}
#endif
