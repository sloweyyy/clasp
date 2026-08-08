# Clasp

Clasp is a private, keyboard-first macOS menu-bar utility that turns selected text from another
app into a Task or Bookmark in Notion.

The repository is developed with [GitHub Spec Kit](https://github.com/github/spec-kit). Product
requirements, architecture decisions, contracts, and implementation tasks live in
[`specs/001-capture-to-notion`](specs/001-capture-to-notion/).

## Features

Clasp opens from the macOS menu bar or a configurable global shortcut. It uses Accessibility
to capture selected text and source context, with an explicit temporary Copy fallback for apps
such as Slack that do not expose their selection. The previous clipboard contents are restored
immediately.

### Capture from any app

1. Select text in the app where you are working.
2. Press Clasp's configurable global shortcut—for example, `⌥⌘C`
   (Option–Command–C).
3. Clasp opens the Create Task/Bookmark dialog with the selected text and detected source.
4. Choose Task or Bookmark, review the details, and save it to Notion.

Clasp records the most useful source for the selected content:

| Selected from | Source saved by Clasp |
|---|---|
| Gmail | Link to the email |
| Slack | Permalink to the exact Slack message |
| A local file | File path |
| A webpage | Page URL |

The Source remains editable when an application cannot expose its exact location.

### Task Management

![Task management in Clasp](docs/images/features/task-management.jpg)

- Capture selected text as a Task or create one manually from the main window.
- Track Name, Source, Due Date, Priority, Notes, Progress, Created Date, and Done in Notion.
- Edit Priority and Due Date directly in Clasp.
- Sort active Tasks by Priority—High, Medium, then Low—and then by earliest Due Date.
- Mark a Task done to hide it from Clasp without deleting its Notion page.
- Delete a Task from Clasp with confirmation when it should be moved to Notion Trash.
- Preserve confirmed captures locally before delivery and retain failed deliveries for retry.

#### Hand a Task to Claude Code or Codex in seconds

Every Task has an **Ask Claude** or **Ask Codex** action, depending on the coding agent selected
in Settings. Click it to open a focused handoff dialog, add an optional instruction, choose the
local project where the work belongs, and start the session. Clasp sends the Task name, Notes,
Priority, Due Date, Source, and a direct link to its Notion page as the conversation context.

![Starting a Codex session from a Clasp Task](docs/images/features/ask-codex.jpg)

Clasp immediately creates a persistent conversation tagged with the Task's stable
`CLASP-XXXXXXXX` ID and replaces the ask action with **Open Conversation**. The Task remains
linked to its conversation, while Clasp synchronizes Working, Waiting, Completed, or Failed
Progress back to Notion. Completing the agent's work does not check the separate Done checkbox
unless you explicitly request it.

### Bookmark Management

![Bookmark management in Clasp](docs/images/features/bookmark-management.jpg)

- Capture selected text as a Bookmark or create one manually from the main window.
- Track Name, Source, Created Date, and Done in a dedicated Notion database.
- Open source links and the corresponding Notion page directly from Clasp.
- Mark a Bookmark done to hide it from the active list, or move it to Notion Trash with the
  confirmed Delete action.
- Preserve confirmed captures locally before delivery and retain failed deliveries for retry.

### Pomodoro Timer

![Mochi accompanying a Pomodoro break in Clasp](docs/images/features/pomodoro-timer.jpg)

- Run a 25-minute Focus session or a 5-minute Break from above the Tasks and Bookmarks tabs.
- Start, pause, resume, and reset the timer while viewing its remaining time and progress.
- Meet Mochi, the animated break companion, during Break sessions.
- Play an original relaxing ambient soundscape during a Break, with an accessible audio toggle.

### Integrations

![Notion synchronization and Codex task controls in Clasp](docs/images/features/integrations.jpg)

Clasp hands Tasks to your preferred coding agent—Claude Code or Codex—selected in Settings.
Claude Code is the default when its CLI is installed.

#### Notion

- Create and validate dedicated `Clasp Tasks` and `Clasp Bookmarks` databases under a shared
  parent page.
- Load active Tasks and Bookmarks into separate tabs and synchronize edits back to Notion.
- Store the Notion integration token only in macOS Keychain.
- Route every entry to its type-specific database without sending analytics or captured content
  elsewhere.

#### Claude Code

- Hand a Task to a persistent Claude Code session with an optional instruction.
- Run the locally installed `claude` CLI headlessly in the selected project folder, so the
  session inherits that project's `CLAUDE.md`, skills, and configuration.
- Choose from project folders discovered from previous Claude Code sessions, with a configurable
  default.
- Pick the autonomy level in Settings: apply file edits only (default), or also run commands
  without asking in projects you trust.
- **Open Conversation** opens Terminal and resumes the exact session with `claude --resume`,
  in the same project folder.
- Include the stable Clasp Task ID and a link to the Notion Task in the conversation, and mirror
  the session's lifecycle Progress to Notion without automatically checking Done.

#### Codex

- Hand a Task to a persistent Codex conversation with an optional instruction.
- Choose from dynamically discovered local Codex project folders, with a configurable default.
- Include the stable Clasp Task ID and a link to the Notion Task in the conversation.
- Show the conversation link immediately while Codex works and mirror its lifecycle Progress to
  Notion without automatically checking Done.

## Requirements

- macOS 14 or later.
- Apple Silicon for the initial supported release.
- Swift 6 for command-line builds and tests.
- Full Xcode for creating a stable `.app`, signing, notarization, UI tests, and release builds.
- A Notion internal integration with Read content, Insert content, and Update content capabilities.
- Optional: the [Claude Code](https://claude.com/claude-code) CLI for **Ask Claude**, or the
  Codex desktop app for **Ask Codex**.

The Accessibility-based build is intended for direct Developer ID distribution and does not
enable App Sandbox. A sandboxed Mac App Store build cannot provide equivalent arbitrary-app
selection access.

## Notion setup

1. Create a Notion internal integration by following
   [Notion’s official integration setup guide](https://www.notion.com/help/create-integrations-with-the-notion-api).
2. Enable Read content, Insert content, and Update content capabilities.
3. Create or choose a Notion page that will contain Clasp’s databases.
4. [Share that parent page with the integration](https://developers.notion.com/guides/get-started/internal-connections#from-the-notion-ui).
5. Clasp creates these databases automatically:

| Database | Properties |
|---|---|
| Clasp Tasks | Name, Source, Due Date, Priority, Notes, Progress, Created Date, Done |
| Clasp Bookmarks | Name, Source, Created Date, Done |

6. In Clasp Settings, enter the integration token and shared parent page URL or ID.
7. Select **Create Clasp Databases**. The token is written to Keychain only after both
   destinations are ready.

Clasp pins the Notion REST API to `2026-03-11`. Setup reuses exact compatible managed database
titles under the parent page, which makes retrying a partially completed setup safe.

## Accessibility permission

Clasp does not request Accessibility access at launch. Settings explains the feature before
opening the macOS prompt. On capture, Clasp snapshots the frontmost app and reads only its
currently selected text. It does not install a general key logger or monitor typing.

Clasp also inspects source metadata around the selected range. It prefers Gmail email URLs,
local file paths, webpage URLs, and exposed Slack message permalinks. Source remains editable
because some app versions expose only a channel/page URL or no location at all.

If permission is denied or an app does not expose selection, Clasp opens an empty editable
draft. Clipboard content appears only after the explicit **Paste** action.

## Build and test

```bash
swift build
swift test
```

Run the command-line development executable:

```bash
swift run ClaspApp
```

Create an ad-hoc-signed local application bundle:

```bash
./scripts/package-app.sh
open dist/Clasp.app
```

To provide a local default for the Ask Claude / Ask Codex project picker, copy `.env.example` to
`.env` and set `CLASP_DEFAULT_CODEX_WORKSPACE_PATH`. The ignored `.env` is loaded by the packaging
script; its value is embedded only in that local app bundle. Release builds should omit this
setting.

On the first launch, Clasp opens its setup window. After setup, it remains in the menu bar and
opens in **Medium** mode by default. Use the menu-bar **Window Mode** menu to switch among Mini
(menu bar only), Medium (compact window), and Maximum (full-size window). Use **Open Clasp** from
the menu bar at any time, refresh to load the latest Notion entries, or press `⌘N` to create an
entry in the selected tab.

Set `CLASP_CODESIGN_IDENTITY` to a Developer ID Application identity to create a distribution
candidate. Notarization still requires the full Apple release toolchain and credentials.

The Swift package verifies the app and core code, but `swift run` is not a production app
bundle. Accessibility permission is tied to code identity and executable location, so repeated
development builds outside the packaging script may need permission refreshed. Ad-hoc packages
embed a stable local designated requirement for `com.clasp.app`, while Developer ID builds use
Apple's signed requirement. The packaging script uses
[`Resources/Info.plist`](Resources/Info.plist) and places the stable development bundle at
`dist/Clasp.app`.

The tests use Apple's open-source Swift Testing package only because this machine's standalone
Command Line Tools omit the bundled XCTest/Testing modules. It is a test-only dependency;
Clasp has no third-party runtime dependency.

## Local data and privacy

- Token: macOS Keychain service `com.clasp.app.notion`.
- Capture outbox: `~/Library/Application Support/Clasp/clasp-store.json`.
- Store permissions: owner read/write only (`0600`).
- Store backup: `clasp-store.json.backup`.
- Logs: lifecycle events only; no token, selected text, request payload, or Notion response body.

Deleting a local delivered capture does not delete its Notion page. Removing the connection
removes the token from Keychain and leaves local captures intact.

## Project structure

```text
Sources/
├── ClaspCore/   # Models, atomic outbox, Keychain, Notion client, services
└── ClaspApp/    # Menu-bar lifecycle, Accessibility, hotkey, native views
Tests/
└── ClaspCoreTests/
specs/
└── 001-capture-to-notion/
```

## License

Apache License 2.0. See [`LICENSE`](LICENSE).
