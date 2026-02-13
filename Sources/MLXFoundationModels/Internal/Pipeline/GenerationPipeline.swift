#if MLX_ENABLED
import Foundation
import MLXLMCommon

struct GenerationPipeline: Sendable {

    let executor: MLXExecutor

    init(executor: MLXExecutor) {
        self.executor = executor
    }

    func run(
        prompt: String,
        parameters: GenerateParameters,
        stopTokens: Set<String>
    ) async throws -> String {
        // Execute generation
        do {
            var raw = ""
            let stream = await executor.executeStream(
                prompt: prompt,
                parameters: parameters,
                logitProcessor: nil
            )

            for try await chunk in stream {
                raw += chunk

                // Check for stop tokens
                if !stopTokens.isEmpty {
                    for stopToken in stopTokens {
                        if raw.contains(stopToken) {
                            Logger.info("[GenerationPipeline] Stop token detected: \(stopToken)")
                            // Truncate at stop token if needed (keep the stop token for parsing)
                            break
                        }
                    }
                    // If we found any stop token, break out of the loop
                    if stopTokens.contains(where: { raw.contains($0) }) {
                        break
                    }
                }
            }

            // Log the generated output
            Logger.info("[GenerationPipeline] Generated output (\(raw.count) characters):")
            Logger.info("========== START OUTPUT ==========")
            Logger.info(raw)
            Logger.info("========== END OUTPUT ==========")

            return raw

        } catch {
            throw error
        }
    }

    func stream(
        prompt: String,
        parameters: GenerateParameters,
        stopTokens: Set<String>
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let baseStream = await executor.executeStream(
                        prompt: prompt,
                        parameters: parameters,
                        logitProcessor: nil
                    )

                    var buffer = ""

                    for try await chunk in baseStream {
                        buffer += chunk
                        continuation.yield(chunk)

                        // Check for stop tokens
                        if !stopTokens.isEmpty {
                            if stopTokens.contains(where: { buffer.contains($0) }) {
                                Logger.info("[GenerationPipeline] Stream: Stop token detected")
                                break
                            }
                        }
                    }

                    continuation.finish()

                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

#endif
