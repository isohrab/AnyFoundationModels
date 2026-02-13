#if CLAUDE_ENABLED
import Foundation
import Synchronization

/// Manages pending thinking blocks for tool-use conversations with extended thinking.
///
/// Claude API requires that thinking blocks from an assistant response containing tool_use
/// be included unmodified in the subsequent request's assistant message.
internal final class ThinkingBlockManager: Sendable {

    private let pendingBlocks = Mutex<[ResponseContentBlock]>([])

    /// Atomically take and clear all pending thinking blocks.
    func take() -> [ResponseContentBlock] {
        pendingBlocks.withLock { blocks in
            let result = blocks
            blocks = []
            return result
        }
    }

    /// Store thinking and redacted thinking blocks from a response.
    func store(from content: [ResponseContentBlock]) {
        let thinkingBlocks = content.filter { block in
            switch block {
            case .thinking, .redactedThinking:
                return true
            default:
                return false
            }
        }
        if !thinkingBlocks.isEmpty {
            pendingBlocks.withLock { $0 = thinkingBlocks }
        }
    }

    /// Store thinking blocks directly (for streaming).
    func store(_ blocks: [ResponseContentBlock]) {
        pendingBlocks.withLock { $0 = blocks }
    }

    /// Inject thinking blocks into the last assistant message.
    /// Thinking blocks are prepended before any text or tool_use blocks.
    static func inject(
        _ thinkingBlocks: [ResponseContentBlock],
        into messages: [Message]
    ) -> [Message] {
        var messages = messages
        guard let lastAssistantIndex = messages.lastIndex(where: { $0.role == .assistant }) else {
            return messages
        }

        let thinkingContentBlocks: [ContentBlock] = thinkingBlocks.compactMap { block in
            switch block {
            case .thinking(let thinkingBlock):
                return .thinking(thinkingBlock)
            case .redactedThinking(let redactedBlock):
                return .redactedThinking(redactedBlock)
            default:
                return nil
            }
        }

        let existingBlocks: [ContentBlock]
        switch messages[lastAssistantIndex].content {
        case .text(let text):
            existingBlocks = [.text(TextBlock(text: text))]
        case .blocks(let blocks):
            existingBlocks = blocks
        }

        let mergedBlocks = thinkingContentBlocks + existingBlocks
        messages[lastAssistantIndex] = Message(role: .assistant, content: mergedBlocks)

        return messages
    }
}

#endif
