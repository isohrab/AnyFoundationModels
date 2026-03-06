#if MLX_ENABLED
import Foundation
import MLXLMCommon
import MLXLLM
import MLXVLM
import Hub

/// Errors that occur during MLX model loading and validation.
public enum MLXModelLoadingError: LocalizedError {
    /// The model's tokenizer_config.json is missing the required chat_template field.
    case chatTemplateNotFound(modelID: String)
    /// The model's config.json could not be found in the downloaded directory.
    case configNotFound(modelID: String)
    /// The tokenizer_config.json could not be parsed.
    case tokenizerConfigInvalid(modelID: String, underlyingError: Error)
    /// The Qwen3.5 variant is unsupported by the standard MLX compatibility matrix.
    case unsupportedQwen35Variant(modelID: String, reason: String)
    /// Qwen3.5 config inspection failed before the model could be loaded.
    case qwen35ClassificationFailed(modelID: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .chatTemplateNotFound(let modelID):
            return "Model '\(modelID)' is missing chat_template in tokenizer_config.json. "
                + "This typically occurs when the model was converted without preserving the chat template. "
                + "Use the original HuggingFace model or a properly converted variant that includes the chat_template."
        case .configNotFound(let modelID):
            return "config.json not found for model '\(modelID)'. The model directory may be incomplete."
        case .tokenizerConfigInvalid(let modelID, let underlyingError):
            return "Failed to parse tokenizer_config.json for model '\(modelID)': \(underlyingError.localizedDescription)"
        case .unsupportedQwen35Variant(let modelID, let reason):
            return "Model '\(modelID)' is not supported: \(reason)"
        case .qwen35ClassificationFailed(let modelID, let reason):
            return "Failed to inspect Qwen3.5 model '\(modelID)': \(reason)"
        }
    }
}

/// Capabilities detected from a model's configuration files.
public struct ModelCapabilities: Sendable {
    /// Whether the model has vision capabilities (vision_config present in config.json).
    public let isVLM: Bool
    /// The model_type string from config.json (e.g. "qwen3_5_moe", "llama").
    public let modelType: String?
    /// Whether the model has a chat_template in tokenizer_config.json.
    public let hasChatTemplate: Bool
}

/// Unified model loader that handles both LLM and VLM models with progress reporting.
///
/// Uses mlx-swift-lm's trampoline factory pattern which automatically
/// tries VLM loading first, then falls back to LLM loading.
/// Validates model artifacts (chat_template, config.json) before loading
/// to provide clear error messages for defective model conversions.
public final class ModelLoader {
    
    private let hubApi: HubApi
    private var modelCache: [String: ModelContainer] = [:]
    private let cacheQueue = DispatchQueue(label: "com.openFoundationModels.modelLoader.cache")
    
    public init(hubApi: HubApi = HubApi()) {
        self.hubApi = hubApi
    }

