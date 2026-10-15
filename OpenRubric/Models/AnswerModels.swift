import Foundation

// MARK: - OpenAI-compatible request models

struct ChatMessage: Codable {
    let role: String
    let content: [ContentPart]

    enum ContentPart: Codable {
        case text(String)
        case imageURL(url: String, detail: String?)

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case imageURL = "image_url"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let t):
                try container.encode("text", forKey: .type)
                try container.encode(t, forKey: .text)
            case .imageURL(let url, let detail):
                try container.encode("image_url", forKey: .type)
                try container.encode(["url": url, "detail": detail ?? "auto"], forKey: .imageURL)
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "text":
                self = .text(try container.decode(String.self, forKey: .text))
            case "image_url":
                let dict = try container.decode([String: String].self, forKey: .imageURL)
                self = .imageURL(url: dict["url"] ?? "", detail: dict["detail"])
            default:
                self = .text("")
            }
        }
    }

    static func system(_ text: String) -> ChatMessage {
        ChatMessage(role: "system", content: [.text(text)])
    }

    static func user(_ text: String, imageBase64: String? = nil) -> ChatMessage {
        var parts: [ContentPart] = [.text(text)]
        if let img = imageBase64 {
            parts.append(.imageURL(url: "data:image/png;base64,\(img)", detail: "high"))
        }
        return ChatMessage(role: "user", content: parts)
    }
}

struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool?
    let temperature: Double?
    let responseFormat: [String: String]?

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature
        case responseFormat = "response_format"
    }
}

// MARK: - OpenAI-compatible response models

struct ChatCompletionResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let role: String?
            let content: String?
        }
        let index: Int?
        let message: Message?
    }
    let id: String?
    let choices: [Choice]?
}

struct StreamChunk: Codable {
    struct Choice: Codable {
        struct Delta: Codable {
            let role: String?
            let content: String?
        }
        let index: Int?
        let delta: Delta?
    }
    let choices: [Choice]?
}

// MARK: - Structured multiple-choice answer

struct MCQuestionAnswer: Codable {
    let question: String
    let options: [String]
    let format: String  // "numeric" or "letter"
    let reasoning: String
    let answer: [Int]
}

struct MCBatchResponse: Codable {
    let answers: [MCQuestionAnswer]
}
