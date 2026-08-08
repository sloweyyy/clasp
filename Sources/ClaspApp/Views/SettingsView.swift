import AppKit
import ClaspCore
import SwiftUI

struct SettingsView: View {
    private static let notionIntegrationGuideURL = URL(
        string: "https://www.notion.com/help/create-integrations-with-the-notion-api"
    )!
    private static let notionPageAccessGuideURL = URL(
        string: "https://developers.notion.com/guides/get-started/internal-connections#from-the-notion-ui"
    )!

    @ObservedObject var model: AppModel

    @State private var token = ""
    @State private var parentPageID = ""
    @State private var agentWorkspacePath = ""
    @State private var showingRemoveConfirmation = false

    var body: some View {
        ZStack {
            ClaspBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        ClaspLogoView(size: 50)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Settings")
                                .font(.system(size: 23, weight: .bold, design: .rounded))
                            Text("Connect your tools and shape how Clasp works")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.bottom, 2)

                    notionSection
                    agentSection
                    permissionSection
                    shortcutSection

                    if let message = model.statusMessage {
                        ClaspStatusBanner(message: message)
                    }
                }
                .padding(22)
            }
        }
        .frame(width: 620)
        .frame(minHeight: 720)
        .task {
            await model.load()
            if !model.hasToken {
                await model.refreshCredentialState()
            }
            parentPageID = model.destinations?.parentPageID ?? parentPageID
            agentWorkspacePath = model.agentWorkspacePath
        }
        .confirmationDialog(
            "Remove the Notion connection?",
            isPresented: $showingRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Connection", role: .destructive) {
                Task { await model.removeConnection() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The token and local destination mapping will be removed. The Notion databases and local captures will remain.")
        }
    }

    private var agentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ClaspSectionHeading(
                "Coding agent",
                icon: "sparkles",
                subtitle: "Choose which agent picks up your tasks"
            )

            Picker("Coding agent", selection: Binding(
                get: { model.codingAgent },
                set: { model.setCodingAgent($0) }
            )) {
                ForEach(CodingAgent.allCases) { agent in
                    Text(agent.displayName).tag(agent)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if model.codingAgent == .claudeCode {
                if let cliPath = ClaudeCodeCLI.executableURL()?.path {
                    Text("Claude Code CLI: \(cliPath)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("The Claude Code CLI was not found. Install it and run claude once in Terminal to sign in.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Picker("Autonomy", selection: Binding(
                    get: { model.claudePermissionMode },
                    set: { model.setClaudePermissionMode($0) }
                )) {
                    ForEach(ClaudeCodePermissionMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .frame(maxWidth: 320, alignment: .leading)

                Text(model.claudePermissionMode.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            TextField("Workspace folder", text: $agentWorkspacePath)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .accessibilityLabel("Agent workspace folder")

            HStack {
                Button {
                    chooseAgentWorkspaceFolder()
                } label: {
                    Label("Choose Folder…", systemImage: "folder")
                }
                Spacer()
                Button("Save Workspace") {
                    if model.saveAgentWorkspacePath(agentWorkspacePath) {
                        agentWorkspacePath = model.agentWorkspacePath
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(ClaspBrand.accent)
            }

            Text(
                "New \(model.codingAgent.displayName) conversations run in this folder by default and inherit its project instructions, skills, and configuration."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .claspCard()
    }

    private func chooseAgentWorkspaceFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Workspace"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if !agentWorkspacePath.isEmpty {
            panel.directoryURL = URL(
                fileURLWithPath: agentWorkspacePath,
                isDirectory: true
            )
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        agentWorkspacePath = url.path
        if model.saveAgentWorkspacePath(url.path) {
            agentWorkspacePath = model.agentWorkspacePath
        }
    }

    private var notionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ClaspSectionHeading(
                "Notion",
                icon: "square.grid.2x2",
                subtitle: "Sync tasks and bookmarks with your private workspace"
            )

            destinationStatus

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Notion integration token")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Link(destination: Self.notionIntegrationGuideURL) {
                        Label("How to get a token", systemImage: "questionmark.circle")
                    }
                    .font(.caption)
                    .accessibilityHint("Opens Notion’s integration setup guide in your browser")
                }
                SecureField(
                    model.hasToken
                        ? "Leave blank to keep the token stored in Keychain"
                        : "Paste your Notion integration token",
                    text: $token
                )
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .textContentType(.password)
                .accessibilityLabel("Notion integration token")
            }
            .padding(.vertical, 3)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Parent page URL or ID")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Link(destination: Self.notionPageAccessGuideURL) {
                        Label("How to connect a page", systemImage: "link")
                    }
                    .font(.caption)
                    .accessibilityHint("Opens Notion’s page access instructions in your browser")
                }
                TextField("Paste the shared Notion page URL or ID", text: $parentPageID)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .textContentType(.URL)
                    .accessibilityLabel("Notion parent page URL or ID")
                Text("Clasp creates “Clasp Tasks” and “Clasp Bookmarks” as full-page databases under this page.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)

            HStack {
                Button(model.destinations == nil ? "Create Clasp Databases" : "Find or Revalidate") {
                    Task {
                        let succeeded = await model.provisionConnection(
                            token: token,
                            parentPageID: parentPageID
                        )
                        if succeeded {
                            token = ""
                            parentPageID = model.destinations?.parentPageID ?? parentPageID
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(ClaspBrand.accent)
                .disabled(model.isBusy || setupValuesMissing)

                if model.isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Creating or validating Clasp databases")
                }

                Spacer()

                if model.hasToken {
                    Button("Remove…", role: .destructive) {
                        showingRemoveConfirmation = true
                    }
                }
            }

            if setupValuesMissing {
                Text("Enter an integration token and shared parent page to enable setup.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            DisclosureGroup("Databases Clasp creates") {
                VStack(alignment: .leading, spacing: 8) {
                    schemaRow(
                        "Clasp Tasks",
                        "Name · Source · Due Date · Priority · Notes · Created Date · Progress · Done"
                    )
                    schemaRow(
                        "Clasp Bookmarks",
                        "Name · Source · Created Date · Done"
                    )
                }
                .padding(.vertical, 4)
            }

            Text("Enable Read, Insert, and Update content, then share the parent page with your integration. The token stays in your Mac’s Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .claspCard()
    }

    @ViewBuilder
    private var destinationStatus: some View {
        if let destinations = model.destinations, model.hasToken {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Connected")
                        .font(.callout.weight(.semibold))
                    Text("\(destinations.tasks.dataSourceName) · \(destinations.bookmarks.dataSourceName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(.green.opacity(0.075), in: RoundedRectangle(cornerRadius: 12))
        } else if let destinations = model.destinations {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "key.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Keychain access required")
                        .font(.callout.weight(.semibold))
                    Text(
                        "\(destinations.tasks.dataSourceName) and \(destinations.bookmarks.dataSourceName) are mapped, but Clasp cannot read the saved token. Allow Keychain access or paste the token again."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(12)
            .background(.orange.opacity(0.075), in: RoundedRectangle(cornerRadius: 12))
        } else {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Not connected")
                        .font(.callout.weight(.semibold))
                    Text("Add a token and parent page to get started.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(.orange.opacity(0.075), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var setupValuesMissing: Bool {
        parentPageID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (!model.hasToken
                && token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ClaspSectionHeading(
                "Accessibility",
                icon: "hand.raised",
                subtitle: "Read selected text only when you invoke Capture"
            )

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Selection access")
                        .font(.callout.weight(.medium))
                    Text(
                        "Clasp reads the selected text and exposed source metadata only when you invoke Capture. It does not monitor typing."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 18)
                Label(
                    model.accessibilityGranted ? "Enabled" : "Not enabled",
                    systemImage: model.accessibilityGranted
                        ? "checkmark.circle.fill"
                        : "lock.circle"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(model.accessibilityGranted ? Color.green : Color.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    (model.accessibilityGranted ? Color.green : Color.secondary).opacity(0.10),
                    in: Capsule()
                )
            }

            HStack {
                Button("Request Access") {
                    model.requestAccessibilityPermission()
                }
                Button("Open Privacy Settings") {
                    if let url = URL(
                        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                    ) {
                        NSWorkspace.shared.open(url)
                    }
                }
                Spacer()
                Button("Check Again") {
                    model.recheckAccessibilityPermission()
                }
            }
        }
        .claspCard()
    }

    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ClaspSectionHeading(
                "Global shortcut",
                icon: "command",
                subtitle: "Open Capture from anywhere on your Mac"
            )

            Picker("Key", selection: $model.shortcut.keyCode) {
                ForEach(GlobalShortcut.availableKeys, id: \.code) { key in
                    Text(key.label).tag(key.code)
                }
            }
            .onChange(of: model.shortcut.keyCode) { _, code in
                model.shortcut.keyLabel = GlobalShortcut.availableKeys
                    .first(where: { $0.code == code })?.label ?? "Key"
            }

            HStack {
                Toggle("⌘", isOn: $model.shortcut.command)
                    .help("Command")
                Toggle("⌃", isOn: $model.shortcut.control)
                    .help("Control")
                Toggle("⌥", isOn: $model.shortcut.option)
                    .help("Option")
                Toggle("⇧", isOn: $model.shortcut.shift)
                    .help("Shift")
            }

            HStack {
                Text(model.shortcut.displayName)
                    .font(.title3.monospaced().weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                Spacer()
                Button("Apply Shortcut") {
                    model.applyShortcut()
                }
                .buttonStyle(.borderedProminent)
                .tint(ClaspBrand.accent)
                .disabled(!model.shortcut.isValid)
            }

            Text("Clasp registers only this shortcut; it does not install a general keyboard monitor.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .claspCard()
    }

    private func schemaRow(_ database: String, _ fields: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(database).font(.callout.weight(.medium))
            Text(fields).font(.caption).foregroundStyle(.secondary)
        }
    }
}
