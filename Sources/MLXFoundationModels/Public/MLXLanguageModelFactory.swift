#if MLX_ENABLED
import Foundation

/// Factory for loading MLX-backed language models with a unified descriptor.
///
/// Default target model: `mlx-community/Nanbeige4.1-3B-8bit`.
public final class MLXLanguageModelFactory {
    private let loader: ModelLoader

    public init(loader: ModelLoader = ModelLoader()) {
        self.loader = loader
    }

    /// Load and initialize an MLXLanguageModel.
    public func makeLanguageModel(
        descriptor: MLXModelDescriptor = .default,
        progress: Progress? = nil
    ) async throws -> MLXLanguageModel {
        let container = try await loader.loadModel(descriptor.id, progress: progress)
        let profile = descriptor.makeModelProfile()
        return try await MLXLanguageModel(modelContainer: container, profile: profile)
    }

    /// Pre-download model artifacts without constructing the runtime model object.
    public func downloadModel(
        descriptor: MLXModelDescriptor = .default,
        progress: Progress? = nil
    ) async throws {
        try await loader.downloadModel(descriptor.id, progress: progress)
    }

    public func isCached(_ descriptor: MLXModelDescriptor) -> Bool {
        loader.isCached(descriptor.id)
    }

    public func clearCache(_ descriptor: MLXModelDescriptor) {
        loader.clearCache(for: descriptor.id)
    }
}
#endif
