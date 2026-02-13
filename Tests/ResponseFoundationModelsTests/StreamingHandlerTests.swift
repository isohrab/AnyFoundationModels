#if RESPONSE_ENABLED
import Testing
import Foundation
@testable import ResponseFoundationModels
import OpenFoundationModels

@Suite("StreamingHandler Tests")
struct StreamingHandlerTests {

    // MARK: - Helpers

    private func makeEvent(_ type: StreamingEventType, _ json: [String: Any] = [:]) throws -> StreamingEvent {
        let data = try JSONSerialization.data(withJSONObject: json)
        return StreamingEvent(type: type, rawData: data)
    }

    // MARK: - Initial State

    @Test("Fresh state has correct initial values")
    func initialState() {
        let state = StreamingHandler.StreamState()
        #expect(state.textContent == "")
        #expect(state.functionCalls.isEmpty)
        #expect(state.isComplete == false)
    }

    // MARK: - Text Streaming

    @Test("outputTextDelta yields response with delta text")
    func outputTextDelta_yieldsResponse() throws {
        var state = StreamingHandler.StreamState()
        let event = try makeEvent(.outputTextDelta, ["delta": "Hello"])

        let entry = StreamingHandler.processEvent(event, state: &state)
        let result = try #require(entry)
        guard case .response(let resp) = result else {
            Issue.record("Expected response entry")
            return
        }
        let text = resp.segments.compactMap { seg -> String? in
            if case .text(let t) = seg { return t.content }
            return nil
        }.joined()
        #expect(text == "Hello")
    }

    @Test("outputTextDelta accumulates in state")
    func outputTextDelta_accumulates() throws {
        var state = StreamingHandler.StreamState()
        let event1 = try makeEvent(.outputTextDelta, ["delta": "Hello"])
        let event2 = try makeEvent(.outputTextDelta, ["delta": " World"])

        _ = StreamingHandler.processEvent(event1, state: &state)
        _ = StreamingHandler.processEvent(event2, state: &state)

        #expect(state.textContent == "Hello World")
    }

    @Test("outputTextDelta with no delta returns nil")
    func outputTextDelta_noDelta() throws {
        var state = StreamingHandler.StreamState()
        let event = try makeEvent(.outputTextDelta, ["not_delta": "data"])

        let entry = StreamingHandler.processEvent(event, state: &state)
        #expect(entry == nil)
    }

    @Test("outputTextDone updates state text, returns nil")
    func outputTextDone_updatesState() throws {
        var state = StreamingHandler.StreamState()
        state.textContent = "partial"
        let event = try makeEvent(.outputTextDone, ["text": "Complete text"])

        let entry = StreamingHandler.processEvent(event, state: &state)
        #expect(entry == nil)
        #expect(state.textContent == "Complete text")
    }

    // MARK: - Function Call Streaming

    @Test("outputItemAdded for function_call creates state entry")
    func outputItemAdded_functionCall() throws {
        var state = StreamingHandler.StreamState()
        let event = try makeEvent(.outputItemAdded, [
            "item": [
                "type": "function_call",
                "id": "item-1",
                "call_id": "call-1",
                "name": "search",
            ] as [String: Any]
        ])

        let entry = StreamingHandler.processEvent(event, state: &state)
        #expect(entry == nil)
        let fcState = try #require(state.functionCalls["item-1"])
        #expect(fcState.callId == "call-1")
        #expect(fcState.name == "search")
        #expect(fcState.arguments == "")
        #expect(fcState.isDone == false)
    }

    @Test("outputItemAdded for non-function_call is ignored")
    func outputItemAdded_message() throws {
        var state = StreamingHandler.StreamState()
        let event = try makeEvent(.outputItemAdded, [
            "item": [
                "type": "message",
                "id": "item-1",
            ] as [String: Any]
        ])

        let entry = StreamingHandler.processEvent(event, state: &state)
        #expect(entry == nil)
        #expect(state.functionCalls.isEmpty)
    }

