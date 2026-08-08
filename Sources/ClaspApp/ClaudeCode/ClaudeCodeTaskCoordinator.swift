import ClaspCore
import Foundation

enum ClaudeCodeTaskError: LocalizedError {
    case cliNotInstalled
    case couldNotStart
    case workspaceUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .cliNotInstalled:
            "Install the Claude Code CLI before using Ask Claude."
        case .couldNotStart:
            "Clasp could not start Claude Code. Run claude once in Terminal, sign in, and try again."
        case let .workspaceUnavailable(path):
            "The configured Claude Code project folder is unavailable: \(path)"
        }
    }
}

struct ClaudeCodeSessionReference: Equatable, Sendable {
    let sessionID: String
    let workspacePath: String
}

@MainActor
final class ClaudeCodeTaskCoordinator {
    typealias ProgressHandler = @MainActor (String, TaskProgress) async -> Void
    typealias SessionReleasedHandler = @MainActor (ClaudeCodeSessionReference) -> Void

    private final class Session: @unchecked Sendable {
        let pageID: String
        let reference: ClaudeCodeSessionReference
        let process: Process
        let output: FileHandle
        var buffer = Data()
        var startContinuation: CheckedContinuation<Void, Error>?
        var initialized = false
        var reachedTerminalState = false

        init(
            pageID: String,
            reference: ClaudeCodeSessionReference,
            process: Process,
            output: FileHandle
        ) {
            self.pageID = pageID
            self.reference = reference
            self.process = process
            self.output = output
        }
    }

    private let onProgress: ProgressHandler
    private let onSessionReleased: SessionReleasedHandler
    private var sessionsByID: [String: Session] = [:]

    init(
        onProgress: @escaping ProgressHandler,
        onSessionReleased: @escaping SessionReleasedHandler
    ) {
        self.onProgress = onProgress
        self.onSessionReleased = onSessionReleased
    }

    func start(
        item: NotionListItem,
        instruction: String,
        workspacePath: String,
        permissionMode: ClaudeCodePermissionMode
    ) async throws -> String {
        let workspaceURL = URL(fileURLWithPath: workspacePath, isDirectory: true)
            .standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: workspaceURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw ClaudeCodeTaskError.workspaceUnavailable(workspaceURL.path)
        }
        guard let executableURL = ClaudeCodeCLI.executableURL() else {
            throw ClaudeCodeTaskError.cliNotInstalled
        }

        let sessionID = UUID().uuidString.lowercased()
        let reference = ClaudeCodeSessionReference(
            sessionID: sessionID,
            workspacePath: workspaceURL.path
        )
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = [
            "--print",
            "--output-format", "stream-json",
            "--verbose",
            "--permission-mode", permissionMode.rawValue,
            "--session-id", sessionID,
            AgentTaskHandoff.prompt(for: item, instruction: instruction)
        ]
        process.currentDirectoryURL = workspaceURL
        process.environment = ClaudeCodeCLI.environment(for: executableURL)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        let session = Session(
            pageID: item.id,
            reference: reference,
            process: process,
            output: outputPipe.fileHandleForReading
        )
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self, weak session] handle in
            let data = handle.availableData
            Task { @MainActor in
                guard let self, let session else { return }
                if data.isEmpty {
                    self.finishUnexpectedly(session)
                } else {
                    self.receive(data, from: session)
                }
            }
        }

        do {
            try process.run()
        } catch {
            session.output.readabilityHandler = nil
            throw ClaudeCodeTaskError.couldNotStart
        }

        sessionsByID[sessionID] = session
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                session.startContinuation = continuation
            }
        } catch {
            sessionsByID.removeValue(forKey: sessionID)
            session.output.readabilityHandler = nil
            if session.process.isRunning {
                session.process.terminate()
            }
            throw error
        }
        save(reference, for: item.id)
        return sessionID
    }

    func availableProjects(defaultPath: String) async -> [AgentProjectOption] {
        let discoveredPaths = await Task.detached(priority: .utility) {
            ClaudeCodeSessionIndex.discoverProjectPaths()
        }.value
        return AgentProjectCatalog.options(
            defaultPath: defaultPath,
            discoveredPaths: discoveredPaths
        )
    }

    func isSessionActive(for pageID: String) -> Bool {
        guard let reference = savedSession(for: pageID) else { return false }
        return sessionsByID[reference.sessionID] != nil
    }

    func savedSession(for pageID: String) -> ClaudeCodeSessionReference? {
        guard let entry = associations()[pageID],
              let sessionID = entry["sessionID"],
              let workspacePath = entry["workspacePath"]
        else {
            return nil
        }
        return ClaudeCodeSessionReference(
            sessionID: sessionID,
            workspacePath: workspacePath
        )
    }

    func removeSavedSession(for pageID: String) {
        var associations = associations()
        associations.removeValue(forKey: pageID)
        UserDefaults.standard.set(associations, forKey: Self.associationsKey)
    }

    private func receive(_ data: Data, from session: Session) {
        session.buffer.append(data)
        while let newline = session.buffer.firstIndex(of: 0x0A) {
            let line = session.buffer[..<newline]
            session.buffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            handle(Data(line), from: session)
        }
    }

    private func handle(_ line: Data, from session: Session) {
        switch ClaudeCodeStreamEvent.parse(line: line) {
        case .initialized:
            session.initialized = true
            session.startContinuation?.resume()
            session.startContinuation = nil
        case let .result(result):
            session.reachedTerminalState = true
            emit(result.progress, for: session)
            stop(session)
        case nil:
            break
        }
    }

    private func emit(_ progress: TaskProgress, for session: Session) {
        let pageID = session.pageID
        Task { @MainActor [onProgress] in
            await onProgress(pageID, progress)
        }
    }

    private func finishUnexpectedly(_ session: Session) {
        session.output.readabilityHandler = nil
        if let continuation = session.startContinuation {
            session.startContinuation = nil
            continuation.resume(throwing: ClaudeCodeTaskError.couldNotStart)
            return
        }
        if !session.reachedTerminalState {
            emit(.failed, for: session)
        }
        stop(session)
    }

    private func stop(_ session: Session) {
        session.output.readabilityHandler = nil
        sessionsByID.removeValue(forKey: session.reference.sessionID)
        if session.process.isRunning {
            session.process.terminate()
        }
        guard session.initialized else { return }
        let reference = session.reference
        Task { @MainActor [onSessionReleased] in
            try? await Task.sleep(for: .milliseconds(250))
            onSessionReleased(reference)
        }
    }

    private static let associationsKey = "clasp.claudeTaskSessionAssociations"

    private func save(_ reference: ClaudeCodeSessionReference, for pageID: String) {
        var associations = associations()
        associations[pageID] = [
            "sessionID": reference.sessionID,
            "workspacePath": reference.workspacePath
        ]
        UserDefaults.standard.set(associations, forKey: Self.associationsKey)
    }

    private func associations() -> [String: [String: String]] {
        UserDefaults.standard.dictionary(
            forKey: Self.associationsKey
        ) as? [String: [String: String]] ?? [:]
    }
}
