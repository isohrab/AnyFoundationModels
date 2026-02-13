#if MLX_ENABLED
import Foundation
import OpenFoundationModels
import MLXLMCommon

// Maps OpenFoundationModels.GenerationOptions into internal SamplingParameters.
enum OptionsMapper {
    static func map(_ options: GenerationOptions?, modelProfile: (any ModelProfile)? = nil) -> SamplingParameters {
        // When options is nil, use profile defaults as the source
        guard let options else {
            if let modelProfile = modelProfile {
                // Use profile default parameters
                return SamplingParameters(
                    temperature: Double(modelProfile.defaultParameters.temperature),
                    topP: Double(modelProfile.defaultParameters.topP),
                    topK: nil,  // default parameters do not expose topK
                    maxTokens: modelProfile.defaultParameters.maxTokens,
                    stop: nil,  // default parameters do not expose stop
                    seed: nil   // default parameters do not expose seed
                )
            } else {
                // No options and no profile - return empty parameters
                return SamplingParameters(temperature: nil, topP: nil, topK: nil, maxTokens: nil, stop: nil, seed: nil)
            }
        }

        // Map all available parameters from GenerationOptions
        // Priority: GenerationOptions > profile defaults > nil
        let fallbackTemp: Double? = modelProfile.map { Double($0.defaultParameters.temperature) }
        let fallbackTopP: Double? = modelProfile.map { Double($0.defaultParameters.topP) }

        var sampling = SamplingParameters(
            temperature: options.temperature ?? fallbackTemp,
            topP: fallbackTopP,  // Use profile topP as fallback
            topK: nil,  // Will be set based on sampling mode if available
            maxTokens: options.maximumResponseTokens ?? modelProfile?.defaultParameters.maxTokens,
            stop: nil,  // GenerationOptions doesn't expose stop sequences
            seed: nil  // Will be set based on sampling mode if available
        )

        // Extract sampling mode parameters
        // NOTE: SamplingMode.Kind is private, so we cannot directly compare mode types.
        // Set temperature to 0.0 if not specified but temperature is 0
        if options.temperature == 0 {
            if sampling.temperature == nil { 
                sampling.temperature = 0.0 
            }
        }

        return sampling
    }
}

#endif
