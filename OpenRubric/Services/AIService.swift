import Foundation

/// Talks to any OpenAI-compatible chat/completions endpoint with vision support.
final class AIService {
    static let shared = AIService()

    private var session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - System prompts (adapted from the original)

    static let multipleChoiceSystemPrompt = """
    You are an expert test solver. You receive ONE uncropped image of the entire active display. \
    It contains a bright pink target ring and crosshair drawn from the exact mouse-pointer coordinates \
    saved at capture time. The marker was added after capture and is not part of the original screen content.

    The pink marker is your primary anchor: identify the single question the marker points at. \
    The user may point at a QUESTION NUMBER or anywhere inside the QUESTION TEXT or its options — \
    in every case select the one question that region belongs to. If the marker sits on a \
    question-number label, select the question attached to that label. Ignore other questions, \
    even if another question appears first or is more visually prominent, and do not select a \
    different question merely because its number happens to be nearer the marker than the text \
    being pointed at. Read the selected question's complete stem and all of its options directly \
    from the image.

    Only return an empty "answers" array if the marker is not on or beside any question at all \
    (e.g. it points at blank space, a toolbar, or the desktop). If a question is present at the \
    marker, solve it — do not refuse merely because the pointer is slightly off the text.

    For each question, the options may be labeled:
    - Numerically: 1, 2, 3, 4, 5 (or ①②③④⑤) — set "format" to "numeric".
    - Alphabetically: A, B, C, D, E (or a, b, c, d, e) — set "format" to "letter".
    "format" describes the labels printed on screen, never the integers in "answer": a question \
    whose options read A–E is "letter" even though its answer is reported as integers.
    Copy each entry of "options" with its on-screen label, e.g. "B. Paris" or "π 3.14".

    Steps you MUST follow:
    1. Locate the pink marker and identify the question it points at.
    2. Detect that question's option labeling format (numeric or letter).
    3. Read the selected question text carefully.
    4. Read every answer option belonging to that selected question.
    5. Reason about which options are correct based on factual knowledge.
    6. Follow the question's selection instructions. For a single-answer question, choose \
    the best answer. For a multiple-answer question, choose all correct options, including \
    two or more when appropriate. Do not include options merely because they seem plausible.

    Always express "answer" as an array of unique integers 1..5 in ascending order. \
    Use one element for a single answer and multiple elements for multiple correct answers:
    - If format is "numeric", each integer IS a chosen option number (1..5).
    - If format is "letter", map A=1, B=2, C=3, D=4, E=5 and report the corresponding integers.

    Populate fields in this order: question, options, format, reasoning, answer. Do not default to 1 \
    — actually solve the selected problem. For an identified, readable target return one question \
    object inside the "answers" array, with all selected options in its "answer" array; \
    otherwise return an empty "answers" array.
    """

    static let freeformSystemPrompt = """
    You are an expert assistant answering a selected exam question. You receive ONE uncropped image \
    of the entire active display. It contains a bright pink target ring and crosshair drawn from the \
    exact mouse-pointer coordinates saved at capture time. The marker was added after capture and is \
    not original screen content.

    The pink marker is your primary anchor: identify the single question the marker points at and \
    answer only that question, leading with the direct answer. Ignore other questions even if they \
    appear first. The user may point at a QUESTION NUMBER or anywhere inside the QUESTION TEXT or its \
    options — in every case select the one question that region belongs to. If the marker sits on a \
    question-number label, select the question attached to that label. Do not select a different \
    question merely because its number happens to be nearer the marker than the text being pointed \
    at. Read the selected question's complete stem and all of its options directly from the image.

    Only reply "Target question unclear. Point at its text and retry." if the marker is not on or \
    beside any question at all (e.g. it points at blank space, a toolbar, or the desktop). If a \
    question is present at the marker, answer it — do not refuse merely because the pointer is \
    slightly off the text.

    Solve the question first; the goal is the correct answer, whatever its language. Write the answer \
    in the form the question expects: if it asks for an English word, sentence, spelling, translation, \
    or a code/formula, give that in English (or as written); otherwise use the question's own language \
    (a Korean question gets a Korean answer, an English question an English answer).

    Output ONLY the answer. Never copy, quote, transcribe, or restate the question text or its \
    options. Reading the question is your private step; the user already sees it. If you notice \
    you are about to write the question itself, stop and write its answer instead.

    Keep any optional explanation to at most one short sentence, and use plain text (no markdown formatting).
    """

    // MARK: - Non-streaming (multiple-choice)

