#if MLX_ENABLED
import Foundation
import Testing
@testable import MLXFoundationModels

@Suite("Qwen3.5 Compatibility Tests")
struct Qwen35CompatibilityTests {

    @Test("Classifies dense text 4bit Qwen3.5 as standard MLX LLM")
    func classifyDenseText4Bit() throws {
        let directory = try fixtureDirectory(named: "qwen35-text-4bit")
        guard let variant = try Qwen35VariantClassifier.classify(
            modelID: "mlx-community/Qwen3.5-9B-4bit",
            in: directory
        ) else {
            Issue.record("Expected Qwen3.5 dense text variant to be classified.")
            return
        }

        #expect(variant.architecture == .dense)
        #expect(variant.modality == .text)
        #expect(variant.runtime == .llm)
        #expect(variant.quantization == .standardMLX(bits: 4))
        #expect(variant.supportVerdict == .supported)
    }

    @Test("Classifies conditional generation bf16 Qwen3.5 as VLM runtime")
    func classifyConditionalGenerationBF16() throws {
        let directory = try fixtureDirectory(named: "qwen35-vlm-bf16")
        guard let variant = try Qwen35VariantClassifier.classify(
            modelID: "mlx-community/Qwen3.5-4B-MLX-bf16",
            in: directory
        ) else {
            Issue.record("Expected Qwen3.5 conditional-generation variant to be classified.")
            return
        }

        #expect(variant.architecture == .dense)
        #expect(variant.modality == .conditionalGeneration)
        #expect(variant.runtime == .vlm)
        #expect(variant.quantization == .bf16)
        #expect(variant.supportVerdict == .supported)
    }

    @Test("Classifies MoE 6bit Qwen3.5 as standard MLX")
    func classifyMoE6Bit() throws {
        let directory = try fixtureDirectory(named: "qwen35-moe-6bit")
        guard let variant = try Qwen35VariantClassifier.classify(
            modelID: "mlx-community/Qwen3.5-35B-A3B-6bit",
            in: directory
        ) else {
            Issue.record("Expected Qwen3.5 MoE variant to be classified.")
            return
        }

        #expect(variant.architecture == .moe)
        #expect(variant.modality == .text)
        #expect(variant.runtime == .llm)
        #expect(variant.quantization == .standardMLX(bits: 6))
        #expect(variant.parameterFamily == .moeMedium)
        #expect(variant.supportVerdict == .supported)
    }

    @Test("Rejects unsupported custom quantization by config marker")
    func rejectCustomQuantizationByConfigMarker() throws {
        let directory = try fixtureDirectory(named: "qwen35-unsupported-awq")
        guard let variant = try Qwen35VariantClassifier.classify(
            modelID: "mlx-community/Qwen3.5-9B-AWQ",
            in: directory
        ) else {
            Issue.record("Expected unsupported Qwen3.5 variant to be classified.")
            return
        }

        #expect(variant.quantization == .unsupportedCustom("awq"))
        #expect(variant.supportVerdict == .unsupported(
            "Model 'mlx-community/Qwen3.5-9B-AWQ' uses unsupported custom quantization 'awq'. Only standard MLX Qwen3.5 bf16 and group-wise quantized variants are supported."
        ))
    }

    @Test("Rejects unsupported custom quantization by safetensors metadata marker")
    func rejectCustomQuantizationByMetadataMarker() throws {
        let directory = try temporaryFixtureCopy(named: "qwen35-text-4bit")
        try writeSafetensorsMetadata(
            at: directory.appendingPathComponent("weights.safetensors"),
            metadata: [
                "format": "mlx",
                "variant": "mxfp4",
            ]
        )

        guard let variant = try Qwen35VariantClassifier.classify(
            modelID: "local-qwen35",
            in: directory
        ) else {
            Issue.record("Expected safetensors metadata variant to be classified.")
            return
        }

        #expect(variant.quantization == .unsupportedCustom("mxfp"))
    }

    @Test("Support matrix contains unique representative model IDs")
    func uniqueRepresentativeModelIDs() {
        let ids = Qwen35SupportMatrix.representativeEntries.map(\.modelID)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Support matrix includes all required representative families")
    func matrixCoversRequiredFamilies() {
        let families = Set(Qwen35SupportMatrix.representativeEntries.map(\.parameterFamily))
        #expect(families.contains(.denseSmall))
        #expect(families.contains(.denseMid))
        #expect(families.contains(.denseLarge))
        #expect(families.contains(.moeMedium))
        #expect(families.contains(.moeLarge))
        #expect(
            Qwen35SupportMatrix.representativeEntries.contains { $0.modality == .conditionalGeneration })
    }

    @Test("ModelLoader fails fast for unsupported Qwen3.5 local variants")
    func modelLoaderFailsFastForUnsupportedLocalVariant() async throws {
        let directory = try temporaryFixtureCopy(named: "qwen35-unsupported-awq")
        let loader = ModelLoader(downloadBase: try temporaryDirectory())

        do {
            _ = try await loader.loadLocalModel(
                from: directory,
                modelID: "mlx-community/Qwen3.5-9B-AWQ"
            )
            Issue.record("Expected unsupported Qwen3.5 variant error")
        } catch let error as MLXModelLoadingError {
            switch error {
            case .unsupportedQwen35Variant(let modelID, let reason):
                #expect(modelID == "mlx-community/Qwen3.5-9B-AWQ")
                #expect(reason.contains("unsupported custom quantization 'awq'"))
            default:
                Issue.record("Unexpected MLXModelLoadingError: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

private func fixtureDirectory(named name: String) throws -> URL {
    guard let resourceURL = Bundle.module.resourceURL else {
        throw FixtureError.missingResourceBundle
    }
    return resourceURL.appendingPathComponent("Fixtures").appendingPathComponent(name)
}

private func temporaryFixtureCopy(named name: String) throws -> URL {
    let source = try fixtureDirectory(named: name)
    let destination = try temporaryDirectory().appendingPathComponent(name)
    let fileManager = FileManager.default

    if fileManager.fileExists(atPath: destination.path) {
        try fileManager.removeItem(at: destination)
    }
    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

    for item in try fileManager.contentsOfDirectory(
        at: source,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    ) {
        try fileManager.copyItem(at: item, to: destination.appendingPathComponent(item.lastPathComponent))
    }

    return destination
}

private func temporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("qwen35-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func writeSafetensorsMetadata(at url: URL, metadata: [String: String]) throws {
    let headerObject: [String: Any] = [
        "__metadata__": metadata,
        "weight": [
            "dtype": "F16",
            "shape": [1],
            "data_offsets": [0, 2],
        ],
    ]
    let headerData = try JSONSerialization.data(withJSONObject: headerObject, options: [])
    var length = UInt64(headerData.count).littleEndian
    let lengthData = Data(bytes: &length, count: MemoryLayout<UInt64>.size)

    var fileData = Data()
    fileData.append(lengthData)
    fileData.append(headerData)
    fileData.append(Data([0, 0]))

    try fileData.write(to: url)
}

private enum FixtureError: Error {
    case missingResourceBundle
}
#endif
