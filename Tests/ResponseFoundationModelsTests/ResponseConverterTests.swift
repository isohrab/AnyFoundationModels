#if RESPONSE_ENABLED
import Testing
import Foundation
@testable import ResponseFoundationModels
import OpenFoundationModels

@Suite("ResponseConverter Tests")
struct ResponseConverterTests {

    // MARK: - Helpers

    private func makeResponseObject(_ json: [String: Any]) throws -> ResponseObject {
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(ResponseObject.self, from: data)
    }

    // MARK: - convert: Text Responses

    @Test("Single text message produces response entry")
    func convert_singleTextMessage() throws {
        let response = try makeResponseObject([
            "id": "resp-1",
            "object": "response",
            "output": [
                [
                    "type": "message",
                    "role": "assistant",
                    "content": [
                        ["type": "output_text", "text": "Hello world"]
                    ]
                ] as [String: Any]
            ]
        ])

        let entry = ResponseConverter.convert(response)
        guard case .response(let resp) = entry else {
            Issue.record("Expected response entry")
            return
        }
        let text = resp.segments.compactMap { segment -> String? in
            if case .text(let t) = segment { return t.content }
            return nil
        }.joined()
        #expect(text == "Hello world")
    }

    @Test("Multiple content parts are joined")
    func convert_multipleContentParts() throws {
        let response = try makeResponseObject([
            "id": "resp-1",
            "object": "response",
            "output": [
                [
                    "type": "message",
                    "role": "assistant",
                    "content": [
                        ["type": "output_text", "text": "Hello"],
                        ["type": "output_text", "text": " World"],
                    ]
                ] as [String: Any]
            ]
        ])

        let entry = ResponseConverter.convert(response)
        guard case .response(let resp) = entry else {
            Issue.record("Expected response entry")
            return
        }
        let text = resp.segments.compactMap { segment -> String? in
            if case .text(let t) = segment { return t.content }
            return nil
        }.joined()
        #expect(text == "Hello World")
    }

    @Test("Empty output produces empty response")
    func convert_emptyOutput() throws {
        let response = try makeResponseObject([
            "id": "resp-1",
            "object": "response",
            "output": [] as [[String: Any]]
        ])

        let entry = ResponseConverter.convert(response)
        guard case .response(let resp) = entry else {
            Issue.record("Expected response entry")
            return
        }
        let text = resp.segments.compactMap { segment -> String? in
            if case .text(let t) = segment { return t.content }
            return nil
        }.joined()
        #expect(text == "")
    }

    // MARK: - convert: Function Call Responses

    @Test("Single function call produces toolCalls entry")
    func convert_singleFunctionCall() throws {
        let response = try makeResponseObject([
            "id": "resp-1",
            "object": "response",
            "output": [
                [
                    "type": "function_call",
                    "id": "fc-1",
                    "call_id": "call-1",
                    "name": "search",
                    "arguments": "{\"query\":\"swift\"}",
                    "status": "completed",
                ] as [String: Any]
            ]
        ])

        let entry = ResponseConverter.convert(response)
        guard case .toolCalls(let calls) = entry else {
            Issue.record("Expected toolCalls entry")
            return
        }
        let callList = calls._calls
        #expect(callList.count == 1)
        #expect(callList[0].toolName == "search")
        #expect(callList[0].id == "call-1")
    }

    @Test("Multiple function calls produces toolCalls with all calls")
    func convert_multipleFunctionCalls() throws {
        let response = try makeResponseObject([
            "id": "resp-1",
            "object": "response",
            "output": [
                [
                    "type": "function_call",
                    "id": "fc-1",
                    "call_id": "call-1",
                    "name": "search",
                    "arguments": "{}",
                    "status": "completed",
                ] as [String: Any],
                [
                    "type": "function_call",
                    "id": "fc-2",
                    "call_id": "call-2",
                    "name": "calculate",
                    "arguments": "{}",
                    "status": "completed",
                ] as [String: Any],
            ]
        ])

        let entry = ResponseConverter.convert(response)
        guard case .toolCalls(let calls) = entry else {
            Issue.record("Expected toolCalls entry")
            return
        }
        let callList = calls._calls
        #expect(callList.count == 2)
        #expect(callList[0].toolName == "search")
        #expect(callList[1].toolName == "calculate")
    }

    @Test("Function call uses callId over id")
    func convert_functionCallIdPrecedence() throws {
        let response = try makeResponseObject([
            "id": "resp-1",
            "object": "response",
            "output": [
                [
                    "type": "function_call",
                    "id": "item-id",
                    "call_id": "preferred-call-id",
                    "name": "test",
                    "arguments": "{}",
                ] as [String: Any]
            ]
        ])

        let entry = ResponseConverter.convert(response)
        guard case .toolCalls(let calls) = entry else {
            Issue.record("Expected toolCalls entry")
            return
        }
        #expect(calls._calls[0].id == "preferred-call-id")
    }

