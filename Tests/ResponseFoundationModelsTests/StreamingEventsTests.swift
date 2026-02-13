#if RESPONSE_ENABLED
import Testing
import Foundation
@testable import ResponseFoundationModels

@Suite("StreamingEvents Tests")
struct StreamingEventsTests {

    // MARK: - Helpers

    private func makeEvent(_ type: StreamingEventType, _ json: [String: Any]) throws -> StreamingEvent {
        let data = try JSONSerialization.data(withJSONObject: json)
        return StreamingEvent(type: type, rawData: data)
    }

    // MARK: - Computed Properties

    @Test("textDelta extracts delta field")
    func textDelta() throws {
        let event = try makeEvent(.outputTextDelta, ["delta": "Hello"])
        #expect(event.textDelta == "Hello")
    }

    @Test("completedText extracts text field")
    func completedText() throws {
        let event = try makeEvent(.outputTextDone, ["text": "Complete"])
        #expect(event.completedText == "Complete")
    }

    @Test("argumentsDelta extracts delta field")
    func argumentsDelta() throws {
        let event = try makeEvent(.functionCallArgumentsDelta, ["delta": "{\"q\""])
        #expect(event.argumentsDelta == "{\"q\"")
    }

    @Test("completedArguments extracts arguments field")
    func completedArguments() throws {
        let event = try makeEvent(.functionCallArgumentsDone, ["arguments": "{\"q\":\"swift\"}"])
        #expect(event.completedArguments == "{\"q\":\"swift\"}")
    }

    @Test("functionName extracts name field")
    func functionName() throws {
        let event = try makeEvent(.functionCallArgumentsDone, ["name": "search"])
        #expect(event.functionName == "search")
    }

    @Test("itemId extracts item_id field")
    func itemId() throws {
        let event = try makeEvent(.functionCallArgumentsDelta, ["item_id": "item-1"])
        #expect(event.itemId == "item-1")
    }

    @Test("outputIndex extracts output_index field")
    func outputIndex() throws {
        let event = try makeEvent(.outputItemAdded, ["output_index": 0])
        #expect(event.outputIndex == 0)
    }

    @Test("outputItem extracts item dictionary")
    func outputItem() throws {
        let event = try makeEvent(.outputItemAdded, [
            "item": ["type": "function_call", "id": "fc-1"] as [String: Any]
        ])
        let item = try #require(event.outputItem)
        #expect(item["type"] as? String == "function_call")
        #expect(item["id"] as? String == "fc-1")
    }

    @Test("errorMessage extracts message field")
    func errorMessage() throws {
        let event = try makeEvent(.error, ["message": "Rate limited"])
        #expect(event.errorMessage == "Rate limited")
    }

    @Test("errorCode extracts code field")
    func errorCode() throws {
        let event = try makeEvent(.error, ["code": "rate_limit_exceeded"])
        #expect(event.errorCode == "rate_limit_exceeded")
    }

    @Test("Invalid JSON data returns nil for all properties")
    func invalidJSON_returnsNil() {
        let event = StreamingEvent(type: .outputTextDelta, rawData: Data("not json".utf8))
        #expect(event.textDelta == nil)
        #expect(event.completedText == nil)
        #expect(event.argumentsDelta == nil)
        #expect(event.completedArguments == nil)
        #expect(event.functionName == nil)
        #expect(event.itemId == nil)
        #expect(event.outputIndex == nil)
        #expect(event.outputItem == nil)
        #expect(event.errorMessage == nil)
        #expect(event.errorCode == nil)
    }
}

#endif
