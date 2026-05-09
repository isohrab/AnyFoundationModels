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

    /// Send a non-streaming request.
    ///
    /// Automatically retries once with `forceRefresh: true` if the first attempt
    /// receives a `401 Unauthorized` response, giving the key provider a chance
    /// to clear any stale cache and return a fresh credential.
    func send(_ request: ResponsesRequest) async throws -> ResponseObject {
        let urlRequest = try await buildURLRequest(request, forceRefreshAPIKey: false)
        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ResponseError.invalidResponse
        }

        // 401 → refresh the key and retry once
        if httpResponse.statusCode == 401 {
            let retryRequest = try await buildURLRequest(request, forceRefreshAPIKey: true)
            let (retryData, retryResponse) = try await session.data(for: retryRequest)

            guard let retryHTTPResponse = retryResponse as? HTTPURLResponse else {
                throw ResponseError.invalidResponse
            }

            if retryHTTPResponse.statusCode == 401 {
                throw ResponseError.unauthorized
            }

            return try decodeResponse(data: retryData, statusCode: retryHTTPResponse.statusCode)
        }

        return try decodeResponse(data: data, statusCode: httpResponse.statusCode)
    }

    /// Send a streaming request, yielding parsed events.
    ///
    /// Retries once with `forceRefresh: true` when the *pre-stream* HTTP status is
    /// `401`. Retrying after the byte stream has started is not supported — the
    /// method throws `ResponseError.unauthorized` in that case.
    func stream(_ request: ResponsesRequest) async throws -> AsyncThrowingStream<StreamingEvent, Error> {
        var streamRequest = request
        streamRequest.stream = true

        let urlRequest = try await buildURLRequest(streamRequest, forceRefreshAPIKey: false)
        let (bytes, response) = try await session.bytes(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ResponseError.invalidResponse
        }

        // 401 before any bytes are consumed → refresh the key and retry once
        let resolvedBytes: URLSession.AsyncBytes
        if httpResponse.statusCode == 401 {
            let retryURLRequest = try await buildURLRequest(streamRequest, forceRefreshAPIKey: true)
            let (retryBytes, retryResponse) = try await session.bytes(for: retryURLRequest)

            guard let retryHTTPResponse = retryResponse as? HTTPURLResponse else {
                throw ResponseError.invalidResponse
            }

            if retryHTTPResponse.statusCode == 401 {
                throw ResponseError.unauthorized
            }

            guard (200..<300).contains(retryHTTPResponse.statusCode) else {
                var body = ""
                for try await line in retryBytes.lines { body += line + "\n" }
                throw ResponseError.httpError(statusCode: retryHTTPResponse.statusCode, body: body)
            }

            resolvedBytes = retryBytes
        } else {
            guard (200..<300).contains(httpResponse.statusCode) else {
                var body = ""
                for try await line in bytes.lines { body += line + "\n" }
                throw ResponseError.httpError(statusCode: httpResponse.statusCode, body: body)
            }

            resolvedBytes = bytes
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var currentEventType: String?

                    for try await line in resolvedBytes.lines {
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

    // MARK: - Private helpers

    /// Build a `URLRequest` for the Responses endpoint.
    ///
    /// - Parameters:
    ///   - request: The API request to encode.
    ///   - forceRefreshAPIKey: Forwarded to `ResponseConfiguration.resolveAPIKey(forceRefresh:)`.
    ///     Pass `true` when retrying after a `401` so that a dynamic provider can bypass
    ///     its cache and return a fresh credential.
    private func buildURLRequest(
        _ request: ResponsesRequest,
        forceRefreshAPIKey: Bool = false
    ) async throws -> URLRequest {
        let url = configuration.baseURL.appendingPathComponent("responses")
        var urlRequest = URLRequest(url: url)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let apiKey = try await configuration.resolveAPIKey(forceRefresh: forceRefreshAPIKey)
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        return urlRequest
    }

    private func decodeResponse(data: Data, statusCode: Int) throws -> ResponseObject {
        guard (200..<300).contains(statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ResponseError.httpError(statusCode: statusCode, body: body)
        }
        return try JSONDecoder().decode(ResponseObject.self, from: data)
    }
}

/// Errors from the Response API backend
public enum ResponseError: Error, LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    /// The request was rejected with `401 Unauthorized` even after retrying with
    /// a force-refreshed API key.
    case unauthorized
    case streamingError(message: String)
    case decodingError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode, let body):
            return "HTTP error \(statusCode): \(body)"
        case .unauthorized:
            return "Unauthorized — API key was rejected after retry"
        case .streamingError(let message):
            return "Streaming error: \(message)"
        case .decodingError(let message):
            return "Decoding error: \(message)"
        }
    }
}

#endif
