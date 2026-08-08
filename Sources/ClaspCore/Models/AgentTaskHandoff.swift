import Foundation

public enum AgentTaskOutcome: String, CaseIterable, Sendable {
    case completed = "COMPLETED"
    case waiting = "WAITING"
    case failed = "FAILED"

    public var progress: TaskProgress {
        switch self {
        case .completed: .completed
        case .waiting: .waiting
        case .failed: .failed
        }
    }

    public var marker: String {
        "<!-- CLASP_TASK_STATUS: \(rawValue) -->"
    }

    public static func declared(in agentMessage: String) -> Self? {
        let trimmed = agentMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return allCases.first { trimmed.hasSuffix($0.marker) }
    }
}

public enum AgentTaskHandoff {
    public static func prompt(
        for item: NotionListItem,
        instruction: String
    ) -> String {
        var sections = [
            "Task ID: \(item.taskID)",
            "Task: \(item.title.isEmpty ? "Untitled Task" : item.title)"
        ]
        if let notionURL = item.url {
            sections.append("Notion task: \(notionURL.absoluteString)")
        }
        if !item.notes.isEmpty { sections.append("Notes: \(item.notes)") }
        if !item.source.isEmpty { sections.append("Source: \(item.source)") }
        if let priority = item.priority {
            sections.append("Priority: \(priority.displayName)")
        }
        if let dueDate = item.dueDate {
            sections.append("Due date: \(dueDate.formatted(.iso8601.year().month().day()))")
        }
        let trimmedInstruction = instruction.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !trimmedInstruction.isEmpty {
            sections.append("Additional instruction: \(trimmedInstruction)")
        }
        sections.append("""
        Work on this task. Ask for clarification when required.

        Task lifecycle rules for Clasp:
        - Completing a response or agent turn does not by itself complete the task.
        - Do not change the Notion Done checkbox unless the user explicitly asks you to mark the task done.
        - End every final response with exactly one hidden status marker:
          \(AgentTaskOutcome.completed.marker) only when all requested work is genuinely finished.
          \(AgentTaskOutcome.waiting.marker) when work remains or you need user input, approval, or clarification.
          \(AgentTaskOutcome.failed.marker) only when the task cannot be completed because of an unrecoverable failure.
        """)
        return sections.joined(separator: "\n")
    }
}