    @Test("functionCallArgumentsDelta appends to arguments")
    func argumentsDelta_appends() throws {
        var state = StreamingHandler.StreamState()
        state.functionCalls["item-1"] = .init(callId: "call-1", name: "search", arguments: "{\"q")

        let event = try makeEvent(.functionCallArgumentsDelta, [
            "item_id": "item-1",
            "delta": "uery\":\"swift\"}",
        ])

        let entry = StreamingHandler.processEvent(event, state: &state)
        #expect(entry == nil)
        #expect(state.functionCalls["item-1"]?.arguments == "{\"query\":\"swift\"}")
    }

    @Test("functionCallArgumentsDelta with unknown item_id is no-op")
    func argumentsDelta_unknownItemId() throws {
        var state = StreamingHandler.StreamState()
        let event = try makeEvent(.functionCallArgumentsDelta, [
            "item_id": "unknown",
            "delta": "data",
        ])

        let entry = StreamingHandler.processEvent(event, state: &state)
        #expect(entry == nil)
    }

    @Test("functionCallArgumentsDone sets isDone and updates args")
    func argumentsDone_setsIsDone() throws {
        var state = StreamingHandler.StreamState()
        state.functionCalls["item-1"] = .init(callId: "call-1", name: "search", arguments: "partial")

        let event = try makeEvent(.functionCallArgumentsDone, [
            "item_id": "item-1",
            "arguments": "{\"query\":\"swift\"}",
            "name": "search_v2",
        ])

        let entry = StreamingHandler.processEvent(event, state: &state)
        #expect(entry == nil)
        let fc = try #require(state.functionCalls["item-1"])
        #expect(fc.isDone == true)
        #expect(fc.arguments == "{\"query\":\"swift\"}")
        #expect(fc.name == "search_v2")
    }

    // MARK: - Response Completion

    @Test("responseCompleted with no function calls sets isComplete, returns nil")
    func responseCompleted_noFunctionCalls() throws {
        var state = StreamingHandler.StreamState()
        let event = try makeEvent(.responseCompleted, [:])

        let entry = StreamingHandler.processEvent(event, state: &state)
        #expect(entry == nil)
        #expect(state.isComplete == true)
    }

    @Test("responseCompleted yields completed function calls as toolCalls")
    func responseCompleted_withFunctionCalls() throws {
        var state = StreamingHandler.StreamState()
        state.functionCalls["item-1"] = .init(callId: "call-1", name: "search", arguments: "{\"q\":\"swift\"}", isDone: true)
        let event = try makeEvent(.responseCompleted, [:])

        let entry = StreamingHandler.processEvent(event, state: &state)
        let result = try #require(entry)
        guard case .toolCalls(let calls) = result else {
            Issue.record("Expected toolCalls entry")
            return
        }
        let callList = calls._calls
        #expect(callList.count == 1)
        #expect(callList[0].toolName == "search")
        #expect(callList[0].id == "call-1")
        #expect(state.isComplete == true)
    }

    @Test("responseCompleted filters out incomplete function calls")
    func responseCompleted_filtersIncomplete() throws {
        var state = StreamingHandler.StreamState()
        state.functionCalls["item-1"] = .init(callId: "call-1", name: "done_tool", arguments: "{}", isDone: true)
        state.functionCalls["item-2"] = .init(callId: "call-2", name: "incomplete_tool", arguments: "", isDone: false)
        let event = try makeEvent(.responseCompleted, [:])

        let entry = StreamingHandler.processEvent(event, state: &state)
        let result = try #require(entry)
        guard case .toolCalls(let calls) = result else {
            Issue.record("Expected toolCalls entry")
            return
        }
        let callList = calls._calls
        #expect(callList.count == 1)
        #expect(callList[0].toolName == "done_tool")
    }

    @Test("responseFailed sets isComplete")
    func responseFailed_setsIsComplete() throws {
        var state = StreamingHandler.StreamState()
        let event = try makeEvent(.responseFailed, [:])

        let entry = StreamingHandler.processEvent(event, state: &state)
        #expect(entry == nil)
        #expect(state.isComplete == true)
    }

