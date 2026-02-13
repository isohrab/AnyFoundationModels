#if CLAUDE_ENABLED
import Foundation

/// Chat message for Claude API
struct Message: Codable, Sendable {
    let role: Role
    let content: MessageContent

    init(role: Role, content: String) {
        self.role = role
        self.content = .text(content)
    }

    init(role: Role, content: [ContentBlock]) {
        self.role = role
        self.content = .blocks(content)
    }

    enum CodingKeys: String, CodingKey {
        case role, content
    }

    // Decoder union pattern: try? is the only way to probe decode types.
    // This is an accepted exception to the no-try? rule.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.role = try container.decode(Role.self, forKey: .role)

        if let text = try? container.decode(String.self, forKey: .content) {
            self.content = .text(text)
        } else if let blocks = try? container.decode([ContentBlock].self, forKey: .content) {
            self.content = .blocks(blocks)
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .content,
                in: container,
                debugDescription: "Content must be either a string or an array of content blocks"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)

        switch content {
        case .text(let text):
            try container.encode(text, forKey: .content)
        case .blocks(let blocks):
            try container.encode(blocks, forKey: .content)
        }
    }
}

/// Message content can be either text or array of content blocks
enum MessageContent: Sendable {
    case text(String)
    case blocks([ContentBlock])
}

/// Message role
enum Role: String, Codable, Sendable {
    case user
    case assistant
}

#endif
