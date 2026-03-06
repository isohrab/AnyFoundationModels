#if MLX_ENABLED
import Foundation

enum Qwen35ArchitectureFamily: String, Sendable, Equatable {
    case dense
    case moe
}

enum Qwen35ModalityFamily: String, Sendable, Equatable {
    case text
    case conditionalGeneration
}

enum Qwen35RuntimeFamily: String, Sendable, Equatable {
    case llm
    case vlm
}

enum Qwen35ParameterFamily: String, Sendable, Equatable {
    case denseSmall
    case denseMid
    case denseLarge
    case moeMedium
    case moeLarge
}

enum Qwen35QuantizationFamily: Sendable, Equatable, CustomStringConvertible {
    case bf16
    case standardMLX(bits: Int?)
    case unsupportedCustom(String)

    var description: String {
        switch self {
        case .bf16:
            return "bf16"
        case .standardMLX(let bits):
            if let bits {
                return "standard-mlx-\(bits)bit"
            }
            return "standard-mlx"
        case .unsupportedCustom(let format):
            return "unsupported-\(format)"
        }
    }
}

enum Qwen35SupportVerdict: Sendable, Equatable {
    case supported
    case unsupported(String)

    var isSupported: Bool {
        switch self {
        case .supported:
            return true
        case .unsupported:
            return false
        }
    }
}

struct Qwen35Variant: Sendable, Equatable {
    let modelID: String
    let architecture: Qwen35ArchitectureFamily
    let modality: Qwen35ModalityFamily
    let runtime: Qwen35RuntimeFamily
    let quantization: Qwen35QuantizationFamily
    let parameterFamily: Qwen35ParameterFamily?
    let supportVerdict: Qwen35SupportVerdict
}

struct Qwen35SupportMatrixEntry: Sendable, Equatable {
    let modelID: String
    let architecture: Qwen35ArchitectureFamily
    let modality: Qwen35ModalityFamily
    let quantization: Qwen35QuantizationFamily
    let parameterFamily: Qwen35ParameterFamily
    let smokeEligible: Bool
    let requiresLargeMemory: Bool
}

enum Qwen35SupportMatrix {
    static let representativeEntries: [Qwen35SupportMatrixEntry] = [
        .init(
            modelID: "mlx-community/Qwen3.5-2B-6bit",
            architecture: .dense,
            modality: .text,
            quantization: .standardMLX(bits: 6),
            parameterFamily: .denseSmall,
            smokeEligible: true,
            requiresLargeMemory: false
        ),
        .init(
            modelID: "mlx-community/Qwen3.5-9B-8bit",
            architecture: .dense,
            modality: .text,
            quantization: .standardMLX(bits: 8),
            parameterFamily: .denseMid,
            smokeEligible: true,
            requiresLargeMemory: false
        ),
        .init(
            modelID: "mlx-community/Qwen3.5-27B-4bit",
            architecture: .dense,
            modality: .text,
            quantization: .standardMLX(bits: 4),
            parameterFamily: .denseLarge,
            smokeEligible: true,
            requiresLargeMemory: true
        ),
        .init(
            modelID: "mlx-community/Qwen3.5-35B-A3B-4bit",
            architecture: .moe,
            modality: .text,
            quantization: .standardMLX(bits: 4),
            parameterFamily: .moeMedium,
            smokeEligible: true,
            requiresLargeMemory: true
        ),
        .init(
            modelID: "mlx-community/Qwen3.5-122B-A10B-4bit",
            architecture: .moe,
            modality: .text,
            quantization: .standardMLX(bits: 4),
            parameterFamily: .moeLarge,
            smokeEligible: false,
            requiresLargeMemory: true
        ),
        .init(
            modelID: "mlx-community/Qwen3.5-4B-MLX-4bit",
            architecture: .dense,
            modality: .conditionalGeneration,
            quantization: .standardMLX(bits: 4),
            parameterFamily: .denseSmall,
            smokeEligible: true,
            requiresLargeMemory: false
        ),
        .init(
            modelID: "mlx-community/Qwen3.5-2B-bf16",
            architecture: .dense,
            modality: .text,
            quantization: .bf16,
            parameterFamily: .denseSmall,
            smokeEligible: true,
            requiresLargeMemory: false
        ),
    ]

    static let unsupportedFormatMarkers = [
        "mxfp",
        "nvfp",
        "optiq",
        "gptq",
        "awq",
        "gguf",
    ]
}