    @Test("error event sets isComplete")
    func error_setsIsComplete() throws {
        var state = StreamingHandler.StreamState()
        let event = try makeEvent(.error, ["message": "Rate limited"])

        let entry = StreamingHandler.processEvent(event, state: &state)
        #expect(entry == nil)
        #expect(state.isComplete == true)
    }

    // MARK: - State Machine Integration

    @Test("Full text streaming sequence")
    func fullTextStreamingSequence() throws {
        var state = StreamingHandler.StreamState()
        var yields: [Transcript.Entry] = []

        let events = [
            try makeEvent(.outputTextDelta, ["delta": "Hello"]),
            try makeEvent(.outputTextDelta, ["delta": " World"]),
            try makeEvent(.outputTextDone, ["text": "Hello World"]),
            try makeEvent(.responseCompleted, [:]),
        ]

        for event in events {
            if let entry = StreamingHandler.processEvent(event, state: &state) {
                yields.append(entry)
            }
        }

        // Two text deltas should yield two response entries
        #expect(yields.count == 2)
        #expect(state.isComplete == true)
        #expect(state.textContent == "Hello World")
    }

    @Test("Full function call streaming sequence")
    func fullFunctionCallSequence() throws {
        var state = StreamingHandler.StreamState()
        var yields: [Transcript.Entry] = []

        let events: [StreamingEvent] = [
            try makeEvent(.outputItemAdded, [
                "item": ["type": "function_call", "id": "item-1", "call_id": "call-1", "name": "search"] as [String: Any]
            ]),
            try makeEvent(.functionCallArgumentsDelta, ["item_id": "item-1", "delta": "{\"q\""]),
            try makeEvent(.functionCallArgumentsDelta, ["item_id": "item-1", "delta": ":\"swift\"}"]),
            try makeEvent(.functionCallArgumentsDone, [
                "item_id": "item-1",
                "arguments": "{\"q\":\"swift\"}",
            ]),
            try makeEvent(.responseCompleted, [:]),
        ]

        for event in events {
            if let entry = StreamingHandler.processEvent(event, state: &state) {
                yields.append(entry)
            }
        }

        // Only responseCompleted should yield toolCalls
        #expect(yields.count == 1)
        guard case .toolCalls(let calls) = yields[0] else {
            Issue.record("Expected toolCalls")
            return
        }
        #expect(calls._calls.count == 1)
        #expect(calls._calls[0].toolName == "search")
        #expect(state.isComplete == true)
    }

    @Test("Multiple function calls in single response")
    func multipleFunctionCalls() throws {
        var state = StreamingHandler.StreamState()
        var yields: [Transcript.Entry] = []

        let events: [StreamingEvent] = [
            try makeEvent(.outputItemAdded, [
                "item": ["type": "function_call", "id": "item-1", "call_id": "call-1", "name": "search"] as [String: Any]
            ]),
            try makeEvent(.functionCallArgumentsDone, ["item_id": "item-1", "arguments": "{}"]),
            try makeEvent(.outputItemAdded, [
                "item": ["type": "function_call", "id": "item-2", "call_id": "call-2", "name": "calculate"] as [String: Any]
            ]),
            try makeEvent(.functionCallArgumentsDone, ["item_id": "item-2", "arguments": "{}"]),
            try makeEvent(.responseCompleted, [:]),
        ]

        for event in events {
            if let entry = StreamingHandler.processEvent(event, state: &state) {
                yields.append(entry)
            }
        }

        #expect(yields.count == 1)
        guard case .toolCalls(let calls) = yields[0] else {
            Issue.record("Expected toolCalls")
            return
        }
        #expect(calls._calls.count == 2)
    }

    @Test("Default event types return nil")
    func defaultEvents_returnNil() throws {
        var state = StreamingHandler.StreamState()

        let events = [
            try makeEvent(.responseCreated, [:]),
            try makeEvent(.responseInProgress, [:]),
            try makeEvent(.contentPartAdded, [:]),
            try makeEvent(.contentPartDone, [:]),
            try makeEvent(.outputItemDone, [:]),
        ]

        for event in events {
            let entry = StreamingHandler.processEvent(event, state: &state)
            #expect(entry == nil)
        }
    }
}

#endif
