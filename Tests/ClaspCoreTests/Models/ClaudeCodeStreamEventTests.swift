import ClaspCore
import Foundation
import Testing

@Suite("Claude Code stream events")
struct ClaudeCodeStreamEventTests {
    @Test("Parses the init event and ignores unrelated events")
    func parsesInitEvent() {
        let initLine = Data(#"""
        {"type":"system","subtype":"init","cwd":"/tmp/project","session_id":"f75861bd-de07-4576-9404-94821c3a7ac4","tools":["Bash"]}
        """#.utf8)
        #expect(ClaudeCodeStreamEvent.parse(line: initLine)
            == .initialized(sessionID: "f75861bd-de07-4576-9404-94821c3a7ac4"))

        let hookLine = Data(#"""
        {"type":"system","subtype":"hook_started","session_id":"f75861bd"}
        """#.utf8)
        #expect(ClaudeCodeStreamEvent.parse(line: hookLine) == nil)

        #expect(ClaudeCodeStreamEvent.parse(line: Data("not json".utf8)) == nil)
    }

    @Test("A successful run requires the declared marker to complete the task")
    func mapsResultToProgress() throws {
        let marked = Data(#"""
        {"type":"result","subtype":"success","is_error":false,"result":"Done.\n\#(AgentTaskOutcome.completed.marker)","session_id":"abc"}
        """#.utf8)
        guard case let .result(markedResult)? = ClaudeCodeStreamEvent.parse(line: marked) else {
            Issue.record("Expected a result event")
            return
        }
        #expect(markedResult.progress == .completed)

        let unmarked = ClaudeCodeRunResult(
            isError: false,
            subtype: "success",
            text: "Turn ended without a declaration."
        )
        #expect(unmarked.progress == .waiting)

        let errored = ClaudeCodeRunResult(
            isError: true,
            subtype: "error_during_execution",
            text: nil
        )
        #expect(errored.progress == .failed)
    }
}
