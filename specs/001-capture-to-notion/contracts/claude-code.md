# Claude Code Task Handoff Contract

## Availability

Clasp discovers the locally installed `claude` CLI at the common install locations
(`~/.local/bin`, `~/.claude/local`, Homebrew and npm global bin directories) and on the
inherited PATH. If it is not available, Ask Claude remains visible but reports an actionable
installation/sign-in error without changing the Task's visible Progress. Claude Code is the
default coding agent when its CLI is installed; the selection is configurable in Settings and
shares the Codex integration's workspace default.

## Conversation creation

After the user confirms the Ask Claude sheet, Clasp generates the session UUID itself and
launches one headless run in the selected project folder:

```
claude --print --output-format stream-json --verbose \
  --permission-mode <acceptEdits|bypassPermissions> \
  --session-id <uuid> <prompt>
```

The prompt contains:

- Task ID and Name
- the canonical Notion Task page link when available
- Notes, Source, Priority, and Due Date when present
- the optional user instruction when non-empty
- Clasp's lifecycle rules, including the hidden status markers

Project choices are discovered by reading the recorded `cwd` value from stored session
transcripts under `~/.claude/projects/<encoded-path>/<session-id>.jsonl`. The directory names
encode paths lossily (`/` and `.` both become `-`), so the transcript value is authoritative.
Valid folders are presented with the configured default first, and the user can choose any other
folder when a project has no recorded session yet. Clasp runs the CLI with the selected folder as
its working directory and rejects an unavailable folder rather than routing the task elsewhere.
The Task ID is deterministically derived from the normalized Notion page UUID, and the prompt
leads with it so the session is identifiable in Claude Code's resume picker.

Clasp treats the stream's `system/init` event as proof that the session exists, stores the
session ID and project folder locally, and immediately replaces Ask Claude with an
`Open Conversation` action, including while Progress is Working. Claude Code has no URL scheme
for opening a stored conversation, so Open Conversation writes a temporary `.command` script and
opens it, which launches Terminal, changes into the project folder, and resumes the exact
session with `claude --resume <session-id>`. When the run reaches a terminal state, Clasp
releases the worker, allows a short persistence grace period, and opens the conversation exactly
once. This guarantees the user has immediate access to the conversation while preserving the
automatic handoff once agent output is available.

## Progress lifecycle

Clasp is the writer of lifecycle state to Notion:

| Claude Code state | Notion Progress |
|---|---|
| No handoff | Not Started |
| Headless run active | Working |
| Run succeeded without an explicit task-complete declaration | Waiting |
| Final response explicitly declares all requested work complete | Completed |
| Startup failure, error result, or process exit without a result | Failed |

The stream's final `result` event means only that the response turn ended; it is not proof that
the requested Task is finished. The handoff therefore requires the final agent response to
declare `COMPLETED`, `WAITING`, or `FAILED` with Clasp's hidden status marker. A successful run
without a valid marker becomes Waiting. The conversation is also instructed never to change the
Task's independent `Done` checkbox unless the user explicitly asks for that action.

Headless runs cannot pause for interactive approval. With the default `acceptEdits` autonomy the
run applies file edits in the project without asking, and read-only shell commands are
auto-approved. A tool call outside the granted permissions does not abort the run: the CLI
denies it in-stream (the model receives a "requires approval" tool error and the final `result`
event lists the attempt under `permission_denials`), and the run continues to a normal result —
verified against Claude Code 2.1.226. Work that requires a denied capability is expected to end
with the `WAITING` marker so the user continues interactively through `Open Conversation`. The
`bypassPermissions` autonomy also runs commands without asking and is offered only as an
explicit Settings choice for trusted projects.

Every remote Progress update is confirmed before the main-table projection changes. The Notion
integration token is never passed to Claude Code or written to the conversation.

## Local association

The mapping from Notion page ID to Claude Code session—session ID plus project folder—is stored
in application preferences. It is used to replace Ask Claude with an Open Conversation action in
the Task table, survives Clasp restarts, and is not treated as a remote source of truth. The
project folder is stored alongside the session ID so a resumed conversation always reopens in
the folder where the session's history lives.
