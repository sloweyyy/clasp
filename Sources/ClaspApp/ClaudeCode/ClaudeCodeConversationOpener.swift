import AppKit
import Foundation

/// Claude Code has no URL scheme for opening a stored conversation, so Clasp
/// opens a Terminal window that resumes the session inside its project folder.
enum ClaudeCodeConversationOpener {
    @discardableResult
    static func open(_ reference: ClaudeCodeSessionReference) -> Bool {
        guard let executable = ClaudeCodeCLI.executableURL() else { return false }
        let script = """
        #!/bin/zsh
        clear
        cd \(quoted(reference.workspacePath)) || exit 1
        exec \(quoted(executable.path)) --resume \(quoted(reference.sessionID))
        """
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clasp-resume-\(reference.sessionID).command")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: scriptURL.path
            )
        } catch {
            return false
        }
        return NSWorkspace.shared.open(scriptURL)
    }

    private static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