private struct Qwen35Inspection {
    let config: [String: Any]
    let configText: String
    let preprocessor: [String: Any]
    let preprocessorText: String
    let tokenizer: [String: Any]
    let tokenizerText: String
    let metadata: [String: String]
}

enum Qwen35VariantClassifier {
    static func classify(modelID: String, in directory: URL) throws -> Qwen35Variant? {
        let inspection = try inspect(directory: directory)
        guard let architecture = architecture(from: inspection.config) else {
            return nil
        }

        let modality = modality(from: inspection)
        let runtime: Qwen35RuntimeFamily = modality == .conditionalGeneration ? .vlm : .llm
        let quantization = quantizationFamily(modelID: modelID, inspection: inspection)
        let parameterFamily = parameterFamily(for: modelID, architecture: architecture)
        let supportVerdict: Qwen35SupportVerdict
        switch quantization {
        case .unsupportedCustom(let format):
            supportVerdict = .unsupported(
                "Model '\(modelID)' uses unsupported custom quantization '\(format)'. "
                    + "Only standard MLX Qwen3.5 bf16 and group-wise quantized variants are supported."
            )
        case .bf16, .standardMLX:
            supportVerdict = .supported
        }

        return Qwen35Variant(
            modelID: modelID,
            architecture: architecture,
            modality: modality,
            runtime: runtime,
            quantization: quantization,
            parameterFamily: parameterFamily,
            supportVerdict: supportVerdict
        )
    }

    private static func inspect(directory: URL) throws -> Qwen35Inspection {
        let configURL = directory.appendingPathComponent("config.json")
        let preprocessorURL = directory.appendingPathComponent("preprocessor_config.json")
        let tokenizerURL = directory.appendingPathComponent("tokenizer_config.json")

        let configText = try String(contentsOf: configURL, encoding: .utf8)
        let config = try loadJSONObject(from: configURL)

        let preprocessorText: String
        let preprocessor: [String: Any]
        if FileManager.default.fileExists(atPath: preprocessorURL.path) {
            preprocessorText = try String(contentsOf: preprocessorURL, encoding: .utf8)
            preprocessor = try loadJSONObject(from: preprocessorURL)
        } else {
            preprocessorText = ""
            preprocessor = [:]
        }

        let tokenizerText: String
        let tokenizer: [String: Any]
        if FileManager.default.fileExists(atPath: tokenizerURL.path) {
            tokenizerText = try String(contentsOf: tokenizerURL, encoding: .utf8)
            tokenizer = try loadJSONObject(from: tokenizerURL)
        } else {
            tokenizerText = ""
            tokenizer = [:]
        }

        let metadata = try firstSafetensorsMetadata(in: directory)

        return Qwen35Inspection(
            config: config,
            configText: configText,
            preprocessor: preprocessor,
            preprocessorText: preprocessorText,
            tokenizer: tokenizer,
            tokenizerText: tokenizerText,
            metadata: metadata
        )
    }

