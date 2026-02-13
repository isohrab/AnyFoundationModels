#if MLX_ENABLED
import Foundation
import OpenFoundationModels

/// Responsible only for decoding raw generated text into transcript entries.
public protocol ResponseDecoder: Sendable {
    func decode(raw: String, options: GenerationOptions?) -> Transcript.Entry

    func decode(
        stream chunks: AsyncThrowingStream<String, Error>,
        options: GenerationOptions?
    ) -> AsyncThrowingStream<Transcript.Entry, Error>
}

extension ResponseDecoder {
    public func decode(raw: String, options: GenerationOptions?) -> Transcript.Entry {
        .response(.init(assetIDs: [], segments: [.text(.init(content: raw))]))
    }

    public func decode(
        stream chunks: AsyncThrowingStream<String, Error>,
        options: GenerationOptions?
    ) -> AsyncThrowingStream<Transcript.Entry, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await chunk in chunks {
                        continuation.yield(.response(.init(
                            assetIDs: [],
                            segments: [.text(.init(content: chunk))]
                        )))
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