    /// Creates a loader that downloads models to the specified base directory.
    ///
    /// - Parameter downloadBase: Base directory for model downloads.
    ///   Models are stored under `<downloadBase>/models/<modelID>/`.
    public convenience init(downloadBase: URL) {
        self.init(hubApi: HubApi(downloadBase: downloadBase))
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

        // Step 2: Download chat template files not covered by *.json glob
        await downloadChatTemplateFiles(modelID: modelID)

        // Step 3: Sanitize config.json (fix non-standard JSON like Infinity, NaN)
        sanitizeConfigJSON(in: modelDirectory)

        // Step 4: Validate model artifacts before loading
        try validateModelArtifacts(in: modelDirectory, modelID: modelID)

        // Step 5: Load model from local directory
        loadingProgress.localizedDescription = NSLocalizedString("Loading model into memory...", comment: "")
        loadingProgress.localizedAdditionalDescription = nil

        let container = try await loadContainer(
            from: modelDirectory,
            modelID: modelID,
            hub: hubApi
        )

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
    
    /// Load a model from a local directory.
    ///
    /// Validates model artifacts before loading. If the chat template is missing
    /// locally, attempts to fetch only the missing template file from the Hub.
    public func loadLocalModel(from path: URL, modelID: String? = nil) async throws -> ModelContainer {
        let resolvedID = modelID ?? path.lastPathComponent

        if !Self.hasChatTemplate(in: path) {
            await downloadChatTemplateFiles(modelID: resolvedID)
        }

        try validateModelArtifacts(in: path, modelID: resolvedID)

        return try await loadContainer(
            from: path,
            modelID: resolvedID,
            hub: hubApi
        )
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
    
    
    // MARK: - Capability Detection

    /// Detects model capabilities from its configuration files.
    public static func detectCapabilities(in directory: URL) -> ModelCapabilities {
        let configURL = directory.appendingPathComponent("config.json")

        var isVLM = false
        var modelType: String?

        if let data = (try? Data(contentsOf: configURL)) {
            do {
                if let parsed = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    isVLM = parsed["vision_config"] != nil
                    modelType = parsed["model_type"] as? String
                }
            } catch {
                // Config not parseable, continue with defaults
            }
        }

        return ModelCapabilities(
            isVLM: isVLM,
            modelType: modelType,
            hasChatTemplate: hasChatTemplate(in: directory)
        )
    }

    // MARK: - Routing

    private func loadContainer(
        from directory: URL,
        modelID: String,
        hub: HubApi
    ) async throws -> ModelContainer {
        let configuration = ModelConfiguration(directory: directory)

        if let variant = try Qwen35VariantClassifier.classify(modelID: modelID, in: directory) {
            #if DEBUG
            print(
                "[ModelLoader] Qwen3.5 classification modelID=\(modelID) architecture=\(variant.architecture.rawValue) modality=\(variant.modality.rawValue) quantization=\(variant.quantization.description) runtime=\(variant.runtime.rawValue) supported=\(variant.supportVerdict.isSupported)"
            )
            #endif

            switch variant.supportVerdict {
            case .supported:
                let metadata = MLXModelMetadata(
                    modelID: modelID,
                    runtimeFamily: variant.runtime == .llm ? .llm : .vlm,
                    modalityFamily: variant.modality == .text ? .text : .conditionalGeneration,
                    qwen35Variant: variant
                )
                switch variant.runtime {
                case .llm:
                    let container = try await LLMModelFactory.shared.loadContainer(
                        hub: hub,
                        configuration: configuration
                    ) { _ in }
                    await MLXModelMetadataRegistry.shared.register(metadata)
                    return container
                case .vlm:
                    let container = try await VLMModelFactory.shared.loadContainer(
                        hub: hub,
                        configuration: configuration
                    ) { _ in }
                    await MLXModelMetadataRegistry.shared.register(metadata)
                    return container
                }
            case .unsupported(let reason):
                throw MLXModelLoadingError.unsupportedQwen35Variant(
                    modelID: modelID,
                    reason: reason
                )
            }
        }

        let container = try await MLXLMCommon.loadModelContainer(
            hub: hub,
            configuration: configuration
        ) { _ in }
        let capabilities = Self.detectCapabilities(in: directory)
        let metadata = MLXModelMetadata(
            modelID: modelID,
            runtimeFamily: capabilities.isVLM ? .vlm : .llm,
            modalityFamily: capabilities.isVLM ? .conditionalGeneration : .text,
            qwen35Variant: nil
        )
        await MLXModelMetadataRegistry.shared.register(metadata)
        return container
    }

    // MARK: - Validation

    /// Validates that required model artifacts are present and well-formed.
    private func validateModelArtifacts(in directory: URL, modelID: String) throws {
        let configURL = directory.appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw MLXModelLoadingError.configNotFound(modelID: modelID)
        }

        guard Self.hasChatTemplate(in: directory) else {
            throw MLXModelLoadingError.chatTemplateNotFound(modelID: modelID)
        }
    }

    // MARK: - Chat Template Resolution

    /// Checks whether a model directory contains a chat template in any supported format.
    ///
    /// Checks in the same priority order as swift-transformers:
    /// 1. `chat_template.jinja` (separate file)
    /// 2. `chat_template.json` (separate file)
    /// 3. Inline `chat_template` field in `tokenizer_config.json`
    private static func hasChatTemplate(in directory: URL) -> Bool {
        if FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("chat_template.jinja").path) {
            return true
        }

        if FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("chat_template.json").path) {
            return true
        }

        let tokenizerConfigURL = directory.appendingPathComponent("tokenizer_config.json")
        guard let data = (try? Data(contentsOf: tokenizerConfigURL)) else { return false }
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                return false
            }
            let chatTemplate = parsed["chat_template"]
            if let str = chatTemplate as? String {
                return !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if let arr = chatTemplate as? [Any] {
                return !arr.isEmpty
            }
            return false
        } catch {
            return false
        }
    }

    // MARK: - Chat Template Download

    /// Downloads chat template files that are not covered by the `*.json` glob
    /// used by `MLXLMCommon.downloadModel()`.
    ///
    /// Some models store the chat template as a separate `chat_template.jinja`
    /// file instead of embedding it in `tokenizer_config.json`.
    private func downloadChatTemplateFiles(modelID: String) async {
        let repo = Hub.Repo(id: modelID)
        _ = try? await hubApi.snapshot(
            from: repo,
            matching: ["chat_template.jinja"],
            progressHandler: { _ in }
        )
    }

    // MARK: - Config Sanitization

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
