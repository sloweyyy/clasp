import Foundation

/// A single newline-delimited JSON event emitted by
/// `claude --print --output-format stream-json`.
public enum ClaudeCodeStreamEvent: Equatable, Sendable {
    case initialized(sessionID: String)
    case result(ClaudeCodeRunResult)

    private struct RawEvent: Decodable {
        let type: String
        let subtype: String?
        let sessionID: String?
        let isError: Bool?
        let result: String?

        enum CodingKeys: String, CodingKey {
            case type
            case subtype
            case sessionID = "session_id"
            case isError = "is_error"
            case result
        }
    }

    public static func parse(line: Data) -> ClaudeCodeStreamEvent? {
        guard let event = try? JSONDecoder().decode(RawEvent.self, from: line) else {
            return nil
        }
        switch event.type {
        case "system" where event.subtype == "init":
            guard let sessionID = event.sessionID else { return nil }
            return .initialized(sessionID: sessionID)
        case "result":
            return .result(ClaudeCodeRunResult(
                isError: event.isError ?? (event.subtype != "success"),
                subtype: event.subtype,
                text: event.result
            ))
        default:
            return nil
        }
    }
}

/// The terminal event of a headless Claude Code run.
public struct ClaudeCodeRunResult: Equatable, Sendable {
    public let isError: Bool
    public let subtype: String?
    public let text: String?

    public init(isError: Bool, subtype: String?, text: String?) {
        self.isError = isError
        self.subtype = subtype
        self.text = text
    }

    /// A finished run only proves that the response turn ended. Task Progress
    /// requires the final response to declare Clasp's hidden status marker;
    /// a successful run without a valid marker becomes Waiting.
    public var progress: TaskProgress {
        guard !isError, subtype == "success" else { return .failed }
        guard let text, let outcome = AgentTaskOutcome.declared(in: text) else {
            return .waiting
        }
        return outcome.progress
    }
}
