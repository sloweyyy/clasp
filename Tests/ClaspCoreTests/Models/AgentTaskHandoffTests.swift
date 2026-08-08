import ClaspCore
import Foundation
import Testing

@Suite("Agent task handoff")
struct AgentTaskHandoffTests {
    @Test("Includes the Notion task link and keeps Done separate from Progress")
    func buildsLifecycleAwarePrompt() {
        let item = NotionListItem(
            id: "2ab1cf9f-0000-0000-0000-000000000000",
            url: URL(string: "https://www.notion.so/2ab1cf9f000000000000000000000000"),
            type: .task,
            title: "Review environment cleanup",
            source: "https://mail.google.com/example",
            notes: "Prepare a customer-facing response",
            priority: .high
        )

        let prompt = AgentTaskHandoff.prompt(
            for: item,
            instruction: "Check the implementation"
        )

        #expect(prompt.contains("Notion task: https://www.notion.so/2ab1cf9f000000000000000000000000"))
        #expect(prompt.contains("Do not change the Notion Done checkbox"))
        #expect(prompt.contains(AgentTaskOutcome.completed.marker))
        #expect(prompt.contains(AgentTaskOutcome.waiting.marker))
        #expect(prompt.contains(AgentTaskOutcome.failed.marker))
    }

    @Test("Recognizes only an explicit completion declaration")
    func parsesExplicitOutcome() {
        #expect(AgentTaskOutcome.declared(in: "Work finished.") == nil)
        #expect(AgentTaskOutcome.declared(
            in: "Work finished.\n\(AgentTaskOutcome.completed.marker)"
        ) == .completed)
        #expect(AgentTaskOutcome.declared(
            in: "I need access.\n\(AgentTaskOutcome.waiting.marker)"
        ) == .waiting)
    }
}
