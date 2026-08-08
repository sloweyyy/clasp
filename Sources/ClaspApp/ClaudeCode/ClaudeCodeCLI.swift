import Foundation

enum ClaudeCodePermissionMode: String, CaseIterable, Identifiable {
    case acceptEdits
    case bypassPermissions

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .acceptEdits: "Edit files only"
        case .bypassPermissions: "Full autonomy"
        }
    }

    var explanation: String {
        switch self {
        case .acceptEdits:
            "Claude Code edits files in the project without asking. Anything else waits until you open the conversation."
        case .bypassPermissions:
            "Claude Code also runs commands without asking. Use only with projects you trust."
        }
    }
}

enum ClaudeCodeCLI {
    static func executableURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates = [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.bun/bin/claude",
            "\(home)/.npm-global/bin/claude"
        ]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path.split(separator: ":").map { "\($0)/claude" }
        }
        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0)
        }.map(URL.init(fileURLWithPath:))
    }

    static var isInstalled: Bool {
        executableURL() != nil
    }

    /// Clasp launches as a GUI app with a minimal PATH, and npm-based installs
    /// resolve node through the environment, so spawned sessions get the
    /// executable's directory and the common tool directories prepended.
    static func environment(for executable: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let basePath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let existing = Set(basePath.split(separator: ":").map(String.init))
        let extra = [
            executable.deletingLastPathComponent().path,
            "/opt/homebrew/bin",
            "/usr/local/bin"
        ].filter { !existing.contains($0) }
        environment["PATH"] = (extra + [basePath]).joined(separator: ":")
        return environment
    }
}
