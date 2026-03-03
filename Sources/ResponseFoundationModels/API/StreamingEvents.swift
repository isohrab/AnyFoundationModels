#if RESPONSE_ENABLED
import Foundation
import OpenFoundationModelsExtra

/// Streaming event types from the Responses API
enum StreamingEventType: String, Sendable {
    case responseCreated = "response.created"
    case responseInProgress = "response.in_progress"
    case responseCompleted = "response.completed"
    case responseIncomplete = "response.incomplete"
    case responseFailed = "response.failed"
    case outputItemAdded = "response.output_item.added"
    case outputItemDone = "response.output_item.done"
    case contentPartAdded = "response.content_part.added"
    case contentPartDone = "response.content_part.done"
    case outputTextDelta = "response.output_text.delta"
    case outputTextDone = "response.output_text.done"
    case functionCallArgumentsDelta = "response.function_call_arguments.delta"
    case functionCallArgumentsDone = "response.function_call_arguments.done"
    case error = "error"
}

/// A parsed streaming event backed by JSONValue (Sendable).
struct StreamingEvent: Sendable {
    let type: StreamingEventType
    private let data: JSONValue?

    init(type: StreamingEventType, rawData: Data) {
        self.type = type
        do {
            self.data = try JSONDecoder().decode(JSONValue.self, from: rawData)
        } catch {
            self.data = nil
        }
    }

    private func stringValue(forKey key: String) -> String? {
        guard case .object(let dict) = data,
              let val = dict[key],
              case .string(let s) = val else { return nil }
        return s
    }

    private func intValue(forKey key: String) -> Int? {
        guard case .object(let dict) = data, let val = dict[key] else { return nil }
        if case .int(let i) = val { return i }
        if case .double(let d) = val { return Int(d) }
        return nil
    }

    private func nestedValue(forKey key: String) -> JSONValue? {
        guard case .object(let dict) = data else { return nil }
        return dict[key]
    }

    /// Extract text delta content
    var textDelta: String? { stringValue(forKey: "delta") }

    /// Extract completed text
    var completedText: String? { stringValue(forKey: "text") }

    /// Extract function call arguments delta
    var argumentsDelta: String? { stringValue(forKey: "delta") }

    /// Extract completed function call arguments
    var completedArguments: String? { stringValue(forKey: "arguments") }

    /// Extract function call name
    var functionName: String? { stringValue(forKey: "name") }

    /// Extract item ID
    var itemId: String? { stringValue(forKey: "item_id") }

    /// Extract output index
    var outputIndex: Int? { intValue(forKey: "output_index") }

    /// Extract the item from output_item events
    var outputItem: JSONValue? { nestedValue(forKey: "item") }

    /// Extract the full response object from response events
    var responseObject: JSONValue? { nestedValue(forKey: "response") }

    /// Extract error information
    var errorMessage: String? { stringValue(forKey: "message") }

    var errorCode: String? { stringValue(forKey: "code") }
}

#endif
