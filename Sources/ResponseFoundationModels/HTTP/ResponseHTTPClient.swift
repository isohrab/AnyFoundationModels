#if RESPONSE_ENABLED
import Foundation
import OpenFoundationModelsExtra

/// HTTP client for the OpenAI Responses API
actor ResponseHTTPClient {
    private let configuration: ResponseConfiguration
    private let session: URLSession

    init(configuration: ResponseConfiguration) {
        self.configuration = configuration
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = configuration.timeout
        self.session = URLSession(configuration: config)
    }

    /// Send a non-streaming request
    func send(_ request: ResponsesRequest) async throws -> ResponseObject {
        var urlRequest = try buildURLRequest(request)
        urlRequest.httpMethod = "POST"

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ResponseError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ResponseError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        return try JSONDecoder().decode(ResponseObject.self, from: data)
    }

    /// Send a streaming request, yielding parsed events
    func stream(_ request: ResponsesRequest) async throws -> AsyncThrowingStream<StreamingEvent, Error> {
        var streamRequest = request
        streamRequest.stream = true

        var urlRequest = try buildURLRequest(streamRequest)
        urlRequest.httpMethod = "POST"

        let (bytes, response) = try await session.bytes(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ResponseError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            var body = ""
            for try await line in bytes.lines {
                body += line + "\n"
            }
            throw ResponseError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var currentEventType: String?

                    for try await line in bytes.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)

                        if trimmed.isEmpty {
                            currentEventType = nil
                            continue
                        }

                        if trimmed.hasPrefix("event:") {
                            currentEventType = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                            continue
                        }

                        if trimmed.hasPrefix("data:") {
                            let dataString = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)

                            if dataString == "[DONE]" {
                                continuation.finish()
                                return
                            }

                            guard let eventTypeStr = currentEventType,
                                  let eventType = StreamingEventType(rawValue: eventTypeStr),
                                  let jsonData = dataString.data(using: .utf8) else {
                                continue
                            }

                            let event = StreamingEvent(type: eventType, rawData: jsonData)
                            continuation.yield(event)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private

    private func buildURLRequest(_ request: ResponsesRequest) throws -> URLRequest {
        let url = configuration.baseURL.appendingPathComponent("responses")
        var urlRequest = URLRequest(url: url)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        return urlRequest
    }
}

/// Errors from the Response API backend
public enum ResponseError: Error, LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case streamingError(message: String)
    case decodingError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode, let body):
            return "HTTP error \(statusCode): \(body)"
        case .streamingError(let message):
            return "Streaming error: \(message)"
        case .decodingError(let message):
            return "Decoding error: \(message)"
        }
    }
}

#endif
