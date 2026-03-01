#if MLX_ENABLED
import Foundation
import MLXLMCommon
import MLXLLM
import Hub

/// Model loader that handles downloading and loading models with progress reporting.
public final class ModelLoader {
    
    private let hubApi: HubApi
    private var modelCache: [String: ModelContainer] = [:]
    private let cacheQueue = DispatchQueue(label: "com.openFoundationModels.modelLoader.cache")
    
    public init(hubApi: HubApi = HubApi()) {
        self.hubApi = hubApi
    }
    
    /// Load a model with optional progress reporting.
    ///
    /// When a `Progress` is provided, it reports byte-level download progress:
    /// - `totalUnitCount`: total bytes to download
    /// - `completedUnitCount`: bytes downloaded so far
    /// - `localizedDescription`: e.g. "1.2 GB / 4.5 GB"
    /// - `localizedAdditionalDescription`: e.g. "45.3 MB/s"
    public func loadModel(
        _ modelID: String,
        progress: Progress? = nil
    ) async throws -> ModelContainer {

        if let cached = getCachedModel(modelID) {
            progress?.completedUnitCount = progress?.totalUnitCount ?? 1
            progress?.localizedDescription = NSLocalizedString("Model loaded from cache", comment: "")
            return cached
        }

        let loadingProgress = progress ?? Progress(totalUnitCount: 0)
        loadingProgress.localizedDescription = NSLocalizedString("Fetching model info...", comment: "")

        // Pre-fetch file metadata to get total byte count
        let repo = Hub.Repo(id: modelID)
        let modelGlobs = ["*.safetensors", "*.json"]
        let metadata = try await hubApi.getFileMetadata(from: repo, matching: modelGlobs)
        let totalBytes = Int64(metadata.compactMap(\.size).reduce(0, +))

        loadingProgress.totalUnitCount = totalBytes
        loadingProgress.completedUnitCount = 0

        let totalString = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        loadingProgress.localizedDescription = "0 MB / \(totalString)"

        let config = ModelConfiguration(id: modelID)

        // Step 1: Download model files
        let modelDirectory = try await MLXLMCommon.downloadModel(
            hub: hubApi,
            configuration: config
        ) { hubProgress in
            let fraction = hubProgress.fractionCompleted
            let completedBytes = Int64(fraction * Double(totalBytes))
            loadingProgress.completedUnitCount = completedBytes

            let completedString = ByteCountFormatter.string(fromByteCount: completedBytes, countStyle: .file)
            loadingProgress.localizedDescription = "\(completedString) / \(totalString)"

            if let speed = hubProgress.userInfo[.throughputKey] as? Double {
                let speedString = ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file)
                loadingProgress.localizedAdditionalDescription = "\(speedString)/s"
            }
        }

        // Step 2: Sanitize config.json (fix non-standard JSON like Infinity, NaN)
        sanitizeConfigJSON(in: modelDirectory)

        // Step 3: Load model from local directory
        loadingProgress.localizedDescription = NSLocalizedString("Loading model into memory...", comment: "")
        loadingProgress.localizedAdditionalDescription = nil

        let container = try await MLXLMCommon.loadModelContainer(
            hub: hubApi,
            directory: modelDirectory
        ) { _ in }

        setCachedModel(container, for: modelID)

        loadingProgress.completedUnitCount = totalBytes
        loadingProgress.localizedDescription = NSLocalizedString("Model ready", comment: "")
        loadingProgress.localizedAdditionalDescription = nil

        return container
    }
    
    /// Download a model without loading it into memory
    public func downloadModel(
        _ modelID: String,
        progress: Progress? = nil
    ) async throws {
        _ = try await loadModel(modelID, progress: progress)
    }
    
    /// Load a model from a local directory
    public func loadLocalModel(from path: URL) async throws -> ModelContainer {
        let config = ModelConfiguration(directory: path)
        
        let container = try await MLXLMCommon.loadModelContainer(
            hub: hubApi,
            configuration: config
        ) { _ in
        }
        
        return container
    }
    
    public func cachedModels() -> [String] {
        cacheQueue.sync {
            Array(modelCache.keys)
        }
    }
    
    public func clearCache() {
        cacheQueue.sync {
            modelCache.removeAll()
        }
    }
    
    public func clearCache(for modelID: String) {
        _ = cacheQueue.sync {
            modelCache.removeValue(forKey: modelID)
        }
    }
    
    public func isCached(_ modelID: String) -> Bool {
        cacheQueue.sync {
            modelCache[modelID] != nil
        }
    }
    
    
    /// Sanitizes config.json for compatibility with mlx-swift-lm.
    ///
    /// Fixes:
    /// 1. Non-standard JSON tokens (Infinity, -Infinity, NaN)
    /// 2. Missing MoE fields required by NemotronH decoder for dense (non-MoE) variants
    private func sanitizeConfigJSON(in directory: URL) {
        let configURL = directory.appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: configURL.path) else { return }
        do {
            var content = try String(contentsOf: configURL, encoding: .utf8)
            let original = content

            // Fix non-standard JSON literals
            content = content.replacingOccurrences(of: "-Infinity", with: "-1e38")
            content = content.replacingOccurrences(of: "Infinity", with: "1e38")
            content = content.replacingOccurrences(of: "NaN", with: "0")

            // Inject default MoE fields for nemotron_h dense models
            if content.contains("\"nemotron_h\"") {
                let moeDefaults: [(key: String, value: String)] = [
                    ("moe_intermediate_size", "0"),
                    ("moe_shared_expert_intermediate_size", "0"),
                    ("n_routed_experts", "0"),
                    ("num_experts_per_tok", "0"),
                ]
                for (key, value) in moeDefaults {
                    if !content.contains("\"\(key)\"") {
                        // Insert before the closing brace
                        if let range = content.range(of: "}", options: .backwards) {
                            content.insert(contentsOf: ",\n  \"\(key)\": \(value)", at: range.lowerBound)
                        }
                    }
                }
            }

            if content != original {
                try content.write(to: configURL, atomically: true, encoding: .utf8)
            }
        } catch {
            // Best effort — if we can't patch, the load will fail with a clear error
        }
    }

    private func getCachedModel(_ modelID: String) -> ModelContainer? {
        cacheQueue.sync {
            modelCache[modelID]
        }
    }
    
    private func setCachedModel(_ container: ModelContainer, for modelID: String) {
        cacheQueue.sync {
            modelCache[modelID] = container
        }
    }
}
#endif
