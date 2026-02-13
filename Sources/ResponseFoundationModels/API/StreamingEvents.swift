#if RESPONSE_ENABLED
import Foundation

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

/// A parsed streaming event (Sendable-safe using raw Data)
struct StreamingEvent: Sendable {
    let type: StreamingEventType
    let rawData: Data

    /// Lazily parse the JSON data
    private var data: [String: Any]? {
        try? JSONSerialization.jsonObject(with: rawData) as? [String: Any]
    }

    /// Extract text delta content
    var textDelta: String? {
        data?["delta"] as? String
    }

    /// Extract completed text
    var completedText: String? {
        data?["text"] as? String
    }

    /// Extract function call arguments delta
    var argumentsDelta: String? {
        data?["delta"] as? String
    }

    /// Extract completed function call arguments
    var completedArguments: String? {
        data?["arguments"] as? String
    }

    /// Extract function call name
    var functionName: String? {
        data?["name"] as? String
    }

    /// Extract item ID
    var itemId: String? {
        data?["item_id"] as? String
    }

    /// Extract output index
    var outputIndex: Int? {
        data?["output_index"] as? Int
    }

    /// Extract the item from output_item events
    var outputItem: [String: Any]? {
        data?["item"] as? [String: Any]
    }

    /// Extract the full response object from response events
    var responseObject: [String: Any]? {
        data?["response"] as? [String: Any]
    }

    /// Extract error information
    var errorMessage: String? {
        data?["message"] as? String
    }

    var errorCode: String? {
        data?["code"] as? String
    }
}

#endif
