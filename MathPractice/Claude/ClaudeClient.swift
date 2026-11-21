import Foundation

/// Minimal Claude Messages API client over raw HTTP (there is no official Swift SDK).
/// Every request streams (SSE) so long extraction/solve calls never hit HTTP timeouts.
struct ClaudeClient: Sendable {
    static let defaultModel = "claude-opus-5-5"
    static let apiVersion = "2026-10-21"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    enum Effort: String, Sendable { case low, medium, high, xhigh, max }

    enum ClientError: LocalizedError, Equatable {
        case missingAPIKey
        case http(status: Int, message: String)
        case refusal(String)
        case truncated
        case emptyResponse
        case decoding(String)
        case stream(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey: return "No Claude API key is set. Add one in Settings."
            case let .http(status, message): return "Claude API error \(status): \(message)"
            case let .refusal(category): return "Claude declined this request (\(category))."
            case .truncated: return "Claude's response was cut off (max_tokens)."
            case .emptyResponse: return "Claude returned an empty response."
            case let .decoding(detail): return "Couldn't read Claude's response: \(detail)"
            case let .stream(detail): return "Streaming error: \(detail)"
            }
        }

        var isRetryable: Bool {
            if case let .http(status, _) = self { return status == 408 || status == 409 || status == 429 || status >= 500 }
            if case .stream = self { return true }
            return false
        }
    }

    /// A content block in a user message.
    enum Block: Sendable {
        case text(String)
        case jpeg(Data)
        case png(Data)

        var json: [String: Any] {
            switch self {
            case let .text(s):
                return ["type": "text", "text": s]
            case let .jpeg(d):
                return ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": d.base64EncodedString()]]
            case let .png(d):
                return ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": d.base64EncodedString()]]
            }
        }
    }

    let apiKey: @Sendable () -> String?
    var model: String = ClaudeClient.defaultModel
    var session: URLSession = .shared
    /// Large chapters make hundreds of calls; new API accounts have low rate limits, so retry patiently.
    var maxRetries: Int = 5

    init(apiKey: @escaping @Sendable () -> String?, model: String = ClaudeClient.defaultModel, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    // MARK: - Public API

    /// Sends one user turn and decodes the JSON-schema-constrained reply into `T`.
    func structured<T: Decodable>(
        _ type: T.Type,
        system: String,
        content: [Block],
        schema: OrderedObject,
        effort: Effort,
        maxTokens: Int = 32000,
        kind: String = "other"
    ) async throws -> T {
        let text = try await send(system: system, content: content, schema: schema, effort: effort, maxTokens: maxTokens, kind: kind)
        guard let data = text.data(using: .utf8) else { throw ClientError.decoding("non-UTF8 text") }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ClientError.decoding(String(describing: error))
        }
    }

    /// Sends one user turn and returns the concatenated text of the reply.
    func send(system: String, content: [Block], schema: OrderedObject?, effort: Effort, maxTokens: Int, kind: String = "other") async throws -> String {
        guard let key = apiKey(), !key.isEmpty else { throw ClientError.missingAPIKey }
        let body = Self.requestBody(model: model, system: system, content: content, schema: schema, effort: effort, maxTokens: maxTokens)
        let request = try Self.urlRequest(apiKey: key, body: body)

        var attempt = 0
        let started = Date()
        while true {
            do {
                let (text, usage) = try await performStreaming(request)
                CallLog.record(kind: kind, model: model, effort: effort.rawValue, started: started, retries: attempt,
                               usage: usage, error: nil, response: text)
                return text
            } catch let error as ClientError where error.isRetryable && attempt < maxRetries {
                attempt += 1
                try await Task.sleep(nanoseconds: UInt64(min(pow(2.0, Double(attempt)), 30) * 1_000_000_000))
            } catch let error as URLError where attempt < maxRetries && error.code != .cancelled {
                attempt += 1
                try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 1_000_000_000))
            } catch {
                CallLog.record(kind: kind, model: model, effort: effort.rawValue, started: started, retries: attempt,
                               usage: [:], error: error.localizedDescription, response: nil)
                throw error
            }
        }
    }

    // MARK: - Request building (internal for tests)

    static func requestBody(model: String, system: String, content: [Block], schema: OrderedObject?, effort: Effort, maxTokens: Int) -> [String: Any] {
        var outputConfig: [String: Any] = ["effort": effort.rawValue]
        if let schema {
            outputConfig["format"] = ["type": "json_schema", "schema": schema]
        }
        return [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            "system": system,
            "output_config": outputConfig,
            // Server-side fallback: if a safety classifier declines, the API retries on a fallback model.
            "fallbacks": "default",
            "messages": [["role": "user", "content": content.map(\.json)]],
        ]
    }

    static func urlRequest(apiKey: String, body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = JSONWriter.data(body)
        return request
    }

    // MARK: - Streaming

    private func performStreaming(_ request: URLRequest) async throws -> (String, [String: Int]) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.stream("no HTTP response") }
        if http.statusCode != 200 {
            var raw = Data()
            for try await byte in bytes { raw.append(byte) }
            throw ClientError.http(status: http.statusCode, message: Self.errorMessage(from: raw))
        }
        var parser = SSEAccumulator()
        for try await line in bytes.lines {
            try parser.consume(line: line)
        }
        return (try parser.finish(), parser.usage)
    }

    static func errorMessage(from data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = obj["error"] as? [String: Any], let msg = err["message"] as? String {
            return msg
        }
        return String(data: data, encoding: .utf8) ?? "unknown error"
    }
}