    @Test("Function call with nil arguments defaults to empty structure")
    func convert_nilArguments() throws {
        let response = try makeResponseObject([
            "id": "resp-1",
            "object": "response",
            "output": [
                [
                    "type": "function_call",
                    "id": "fc-1",
                    "call_id": "call-1",
                    "name": "test",
                ] as [String: Any]
            ]
        ])

        let entry = ResponseConverter.convert(response)
        guard case .toolCalls(let calls) = entry else {
            Issue.record("Expected toolCalls entry")
            return
        }
        let args = calls._calls[0].arguments
        let props = try args.properties()
        #expect(props.isEmpty)
    }

    // MARK: - convert: Mixed Output Precedence

    @Test("Function calls take precedence over text in mixed output")
    func convert_functionCallPrecedence() throws {
        let response = try makeResponseObject([
            "id": "resp-1",
            "object": "response",
            "output": [
                [
                    "type": "message",
                    "role": "assistant",
                    "content": [["type": "output_text", "text": "Some text"]]
                ] as [String: Any],
                [
                    "type": "function_call",
                    "id": "fc-1",
                    "call_id": "call-1",
                    "name": "search",
                    "arguments": "{}",
                ] as [String: Any],
            ]
        ])

        let entry = ResponseConverter.convert(response)
        guard case .toolCalls = entry else {
            Issue.record("Expected toolCalls entry (text should be discarded)")
            return
        }
    }

    // MARK: - parseArguments

    @Test("Parse valid JSON arguments")
    func parseArguments_validJSON() throws {
        let content = ResponseConverter.parseArguments("{\"city\":\"Tokyo\"}")
        let props = try content.properties()
        let city = try props["city"]?.value(String.self)
        #expect(city == "Tokyo")
    }

    @Test("Parse invalid JSON returns empty structure")
    func parseArguments_invalidJSON() throws {
        let content = ResponseConverter.parseArguments("not json")
        let props = try content.properties()
        #expect(props.isEmpty)
    }

    @Test("Parse empty object")
    func parseArguments_emptyObject() throws {
        let content = ResponseConverter.parseArguments("{}")
        let props = try content.properties()
        #expect(props.isEmpty)
    }

    @Test("Parse nested JSON")
    func parseArguments_nestedJSON() throws {
        let content = ResponseConverter.parseArguments("{\"outer\":{\"inner\":\"value\"}}")
        let props = try content.properties()
        let outerProps = try props["outer"]?.properties()
        let inner = try outerProps?["inner"]?.value(String.self)
        #expect(inner == "value")
    }

    // MARK: - convertJSONToGeneratedContent

    @Test("Convert string JSON value")
    func convertJSON_string() {
        let content = ResponseConverter.convertJSONToGeneratedContent("hello")
        if case .string(let s) = content.kind {
            #expect(s == "hello")
        } else {
            Issue.record("Expected string kind")
        }
    }

    @Test("Convert bool true (not number 1)")
    func convertJSON_boolTrue() {
        let content = ResponseConverter.convertJSONToGeneratedContent(true as NSNumber)
        if case .bool(let b) = content.kind {
            #expect(b == true)
        } else {
            Issue.record("Expected bool kind, got \(content.kind)")
        }
    }

    @Test("Convert bool false (not number 0)")
    func convertJSON_boolFalse() {
        let content = ResponseConverter.convertJSONToGeneratedContent(false as NSNumber)
        if case .bool(let b) = content.kind {
            #expect(b == false)
        } else {
            Issue.record("Expected bool kind, got \(content.kind)")
        }
    }

    @Test("Convert integer number")
    func convertJSON_number() {
        let content = ResponseConverter.convertJSONToGeneratedContent(42 as NSNumber)
        if case .number(let n) = content.kind {
            #expect(n == 42.0)
        } else {
            Issue.record("Expected number kind")
        }
    }

    @Test("Convert null")
    func convertJSON_null() {
        let content = ResponseConverter.convertJSONToGeneratedContent(NSNull())
        if case .null = content.kind {
            // OK
        } else {
            Issue.record("Expected null kind")
        }
    }

    @Test("Convert array")
    func convertJSON_array() {
        let content = ResponseConverter.convertJSONToGeneratedContent(["a", "b"])
        if case .array(let elements) = content.kind {
            #expect(elements.count == 2)
        } else {
            Issue.record("Expected array kind")
        }
    }

    @Test("Convert dictionary with sorted keys")
    func convertJSON_dictionary() {
        let content = ResponseConverter.convertJSONToGeneratedContent(["b": 2, "a": 1] as [String: Any])
        if case .structure(let props, let keys) = content.kind {
            #expect(props.count == 2)
            #expect(keys == ["a", "b"])
        } else {
            Issue.record("Expected structure kind")
        }
    }
}

#endif
