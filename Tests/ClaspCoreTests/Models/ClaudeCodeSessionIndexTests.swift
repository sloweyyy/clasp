import ClaspCore
import Foundation
import Testing

@Suite("Claude Code session index")
struct ClaudeCodeSessionIndexTests {
    @Test("Reads working directories from stored session transcripts")
    func discoversProjectPaths() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let projectA = root.appendingPathComponent("-Users-a-project", isDirectory: true)
        let projectB = root.appendingPathComponent("-Users-b-project", isDirectory: true)
        let emptyProject = root.appendingPathComponent("-Users-empty", isDirectory: true)
        for directory in [projectA, projectB, emptyProject] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        try """
        {"type":"last-prompt","sessionId":"one"}
        {"type":"user","cwd":"/Users/a/project","sessionId":"one"}
        """.write(
            to: projectA.appendingPathComponent("one.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        try """
        {"type":"user","cwd":"/Users/b/project","sessionId":"two"}
        """.write(
            to: projectB.appendingPathComponent("two.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        try "not json at all".write(
            to: emptyProject.appendingPathComponent("broken.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let paths = ClaudeCodeSessionIndex.discoverProjectPaths(projectsRoot: root)

        #expect(Set(paths) == ["/Users/a/project", "/Users/b/project"])
    }

    @Test("Returns nothing when the projects root does not exist")
    func missingRoot() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        #expect(ClaudeCodeSessionIndex.discoverProjectPaths(projectsRoot: missing).isEmpty)
    }
}