    private static func loadJSONObject(from url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw MLXModelLoadingError.qwen35ClassificationFailed(
                modelID: url.deletingLastPathComponent().lastPathComponent,
                reason: "Expected top-level JSON object in \(url.lastPathComponent)."
            )
        }
        return dictionary
    }

    private static func architecture(from config: [String: Any]) -> Qwen35ArchitectureFamily? {
        let rootModelType = (config["model_type"] as? String)?.lowercased()
        let textConfigModelType = ((config["text_config"] as? [String: Any])?["model_type"] as? String)?
            .lowercased()

        let candidates = [rootModelType, textConfigModelType].compactMap { $0 }
        if candidates.contains("qwen3_5_moe") {
            return .moe
        }
        if candidates.contains("qwen3_5") || candidates.contains("qwen3_5_text") {
            return .dense
        }
        return nil
    }

    private static func modality(from inspection: Qwen35Inspection) -> Qwen35ModalityFamily {
        if inspection.config["vision_config"] != nil {
            return .conditionalGeneration
        }

        if let architectures = inspection.config["architectures"] as? [String] {
            let joined = architectures.joined(separator: " ").lowercased()
            if joined.contains("conditionalgeneration") {
                return .conditionalGeneration
            }
        }

        if let processorClass = inspection.preprocessor["processor_class"] as? String,
            processorClass.lowercased().contains("vl")
        {
            return .conditionalGeneration
        }

        return .text
    }

    private static func quantizationFamily(modelID: String, inspection: Qwen35Inspection) -> Qwen35QuantizationFamily {
        if let unsupported = unsupportedCustomFormat(modelID: modelID, inspection: inspection) {
            return .unsupportedCustom(unsupported)
        }

        if let bits = quantizationBits(in: inspection.config) {
            return .standardMLX(bits: bits)
        }

        let searchable = [
            modelID.lowercased(),
            inspection.configText.lowercased(),
            inspection.preprocessorText.lowercased(),
            inspection.tokenizerText.lowercased(),
            inspection.metadataText.lowercased(),
        ].joined(separator: "\n")

        if searchable.contains("bf16") || searchable.contains("bfloat16") {
            return .bf16
        }

        return .standardMLX(bits: nil)
    }

    private static func unsupportedCustomFormat(modelID: String, inspection: Qwen35Inspection) -> String? {
        let searchableSegments = [
            modelID.lowercased(),
            inspection.configText.lowercased(),
            inspection.preprocessorText.lowercased(),
            inspection.tokenizerText.lowercased(),
            inspection.metadataText.lowercased(),
        ]

        let searchable = searchableSegments.joined(separator: "\n")
        for marker in Qwen35SupportMatrix.unsupportedFormatMarkers where searchable.contains(marker) {
            return marker
        }

        if containsQXQuantizationMarker(in: searchable) {
            return "qx"
        }

        if let format = inspection.metadata["format"]?.lowercased(), format != "mlx" {
            return format
        }

        return nil
    }

    private static func containsQXQuantizationMarker(in text: String) -> Bool {
        let patterns = [
            "(^|[^a-z])qx\\d+",
            "(^|[^a-z])qx-",
            "(^|[^a-z])qx_",
        ]

        for pattern in patterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                let range = NSRange(location: 0, length: text.utf16.count)
                if regex.firstMatch(in: text, options: [], range: range) != nil {
                    return true
                }
            } catch {
                continue
            }
        }
        return false
    }

    private static func quantizationBits(in config: [String: Any]) -> Int? {
        if let quantization = config["quantization"] as? [String: Any],
            let bits = quantization["bits"] as? Int
        {
            return bits
        }

        if let quantization = config["quantization_config"] as? [String: Any],
            let bits = quantization["bits"] as? Int
        {
            return bits
        }

        if let textConfig = config["text_config"] as? [String: Any],
            let quantization = textConfig["quantization"] as? [String: Any],
            let bits = quantization["bits"] as? Int
        {
            return bits
        }

        return nil
    }

    private static func parameterFamily(
        for modelID: String,
        architecture: Qwen35ArchitectureFamily
    ) -> Qwen35ParameterFamily? {
        let normalized = modelID.lowercased()

        switch architecture {
        case .dense:
            if normalized.contains("0.8b") || normalized.contains("2b") || normalized.contains("4b") {
                return .denseSmall
            }
            if normalized.contains("9b") {
                return .denseMid
            }
            if normalized.contains("27b") || normalized.contains("397b") {
                return .denseLarge
            }
        case .moe:
            if normalized.contains("35b-a3b") {
                return .moeMedium
            }
            if normalized.contains("122b-a10b") || normalized.contains("397b-a17b") {
                return .moeLarge
            }
        }

        return nil
    }

    private static func firstSafetensorsMetadata(in directory: URL) throws -> [String: String] {
        let fileManager = FileManager.default
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
            .filter { $0.pathExtension == "safetensors" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard let firstFile = urls.first else {
            return [:]
        }

        let handle = try FileHandle(forReadingFrom: firstFile)
        defer {
            do {
                try handle.close()
            } catch {
            }
        }

        guard let lengthData = try handle.read(upToCount: 8), lengthData.count == 8 else {
            return [:]
        }

        let headerLength = lengthData.withUnsafeBytes { rawBuffer in
            rawBuffer.load(as: UInt64.self).littleEndian
        }

        guard headerLength > 0, headerLength < 32 * 1024 * 1024 else {
            return [:]
        }

        guard let headerData = try handle.read(upToCount: Int(headerLength)),
            headerData.count == Int(headerLength)
        else {
            return [:]
        }

        let object = try JSONSerialization.jsonObject(with: headerData)
        guard let dictionary = object as? [String: Any] else {
            return [:]
        }
        guard let metadataObject = dictionary["__metadata__"] as? [String: Any] else {
            return [:]
        }

        var metadata = [String: String]()
        for (key, value) in metadataObject {
            metadata[key] = String(describing: value)
        }
        return metadata
    }
}

private extension Qwen35Inspection {
    var metadataText: String {
        metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n")
    }
}
#endif
