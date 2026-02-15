#if MLX_ENABLED
import Foundation
import MLXLMCommon
import MLXVLM
import Hub

public final class VLMModelLoader {

    private let hubApi: HubApi
    private var modelCache: [String: ModelContainer] = [:]
    private let cacheQueue = DispatchQueue(label: "com.openFoundationModels.vlmModelLoader.cache")

    public init(hubApi: HubApi = HubApi()) {
        self.hubApi = hubApi
    }

    public func loadModel(
        _ modelID: String,
        progress: Progress? = nil
    ) async throws -> ModelContainer {

        if let cached = getCachedModel(modelID) {
            progress?.completedUnitCount = progress?.totalUnitCount ?? 100
            progress?.localizedDescription = NSLocalizedString("VLM loaded from cache", comment: "")
            return cached
        }

        let loadingProgress = progress ?? Progress(totalUnitCount: 100)
        loadingProgress.localizedDescription = NSLocalizedString("Loading VLM...", comment: "")

        let config = ModelConfiguration(id: modelID)

        let container = try await VLMModelFactory.shared.loadContainer(
            hub: hubApi,
            configuration: config
        ) { hubProgress in
            let fraction = hubProgress.fractionCompleted
            loadingProgress.completedUnitCount = Int64(fraction * Double(loadingProgress.totalUnitCount))

            if let description = hubProgress.localizedAdditionalDescription {
                loadingProgress.localizedAdditionalDescription = description
            }
        }

        setCachedModel(container, for: modelID)

        loadingProgress.completedUnitCount = loadingProgress.totalUnitCount
        loadingProgress.localizedDescription = NSLocalizedString("VLM ready", comment: "")

        return container
    }

    public func downloadModel(
        _ modelID: String,
        progress: Progress? = nil
    ) async throws {
        _ = try await loadModel(modelID, progress: progress)
    }

    public func isCached(_ modelID: String) -> Bool {
        cacheQueue.sync { modelCache[modelID] != nil }
    }

    public func clearCache(for modelID: String) {
        _ = cacheQueue.sync { modelCache.removeValue(forKey: modelID) }
    }

    public func clearCache() {
        cacheQueue.sync { modelCache.removeAll() }
    }

    private func getCachedModel(_ modelID: String) -> ModelContainer? {
        cacheQueue.sync { modelCache[modelID] }
    }

    private func setCachedModel(_ container: ModelContainer, for modelID: String) {
        cacheQueue.sync { modelCache[modelID] = container }
    }
}
#endif
