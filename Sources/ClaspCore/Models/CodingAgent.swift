import Foundation

public enum CodingAgent: String, CaseIterable, Identifiable, Sendable {
    case claudeCode = "claude-code"
    case codex = "codex"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }

    public var askActionTitle: String {
        switch self {
        case .claudeCode: "Ask Claude"
        case .codex: "Ask Codex"
        }
    }
}
