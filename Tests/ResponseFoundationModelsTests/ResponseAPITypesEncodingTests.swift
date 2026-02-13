#if RESPONSE_ENABLED
import Testing
import Foundation
@testable import ResponseFoundationModels

@Suite("Response API Types Encoding Tests")
struct ResponseAPITypesEncodingTests {

    // MARK: - Helpers

    private func encodeToJSON<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    private func encodeToData<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    // MARK: - MessageItem

    @Test("MessageItem encodes with type field")
    func messageItem_hasTypeField() throws {
        let item = MessageItem(role: "user", content: "Hello")
        let json = try encodeToJSON(item)
        #expect(json["type"] as? String == "message")
        #expect(json["role"] as? String == "user")
        #expect(json["content"] as? String == "Hello")
    }

    // MARK: - InputItem Union Encoding

    @Test("InputItem.message encodes correctly")
    func inputItem_message() throws {
        let item = InputItem.message(MessageItem(role: "system", content: "Be helpful"))
        let json = try encodeToJSON(item)
        #expect(json["type"] as? String == "message")
        #expect(json["role"] as? String == "system")
    }

    @Test("InputItem.functionCall encodes correctly")
    func inputItem_functionCall() throws {
        let item = InputItem.functionCall(FunctionCallItem(
            id: nil,
            callId: "call-1",
            name: "search",
            arguments: "{\"q\":\"swift\"}",
            status: "completed"
        ))
        let json = try encodeToJSON(item)
        #expect(json["type"] as? String == "function_call")
        #expect(json["call_id"] as? String == "call-1")
        #expect(json["name"] as? String == "search")
    }

    @Test("InputItem.functionCallOutput encodes correctly")
    func inputItem_functionCallOutput() throws {
        let item = InputItem.functionCallOutput(FunctionCallOutputItem(
            callId: "call-1",
            output: "result text"
        ))
        let json = try encodeToJSON(item)
        #expect(json["type"] as? String == "function_call_output")
        #expect(json["call_id"] as? String == "call-1")
        #expect(json["output"] as? String == "result text")
    }

    // MARK: - FunctionCallItem CodingKeys

    @Test("FunctionCallItem encodes callId as call_id")
    func functionCallItem_snakeCase() throws {
        let item = FunctionCallItem(
            id: "fc-id",
            callId: "call-id",
            name: "test",
            arguments: "{}",
            status: nil
        )
        let json = try encodeToJSON(item)
        #expect(json["call_id"] as? String == "call-id")
        #expect(json["id"] as? String == "fc-id")
        // status nil should not be present or be null
    }

    // MARK: - ResponsesRequest CodingKeys

    @Test("ResponsesRequest encodes with snake_case keys")
    func responsesRequest_snakeCaseKeys() throws {
        var request = ResponsesRequest(
            model: "gpt-4.1",
            input: [.message(MessageItem(role: "user", content: "Hi"))],
            instructions: nil,
            tools: nil,
            stream: true
        )
        request.topP = 0.95
        request.maxOutputTokens = 1000
        request.temperature = 0.7

        let json = try encodeToJSON(request)
        #expect(json["model"] as? String == "gpt-4.1")
        #expect(json["stream"] as? Bool == true)
        #expect(json["top_p"] as? Double == 0.95)
        #expect(json["max_output_tokens"] as? Int == 1000)
        #expect(json["temperature"] as? Double == 0.7)
        // Verify snake_case keys exist (not camelCase)
        #expect(json["topP"] == nil)
        #expect(json["maxOutputTokens"] == nil)
    }

    // MARK: - ToolChoice

    @Test("ToolChoice.auto encodes as string")
    func toolChoice_auto() throws {
        let data = try encodeToData(ToolChoice.auto)
        let value = String(data: data, encoding: .utf8)
        #expect(value == "\"auto\"")
    }

    @Test("ToolChoice.none encodes as string")
    func toolChoice_none() throws {
        let data = try encodeToData(ToolChoice.none)
        let value = String(data: data, encoding: .utf8)
        #expect(value == "\"none\"")
    }

    @Test("ToolChoice.required encodes as string")
    func toolChoice_required() throws {
        let data = try encodeToData(ToolChoice.required)
        let value = String(data: data, encoding: .utf8)
        #expect(value == "\"required\"")
    }

    @Test("ToolChoice.function encodes as object")
    func toolChoice_function() throws {
        let data = try encodeToData(ToolChoice.function(name: "search"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: String]
        let result = try #require(json)
        #expect(result["type"] == "function")
        #expect(result["name"] == "search")
    }

    // MARK: - TextFormat

    @Test("TextFormat.jsonObject encodes with format wrapper")
    func textFormat_jsonObject() throws {
        let format = TextFormat(format: .jsonObject)
        let json = try encodeToJSON(format)
        let inner = try #require(json["format"] as? [String: Any])
        #expect(inner["type"] as? String == "json_object")
    }

    @Test("TextFormat.text encodes with format wrapper")
    func textFormat_text() throws {
        let format = TextFormat(format: .text)
        let json = try encodeToJSON(format)
        let inner = try #require(json["format"] as? [String: Any])
        #expect(inner["type"] as? String == "text")
    }

    @Test("TextFormat.jsonSchema encodes with all fields")
    func textFormat_jsonSchema() throws {
        let schema: [String: Any] = ["type": "object", "properties": ["name": ["type": "string"]]]
        let format = TextFormat(format: .jsonSchema(name: "TestSchema", schema: schema, strict: true))
        let json = try encodeToJSON(format)
        let inner = try #require(json["format"] as? [String: Any])
        #expect(inner["type"] as? String == "json_schema")
        #expect(inner["name"] as? String == "TestSchema")
        #expect(inner["strict"] as? Bool == true)
        #expect(inner["schema"] != nil)
    }

    // MARK: - JSONSchemaProperty Recursive

    @Test("JSONSchemaProperty encodes recursively")
    func jsonSchemaProperty_recursive() throws {
        let innerProp = JSONSchemaProperty(type: "string", description: "Inner")
        let outerProp = JSONSchemaProperty(
            type: "object",
            description: "Outer",
            properties: ["inner": innerProp],
            required: ["inner"]
        )
        let json = try encodeToJSON(outerProp)
        #expect(json["type"] as? String == "object")
        let props = try #require(json["properties"] as? [String: Any])
        let innerJson = try #require(props["inner"] as? [String: Any])
        #expect(innerJson["type"] as? String == "string")
    }

    // MARK: - ToolDefinition

    @Test("ToolDefinition encodes with type function")
    func toolDefinition_encodesType() throws {
        let def = ToolDefinition(
            name: "search",
            description: "Search the web",
            parameters: JSONSchemaObject(
                type: "object",
                properties: ["query": JSONSchemaProperty(type: "string")],
                required: ["query"],
                additionalProperties: false
            ),
            strict: true
        )
        let json = try encodeToJSON(def)
        #expect(json["type"] as? String == "function")
        #expect(json["name"] as? String == "search")
        #expect(json["strict"] as? Bool == true)
    }
}

#endif
