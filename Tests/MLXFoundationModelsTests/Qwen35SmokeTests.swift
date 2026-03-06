#if MLX_ENABLED
import Foundation
@preconcurrency import MLXLMCommon
import Testing
@testable import MLXFoundationModels

@Suite("Qwen3.5 Smoke Tests")
struct Qwen35SmokeTests {

    @Test("Representative Qwen3.5 models load, prepare, and generate")
    func representativeSmokeMatrix() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["QWEN35_SMOKE"] == "1" else {
            return
        }

        let includeLarge = environment["QWEN35_SMOKE_LARGE"] == "1"
        let selectedIDs = selectedModelIDs(from: environment)
        let entries = Qwen35SupportMatrix.representativeEntries.filter { entry in
            if let selectedIDs {
                return selectedIDs.contains(entry.modelID)
            }
            if entry.requiresLargeMemory && !includeLarge {
                return false
            }
            return entry.smokeEligible
        }

        for entry in entries {
            try await smoke(entry: entry)
        }
    }

    private func smoke(entry: Qwen35SupportMatrixEntry) async throws {
        let loader = ModelLoader(downloadBase: try smokeDownloadBase())
        let timeout = entry.requiresLargeMemory ? 600.0 : 240.0

        let startedAt = Date()
        let container = try await loader.loadModel(entry.modelID)

        let input = UserInput(prompt: "Reply with one short sentence.")
        let prepared = try await container.prepare(input: input)

        let stream = try await container.generate(
            input: prepared,
            parameters: GenerateParameters(
                maxTokens: 16,
                temperature: 0,
                prefillStepSize: 256
            )
        )

        var generated = ""
        for await generation in stream {
            switch generation {
            case .chunk(let text):
                generated += text
            case .info, .toolCall:
                break
            }
        }

        #expect(!generated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(Date().timeIntervalSince(startedAt) < timeout)
    }
}

private func selectedModelIDs(from environment: [String: String]) -> Set<String>? {
    guard let raw = environment["QWEN35_SMOKE_IDS"] else {
        return nil
    }

    let ids = raw
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    return Set(ids)
}

private func smokeDownloadBase() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("qwen35-smoke-cache", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
#endif
