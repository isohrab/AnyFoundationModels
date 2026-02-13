#if CLAUDE_ENABLED
import Foundation

/// HTTP client for Claude API
public actor ClaudeHTTPClient {
    private let session: URLSession
    private let configuration: ClaudeConfiguration
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(configuration: ClaudeConfiguration) {
        self.configuration = configuration

        // Configure URLSession
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = configuration.timeout
        config.timeoutIntervalForResource = configuration.timeout
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    // MARK: - Public Methods

    /// Send a request and decode the response
    public func send<Request: Encodable, Response: Decodable>(
        _ request: Request,
        to endpoint: String,
        betaHeaders: [String]? = nil
    ) async throws -> Response {
        let url = resolveEndpointURL(for: endpoint)

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(configuration.apiVersion, forHTTPHeaderField: "anthropic-version")
        if let betaHeaders = betaHeaders, !betaHeaders.isEmpty {
            urlRequest.setValue(betaHeaders.joined(separator: ","), forHTTPHeaderField: "anthropic-beta")
        }
        applyAdditionalHeaders(to: &urlRequest)
        urlRequest.httpBody = try encoder.encode(request)

        do {
            let (data, response) = try await session.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ClaudeHTTPError.invalidResponse
            }

            if httpResponse.statusCode >= 400 {
                do {
                    let errorResponse = try decoder.decode(ClaudeErrorResponse.self, from: data)
                    throw errorResponse
                } catch let knownError as ClaudeErrorResponse {
                    throw knownError
                } catch {
                    throw ClaudeHTTPError.statusError(httpResponse.statusCode, data)
                }
            }

            return try decoder.decode(Response.self, from: data)
        } catch let error as URLError {
            if error.code == .notConnectedToInternet || error.code == .cannotConnectToHost {
                throw ClaudeHTTPError.connectionError("Cannot connect to Claude API at \(configuration.baseURL)")
            }
            throw ClaudeHTTPError.networkError(error.localizedDescription)
        } catch {
            throw error
        }
    }

    /// Stream a request with Server-Sent Events (SSE)
    func stream<Request: Encodable & Sendable>(
        _ request: Request,
        to endpoint: String,
        betaHeaders: [String]? = nil
    ) -> AsyncThrowingStream<StreamingEvent, Error> {
        let betaHeadersCopy = betaHeaders
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = self.resolveEndpointURL(for: endpoint)

                    var urlRequest = URLRequest(url: url)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
                    urlRequest.setValue(configuration.apiVersion, forHTTPHeaderField: "anthropic-version")
                    if let betaHeaders = betaHeadersCopy, !betaHeaders.isEmpty {
                        urlRequest.setValue(betaHeaders.joined(separator: ","), forHTTPHeaderField: "anthropic-beta")
                    }
                    self.applyAdditionalHeaders(to: &urlRequest)
                    urlRequest.httpBody = try encoder.encode(request)

                    let (asyncBytes, response) = try await session.bytes(for: urlRequest)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: ClaudeHTTPError.invalidResponse)
                        return
                    }

                    if httpResponse.statusCode >= 400 {
                        var errorData = Data()
                        for try await byte in asyncBytes {
                            errorData.append(byte)
                        }

                        do {
                            let errorResponse = try decoder.decode(ClaudeErrorResponse.self, from: errorData)
                            continuation.finish(throwing: errorResponse)
                        } catch _ as DecodingError {
                            continuation.finish(throwing: ClaudeHTTPError.statusError(httpResponse.statusCode, errorData))
                        } catch {
                            continuation.finish(throwing: error)
                        }
                        return
                    }

                    // Process SSE stream using byte buffer with UTF-8 safe decoding.
                    // Detect event boundaries at byte level (\n\n = 0x0A 0x0A),
                    // then decode complete event strings as UTF-8.
                    let doubleNewline = Data([0x0A, 0x0A])
                    var buffer = Data()

                    for try await byte in asyncBytes {
                        buffer.append(byte)

                        while let range = buffer.range(of: doubleNewline) {
                            let eventData = buffer[buffer.startIndex..<range.lowerBound]
                            buffer.removeSubrange(buffer.startIndex..<range.upperBound)

                            guard let eventString = String(data: eventData, encoding: .utf8) else {
                                continue
                            }

                            if let event = self.parseSSEEvent(eventString) {
                                continuation.yield(event)

                                if case .messageStop = event {
                                    continuation.finish()
                                    return
                                }
                                if case .error = event {
                                    continuation.finish()
                                    return
                                }
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private Methods

    /// Parse SSE event data
    private func parseSSEEvent(_ data: String) -> StreamingEvent? {
        var eventType: String?
        var eventData: String?

        for line in data.split(separator: "\n", omittingEmptySubsequences: false) {
            let lineStr = String(line)
            if lineStr.hasPrefix("event: ") {
                eventType = String(lineStr.dropFirst(7))
            } else if lineStr.hasPrefix("data: ") {
                eventData = String(lineStr.dropFirst(6))
            }
        }

        guard let type = eventType, let jsonData = eventData?.data(using: .utf8) else {
            return nil
        }

        do {
            switch type {
            case "message_start":
                let event = try decoder.decode(MessageStartEvent.self, from: jsonData)
                return .messageStart(event)

            case "content_block_start":
                let event = try decoder.decode(ContentBlockStartEvent.self, from: jsonData)
                return .contentBlockStart(event)

            case "content_block_delta":
                let event = try decoder.decode(ContentBlockDeltaEvent.self, from: jsonData)
                return .contentBlockDelta(event)

            case "content_block_stop":
                let event = try decoder.decode(ContentBlockStopEvent.self, from: jsonData)
                return .contentBlockStop(event)

            case "message_delta":
                let event = try decoder.decode(MessageDeltaEvent.self, from: jsonData)
                return .messageDelta(event)

            case "message_stop":
                let event = try decoder.decode(MessageStopEvent.self, from: jsonData)
                return .messageStop(event)

            case "ping":
                return .ping

            case "error":
                let event = try decoder.decode(ErrorEvent.self, from: jsonData)
                return .error(event)

            default:
                return nil
            }
        } catch {
            #if DEBUG
            print("Failed to parse SSE event '\(type)': \(error)")
            #endif
            return nil
        }
    }

    private func resolveEndpointURL(for endpoint: String) -> URL {
        if let endpointURL = configuration.endpointURL {
            return endpointURL
        }
        return configuration.baseURL.appendingPathComponent(endpoint)
    }

    private func applyAdditionalHeaders(to request: inout URLRequest) {
        if configuration.additionalHeaders.isEmpty {
            return
        }
        for (key, value) in configuration.additionalHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }
}

// MARK: - HTTP Errors

public enum ClaudeHTTPError: Error, LocalizedError, Sendable {
    case invalidResponse
    case statusError(Int, Data?)
    case networkError(String)
    case connectionError(String)
    case decodingError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response received from Claude API"
        case .statusError(let code, _):
            return "HTTP error with status code: \(code)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .connectionError(let message):
            return message
        case .decodingError(let message):
            return "Failed to decode response: \(message)"
        }
    }
}

#endif