/// Accumulates Messages API server-sent events into the final text output.
/// Only `text` blocks are collected; thinking blocks are ignored.
struct SSEAccumulator {
    private var textBlockIndices = Set<Int>()
    private var textByIndex: [Int: String] = [:]
    private(set) var stopReason: String?
    private(set) var refusalCategory: String?
    private var sawMessageStop = false
    /// Token usage from message_start / message_delta.
    private(set) var usage: [String: Int] = [:]

    private mutating func mergeUsage(_ u: Any?) {
        guard let u = u as? [String: Any] else { return }
        for (k, v) in u { if let n = v as? Int { usage[k] = n } }
    }

    mutating func consume(line: String) throws {
        guard line.hasPrefix("data:") else { return }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let data = payload.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else { return }

        switch type {
        case "message_start":
            mergeUsage((event["message"] as? [String: Any])?["usage"])
        case "content_block_start":
            if let index = event["index"] as? Int,
               let block = event["content_block"] as? [String: Any],
               block["type"] as? String == "text" {
                textBlockIndices.insert(index)
                textByIndex[index] = (block["text"] as? String) ?? ""
            }
        case "content_block_delta":
            if let index = event["index"] as? Int, textBlockIndices.contains(index),
               let delta = event["delta"] as? [String: Any],
               delta["type"] as? String == "text_delta",
               let text = delta["text"] as? String {
                textByIndex[index, default: ""] += text
            }
        case "message_delta":
            mergeUsage(event["usage"])
            if let delta = event["delta"] as? [String: Any] {
                if let reason = delta["stop_reason"] as? String { stopReason = reason }
                if let details = delta["stop_details"] as? [String: Any] {
                    refusalCategory = details["category"] as? String
                }
            }
        case "message_stop":
            sawMessageStop = true
        case "error":
            let err = event["error"] as? [String: Any]
            let errType = err?["type"] as? String ?? "error"
            let message = err?["message"] as? String ?? "stream error"
            if errType == "overloaded_error" || errType == "api_error" {
                throw ClaudeClient.ClientError.stream(message)
            }
            throw ClaudeClient.ClientError.http(status: 400, message: message)
        default:
            break
        }
    }

    func finish() throws -> String {
        if stopReason == "refusal" { throw ClaudeClient.ClientError.refusal(refusalCategory ?? "unspecified") }
        if stopReason == "max_tokens" { throw ClaudeClient.ClientError.truncated }
        guard sawMessageStop else { throw ClaudeClient.ClientError.stream("stream ended early") }
        let text = textByIndex.keys.sorted().compactMap { textByIndex[$0] }.joined()
        guard !text.isEmpty else { throw ClaudeClient.ClientError.emptyResponse }
        return text
    }
}
