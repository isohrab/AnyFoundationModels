#if RESPONSE_ENABLED
import Foundation
import OpenFoundationModels

/// Handles streaming events and accumulates state for the Responses API
struct StreamingHandler {

    /// Accumulated state for a streaming response
    struct StreamState {
        var textContent: String = ""
        /// Accumulated function calls keyed by item_id
        var functionCalls: [String: FunctionCallState] = [:]
        var isComplete: Bool = false

        struct FunctionCallState {
            var callId: String
            var name: String
            var arguments: String
            var isDone: Bool = false
        }
    }

    /// Process a streaming event and produce an optional Transcript.Entry to yield
    static func processEvent(
        _ event: StreamingEvent,
        state: inout StreamState
    ) -> Transcript.Entry? {
        switch event.type {
        case .outputTextDelta:
            if let delta = event.textDelta {
                state.textContent += delta
                return .response(
                    Transcript.Response(
                        assetIDs: [],
                        segments: [.text(Transcript.TextSegment(content: delta))]
                    )
                )
            }

        case .outputTextDone:
            if let text = event.completedText {
                state.textContent = text
            }

        case .outputItemAdded:
            if let item = event.outputItem,
               item["type"] as? String == "function_call" {
                let itemId = item["id"] as? String ?? UUID().uuidString
                let callId = item["call_id"] as? String ?? itemId
                let name = item["name"] as? String ?? ""
                state.functionCalls[itemId] = StreamState.FunctionCallState(
                    callId: callId,
                    name: name,
                    arguments: ""
                )
            }

        case .functionCallArgumentsDelta:
            if let itemId = event.itemId,
               let delta = event.argumentsDelta {
                state.functionCalls[itemId]?.arguments += delta
            }

        case .functionCallArgumentsDone:
            if let itemId = event.itemId {
                if let args = event.completedArguments {
                    state.functionCalls[itemId]?.arguments = args
                }
                if let name = event.functionName {
                    state.functionCalls[itemId]?.name = name
                }
                state.functionCalls[itemId]?.isDone = true
            }

        case .responseCompleted:
            state.isComplete = true
            // Yield all completed tool calls at response completion
            let completedCalls = state.functionCalls.values
                .filter { $0.isDone }
                .map { fc in
                    Transcript.ToolCall(
                        id: fc.callId,
                        toolName: fc.name,
                        arguments: ResponseConverter.parseArguments(fc.arguments)
                    )
                }
            if !completedCalls.isEmpty {
                return .toolCalls(Transcript.ToolCalls(completedCalls))
            }

        case .responseFailed:
            state.isComplete = true

        case .error:
            state.isComplete = true

        default:
            break
        }

        return nil
    }
}

#endif
