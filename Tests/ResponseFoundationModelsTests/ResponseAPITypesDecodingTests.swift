#if RESPONSE_ENABLED
import Testing
import Foundation
@testable import ResponseFoundationModels

@Suite("Response API Types Decoding Tests")
struct ResponseAPITypesDecodingTests {

    // MARK: - Helpers

    private func decode<T: Decodable>(_ type: T.Type, from json: [String: Any]) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(type, from: data)
    }

    // MARK: - ResponseObject

    @Test("ResponseObject minimal decoding")
    func responseObject_minimal() throws {
        let obj = try decode(ResponseObject.self, from: [
            "id": "resp-1",
            "object": "response",
            "output": [] as [[String: Any]],
        ])
        #expect(obj.id == "resp-1")
        #expect(obj.object == "response")
        #expect(obj.output.isEmpty)
        #expect(obj.usage == nil)
    }

    @Test("ResponseObject with usage")
    func responseObject_withUsage() throws {
        let obj = try decode(ResponseObject.self, from: [
            "id": "resp-1",
            "object": "response",
            "output": [] as [[String: Any]],
            "usage": [
                "input_tokens": 100,
                "output_tokens": 50,
                "total_tokens": 150,
            ] as [String: Any],
        ])
        let usage = try #require(obj.usage)
        #expect(usage.inputTokens == 100)
        #expect(usage.outputTokens == 50)
        #expect(usage.totalTokens == 150)
    }

    // MARK: - OutputItem

    @Test("OutputItem decodes message type")
    func outputItem_message() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "type": "message",
            "role": "assistant",
            "content": [["type": "output_text", "text": "Hello"]],
        ] as [String: Any])

        let item = try JSONDecoder().decode(OutputItem.self, from: data)
        guard case .message(let msg) = item else {
            Issue.record("Expected message")
            return
        }
        #expect(msg.role == "assistant")
        let text = msg.content?.first?.text
        #expect(text == "Hello")
    }

    @Test("OutputItem decodes function_call type")
    func outputItem_functionCall() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "type": "function_call",
            "id": "fc-1",
            "call_id": "call-1",
            "name": "search",
            "arguments": "{\"q\":\"swift\"}",
            "status": "completed",
        ] as [String: Any])

        let item = try JSONDecoder().decode(OutputItem.self, from: data)
        guard case .functionCall(let fc) = item else {
            Issue.record("Expected functionCall")
            return
        }
        #expect(fc.callId == "call-1")
        #expect(fc.name == "search")
        #expect(fc.arguments == "{\"q\":\"swift\"}")
    }

    @Test("OutputItem unknown type decodes as message")
    func outputItem_unknownType() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "type": "unknown_type",
            "role": "assistant",
        ] as [String: Any])

        let item = try JSONDecoder().decode(OutputItem.self, from: data)
        guard case .message = item else {
            Issue.record("Expected message fallback")
            return
        }
    }

    // MARK: - StreamingEventType

    @Test("StreamingEventType raw values match API strings")
    func streamingEventType_rawValues() {
        #expect(StreamingEventType.responseCreated.rawValue == "response.created")
        #expect(StreamingEventType.responseCompleted.rawValue == "response.completed")
        #expect(StreamingEventType.responseFailed.rawValue == "response.failed")
        #expect(StreamingEventType.outputTextDelta.rawValue == "response.output_text.delta")
        #expect(StreamingEventType.outputTextDone.rawValue == "response.output_text.done")
        #expect(StreamingEventType.functionCallArgumentsDelta.rawValue == "response.function_call_arguments.delta")
        #expect(StreamingEventType.functionCallArgumentsDone.rawValue == "response.function_call_arguments.done")
        #expect(StreamingEventType.outputItemAdded.rawValue == "response.output_item.added")
        #expect(StreamingEventType.error.rawValue == "error")
    }

    @Test("StreamingEventType invalid raw value returns nil")
    func streamingEventType_invalid() {
        let result = StreamingEventType(rawValue: "invalid.event.type")
        #expect(result == nil)
    }
}

#endif