    func solveMultipleChoice(imageBase64: String, pointerDescription: String) async throws -> MCBatchResponse {
        let userText = buildUserMessage(pointerDescription: pointerDescription)
        let messages = [
            ChatMessage.system(Self.multipleChoiceSystemPrompt),
            ChatMessage.user(userText, imageBase64: imageBase64),
        ]

        let body = ChatCompletionRequest(
            model: SettingsStore.shared.modelName,
            messages: messages,
            stream: false,
            temperature: 0.2,
            responseFormat: ["type": "json_object"]
        )

        let data = try await post(body: body)
        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = response.choices?.first?.message?.content else {
            throw AIError.emptyResponse
        }
        return try Self.parseMCResponse(content)
    }

    // MARK: - Streaming (freeform)

    func solveFreeformStream(imageBase64: String, pointerDescription: String) -> AsyncThrowingStream<String, Error> {
        let userText = buildUserMessage(pointerDescription: pointerDescription)
        let messages = [
            ChatMessage.system(Self.freeformSystemPrompt),
            ChatMessage.user(userText, imageBase64: imageBase64),
        ]

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let body = ChatCompletionRequest(
                        model: SettingsStore.shared.modelName,
                        messages: messages,
                        stream: true,
                        temperature: 0.2,
                        responseFormat: nil
                    )
                    let base = SettingsStore.shared.providerBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "chat/completions", with: "")
                        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    let urlString = base.hasSuffix("/v1") ? "\(base)/chat/completions" : "\(base)/v1/chat/completions"
                    guard let url = URL(string: urlString) else {
                        throw AIError.invalidURL
                    }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(SettingsStore.shared.apiKey)", forHTTPHeaderField: "Authorization")
                    request.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        throw AIError.httpError((response as? HTTPURLResponse)?.statusCode ?? -1)
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }
                        guard let jsonData = payload.data(using: .utf8) else { continue }
                        if let chunk = try? JSONDecoder().decode(StreamChunk.self, from: jsonData),
                           let delta = chunk.choices?.first?.delta?.content {
                            continuation.yield(delta)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Connection test

    /// Sends a minimal text-only request to verify the endpoint and key work.
    func testConnection() async throws -> String {
        let messages = [
            ChatMessage.user("Reply with exactly: OK")
        ]
        let body = ChatCompletionRequest(
            model: SettingsStore.shared.modelName,
            messages: messages,
            stream: false,
            temperature: 0,
            responseFormat: nil
        )
        let data = try await post(body: body)
        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        let content = response.choices?.first?.message?.content ?? "(empty)"
        return "Connected — model replied: \(content.prefix(40))"
    }

    // MARK: - Helpers

    private func buildUserMessage(pointerDescription: String) -> String {
        "This is the full uncropped display. The saved pointer target is \(pointerDescription), " +
        "shown by the pink marker. Identify and solve the question the marker points at."
    }

    private func post(body: ChatCompletionRequest) async throws -> Data {
        let base = SettingsStore.shared.providerBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "chat/completions", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString = base.hasSuffix("/v1") ? "\(base)/chat/completions" : "\(base)/v1/chat/completions"
        guard let url = URL(string: urlString) else {
            throw AIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(SettingsStore.shared.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIError.httpErrorWithBody(http.statusCode, body)
        }
        return data
    }

    /// Parse the model's content into an MCBatchResponse, tolerating markdown fences.
    static func parseMCResponse(_ content: String) throws -> MCBatchResponse {
        var json = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if json.hasPrefix("```") {
            json = json
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = json.data(using: .utf8) else { throw AIError.parseFailed }
        do {
            return try JSONDecoder().decode(MCBatchResponse.self, from: data)
        } catch {
            // Try to find a JSON object in the text
            if let start = json.firstIndex(of: "{"), let end = json.lastIndex(of: "}") {
                let substring = String(json[start...end])
                if let data2 = substring.data(using: .utf8) {
                    return try JSONDecoder().decode(MCBatchResponse.self, from: data2)
                }
            }
            throw AIError.parseFailed
        }
    }

    enum AIError: Error, LocalizedError {
        case invalidURL
        case invalidResponse
        case emptyResponse
        case parseFailed
        case httpError(Int)
        case httpErrorWithBody(Int, String)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid provider URL."
            case .invalidResponse: return "Invalid response from provider."
            case .emptyResponse: return "Provider returned an empty response."
            case .parseFailed: return "Could not parse the model's answer."
            case .httpError(let code): return "Provider HTTP error: \(code)"
            case .httpErrorWithBody(let code, let body): return "Provider HTTP \(code): \(body.prefix(300))"
            }
        }
    }
}
