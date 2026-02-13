#if RESPONSE_ENABLED
import Testing
import Foundation
@testable import ResponseFoundationModels
import OpenFoundationModels
import OpenFoundationModelsExtra

@Suite("TranscriptConverter Tests")
struct TranscriptConverterTests {

    // MARK: - buildInputItems: Basic Entry Conversion

    @Test("Instructions entry converts to system message")
    func buildInputItems_instructions() throws {
        let transcript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                segments: [.text(Transcript.TextSegment(content: "You are helpful"))],
                toolDefinitions: []
            ))
        ])

        let items = TranscriptConverter.buildInputItems(from: transcript)
        #expect(items.count == 1)
        guard case .message(let msg) = items[0] else {
            Issue.record("Expected message item")
            return
        }
        #expect(msg.role == "system")
        #expect(msg.content == "You are helpful")
    }

    @Test("Prompt entry converts to user message")
    func buildInputItems_prompt() throws {
        let transcript = Transcript(entries: [
            .prompt(Transcript.Prompt(
                segments: [.text(Transcript.TextSegment(content: "Hello"))],
                options: GenerationOptions(),
                responseFormat: nil
            ))
        ])

        let items = TranscriptConverter.buildInputItems(from: transcript)
        #expect(items.count == 1)
        guard case .message(let msg) = items[0] else {
            Issue.record("Expected message item")
            return
        }
        #expect(msg.role == "user")
        #expect(msg.content == "Hello")
    }

    @Test("Response entry converts to assistant message")
    func buildInputItems_response() throws {
        let transcript = Transcript(entries: [
            .response(Transcript.Response(
                assetIDs: [],
                segments: [.text(Transcript.TextSegment(content: "Hi there"))]
            ))
        ])

        let items = TranscriptConverter.buildInputItems(from: transcript)
        #expect(items.count == 1)
        guard case .message(let msg) = items[0] else {
            Issue.record("Expected message item")
            return
        }
        #expect(msg.role == "assistant")
        #expect(msg.content == "Hi there")
    }

    @Test("Empty transcript produces empty items")
    func buildInputItems_empty() {
        let transcript = Transcript(entries: [])
        let items = TranscriptConverter.buildInputItems(from: transcript)
        #expect(items.isEmpty)
    }

    @Test("Full conversation produces correct sequence")
    func buildInputItems_fullConversation() throws {
        let transcript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                segments: [.text(Transcript.TextSegment(content: "Be helpful"))],
                toolDefinitions: []
            )),
            .prompt(Transcript.Prompt(
                segments: [.text(Transcript.TextSegment(content: "Hi"))],
                options: GenerationOptions(),
                responseFormat: nil
            )),
            .response(Transcript.Response(
                assetIDs: [],
                segments: [.text(Transcript.TextSegment(content: "Hello!"))]
            )),
            .prompt(Transcript.Prompt(
                segments: [.text(Transcript.TextSegment(content: "How are you?"))],
                options: GenerationOptions(),
                responseFormat: nil
            )),
        ])

        let items = TranscriptConverter.buildInputItems(from: transcript)
        #expect(items.count == 4)

        guard case .message(let m0) = items[0] else { Issue.record("Expected message at 0"); return }
        #expect(m0.role == "system")

        guard case .message(let m1) = items[1] else { Issue.record("Expected message at 1"); return }
        #expect(m1.role == "user")
        #expect(m1.content == "Hi")

        guard case .message(let m2) = items[2] else { Issue.record("Expected message at 2"); return }
        #expect(m2.role == "assistant")
        #expect(m2.content == "Hello!")

        guard case .message(let m3) = items[3] else { Issue.record("Expected message at 3"); return }
        #expect(m3.role == "user")
        #expect(m3.content == "How are you?")
    }

    @Test("Multiple text segments are joined with space")
    func buildInputItems_multipleTextSegments() throws {
        let transcript = Transcript(entries: [
            .prompt(Transcript.Prompt(
                segments: [
                    .text(Transcript.TextSegment(content: "Hello")),
                    .text(Transcript.TextSegment(content: "World")),
                ],
                options: GenerationOptions(),
                responseFormat: nil
            ))
        ])

        let items = TranscriptConverter.buildInputItems(from: transcript)
        #expect(items.count == 1)
        guard case .message(let msg) = items[0] else { Issue.record("Expected message"); return }
        #expect(msg.content == "Hello World")
    }

    // MARK: - buildInputItems: Tool Call Conversion

    @Test("ToolCalls entry converts to function call items")
    func buildInputItems_toolCalls() throws {
        let toolCall = Transcript.ToolCall(
            id: "tc-001",
            toolName: "search",
            arguments: GeneratedContent(properties: ["query": "swift"])
        )
        let transcript = Transcript(entries: [
            .toolCalls(Transcript.ToolCalls(id: UUID().uuidString, [toolCall]))
        ])

        let items = TranscriptConverter.buildInputItems(from: transcript)
        #expect(items.count == 1)
        guard case .functionCall(let fc) = items[0] else {
            Issue.record("Expected functionCall item")
            return
        }
        #expect(fc.name == "search")
        #expect(fc.callId == "tc-001")
    }

    @Test("ToolOutput uses pending tool call ID (FIFO matching)")
    func buildInputItems_toolOutputMatchesPendingCallId() throws {
        let toolCall = Transcript.ToolCall(
            id: "tc-original",
            toolName: "search",
            arguments: GeneratedContent(properties: ["q": "test"])
        )
        let toolOutput = Transcript.ToolOutput(
            id: "random-uuid-from-session",
            toolName: "search",
            segments: [.text(Transcript.TextSegment(content: "result"))]
        )

        let transcript = Transcript(entries: [
            .toolCalls(Transcript.ToolCalls(id: UUID().uuidString, [toolCall])),
            .toolOutput(toolOutput),
        ])

        let items = TranscriptConverter.buildInputItems(from: transcript)
        #expect(items.count == 2)

        guard case .functionCallOutput(let output) = items[1] else {
            Issue.record("Expected functionCallOutput at index 1")
            return
        }
        // The output should use the original tool call ID, not the random UUID
        #expect(output.callId == "tc-original")
        #expect(output.output == "result")
    }

    @Test("Multiple tool outputs match pending call IDs in FIFO order")
    func buildInputItems_multipleToolOutputsFIFO() throws {
        let call1 = Transcript.ToolCall(
            id: "call-A",
            toolName: "tool1",
            arguments: GeneratedContent(properties: ["x": "1"])
        )
        let call2 = Transcript.ToolCall(
            id: "call-B",
            toolName: "tool2",
            arguments: GeneratedContent(properties: ["x": "2"])
        )
        let output1 = Transcript.ToolOutput(
            id: "random-1",
            toolName: "tool1",
            segments: [.text(Transcript.TextSegment(content: "result1"))]
        )
        let output2 = Transcript.ToolOutput(
            id: "random-2",
            toolName: "tool2",
            segments: [.text(Transcript.TextSegment(content: "result2"))]
        )

        let transcript = Transcript(entries: [
            .toolCalls(Transcript.ToolCalls(id: UUID().uuidString, [call1, call2])),
            .toolOutput(output1),
            .toolOutput(output2),
        ])

        let items = TranscriptConverter.buildInputItems(from: transcript)
        // 2 function calls + 2 function call outputs = 4
        #expect(items.count == 4)

        guard case .functionCallOutput(let out1) = items[2] else {
            Issue.record("Expected functionCallOutput at index 2")
            return
        }
        #expect(out1.callId == "call-A")

        guard case .functionCallOutput(let out2) = items[3] else {
            Issue.record("Expected functionCallOutput at index 3")
            return
        }
        #expect(out2.callId == "call-B")
    }

    @Test("ToolOutput falls back to own ID when no pending calls")
    func buildInputItems_toolOutputFallbackToOwnId() throws {
        let toolOutput = Transcript.ToolOutput(
            id: "own-id",
            toolName: "search",
            segments: [.text(Transcript.TextSegment(content: "result"))]
        )

        let transcript = Transcript(entries: [
            .toolOutput(toolOutput),
        ])

        let items = TranscriptConverter.buildInputItems(from: transcript)
        #expect(items.count == 1)
        guard case .functionCallOutput(let out) = items[0] else {
            Issue.record("Expected functionCallOutput")
            return
        }
        #expect(out.callId == "own-id")
    }

    // MARK: - extractToolDefinitions

    @Test("Extract tool definitions from instructions")
    func extractToolDefinitions_fromInstructions() throws {
        let schema = GenerationSchema(
            type: String.self,
            description: "A query string",
            properties: []
        )
        let toolDef = Transcript.ToolDefinition(
            name: "search",
            description: "Search the web",
            parameters: schema
        )
        let transcript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                segments: [.text(Transcript.TextSegment(content: "instructions"))],
                toolDefinitions: [toolDef]
            ))
        ])

        let definitions = TranscriptConverter.extractToolDefinitions(from: transcript)
        let defs = try #require(definitions)
        #expect(defs.count == 1)
        #expect(defs[0].name == "search")
        #expect(defs[0].description == "Search the web")
    }

    @Test("Extract tool definitions returns nil for empty transcript")
    func extractToolDefinitions_empty() {
        let transcript = Transcript(entries: [])
        let definitions = TranscriptConverter.extractToolDefinitions(from: transcript)
        #expect(definitions == nil)
    }

    @Test("Extract tool definitions returns nil when no tools defined")
    func extractToolDefinitions_noTools() {
        let transcript = Transcript(entries: [
            .instructions(Transcript.Instructions(
                segments: [.text(Transcript.TextSegment(content: "instructions"))],
                toolDefinitions: []
            ))
        ])
        let definitions = TranscriptConverter.extractToolDefinitions(from: transcript)
        #expect(definitions == nil)
    }

    // MARK: - extractOptions

    @Test("Extract options from last prompt")
    func extractOptions_fromLastPrompt() throws {
        let options1 = GenerationOptions(temperature: 0.5, maximumResponseTokens: 100)
        let options2 = GenerationOptions(temperature: 0.9, maximumResponseTokens: 500)

        let transcript = Transcript(entries: [
            .prompt(Transcript.Prompt(
                segments: [.text(Transcript.TextSegment(content: "First"))],
                options: options1,
                responseFormat: nil
            )),
            .prompt(Transcript.Prompt(
                segments: [.text(Transcript.TextSegment(content: "Second"))],
                options: options2,
                responseFormat: nil
            )),
        ])

        let extracted = TranscriptConverter.extractOptions(from: transcript)
        let opts = try #require(extracted)
        #expect(opts.temperature == 0.9)
        #expect(opts.maximumResponseTokens == 500)
    }

    @Test("Extract options returns nil when no prompts")
    func extractOptions_noPrompts() {
        let transcript = Transcript(entries: [
            .response(Transcript.Response(
                assetIDs: [],
                segments: [.text(Transcript.TextSegment(content: "text"))]
            ))
        ])
        let extracted = TranscriptConverter.extractOptions(from: transcript)
        #expect(extracted == nil)
    }

    // MARK: - extractResponseFormat

    @Test("Extract response format returns nil when no format set")
    func extractResponseFormat_noFormat() {
        let transcript = Transcript(entries: [
            .prompt(Transcript.Prompt(
                segments: [.text(Transcript.TextSegment(content: "text"))],
                options: GenerationOptions(),
                responseFormat: nil
            ))
        ])
        let format = TranscriptConverter.extractResponseFormat(from: transcript)
        #expect(format == nil)
    }

    @Test("Extract response format from prompt with type")
    func extractResponseFormat_withType() throws {
        let responseFormat = Transcript.ResponseFormat(type: String.self)
        let transcript = Transcript(entries: [
            .prompt(Transcript.Prompt(
                segments: [.text(Transcript.TextSegment(content: "text"))],
                options: GenerationOptions(),
                responseFormat: responseFormat
            ))
        ])
        let format = TranscriptConverter.extractResponseFormat(from: transcript)
        // Should return a TextFormat (either jsonSchema or jsonObject)
        #expect(format != nil)
    }
}

#endif
