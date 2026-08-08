import ClaspCore
import Foundation

enum CodexTaskError: LocalizedError {
    case appNotInstalled
    case couldNotStart
    case workspaceUnavailable(String)
    case protocolFailure(String)

    var errorDescription: String? {
        switch self {
        case .appNotInstalled:
            "Install or update the Codex desktop app before using Ask Codex."
        case .couldNotStart:
            "Clasp could not start Codex. Open Codex once, sign in, and try again."
        case let .workspaceUnavailable(path):
            "The configured Codex workspace is unavailable: \(path)"
        case let .protocolFailure(message):
            "Codex could not start this task: \(message)"
        }
    }
}

@MainActor
final class CodexTaskCoordinator {
    typealias ProgressHandler = @MainActor (String, TaskProgress) async -> Void
    typealias ThreadReleasedHandler = @MainActor (String) -> Void

    private struct ThreadStartResult: Decodable {
        struct Thread: Decodable {
            let id: String
        }
        let thread: Thread
    }

    private struct ThreadListResult: Decodable {
        struct ThreadSummary: Decodable {
            let cwd: String?
        }

        let data: [ThreadSummary]
        let nextCursor: String?
    }

    private final class Session: @unchecked Sendable {
        let pageID: String
        let process: Process
        let input: FileHandle
        let output: FileHandle
        var buffer = Data()
        var nextRequestID = 1
        var pending: [Int: CheckedContinuation<Data, Error>] = [:]
        var reachedTerminalState = false
        var declaredOutcome: AgentTaskOutcome?
        let reportsProgress: Bool

        init(
            pageID: String,
            process: Process,
            input: FileHandle,
            output: FileHandle,
            reportsProgress: Bool = true
        ) {
            self.pageID = pageID
            self.process = process
            self.input = input
            self.output = output
            self.reportsProgress = reportsProgress
        }
    }

    private let onProgress: ProgressHandler
    private let onThreadReleased: ThreadReleasedHandler
    private var sessionsByThreadID: [String: Session] = [:]
    private var startingSessions: [ObjectIdentifier: Session] = [:]

    init(
        onProgress: @escaping ProgressHandler,
        onThreadReleased: @escaping ThreadReleasedHandler
    ) {
        self.onProgress = onProgress
        self.onThreadReleased = onThreadReleased
    }

    func start(
        item: NotionListItem,
        instruction: String,
        workspacePath: String
    ) async throws -> String {
        let workspaceURL = URL(fileURLWithPath: workspacePath, isDirectory: true)
            .standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: workspaceURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw CodexTaskError.workspaceUnavailable(workspaceURL.path)
        }

        let session = try openSession(pageID: item.id)
        let sessionKey = ObjectIdentifier(session)
        startingSessions[sessionKey] = session

        do {
            _ = try await request(
                "initialize",
                params: [
                    "clientInfo": [
                        "name": "clasp",
                        "title": "Clasp",
                        "version": "0.1"
                    ],
                    "capabilities": ["experimentalApi": true]
                ],
                session: session
            )
            try notify("initialized", params: nil, session: session)

            let startData = try await request(
                "thread/start",
                params: [
                    "cwd": workspaceURL.path,
                    "ephemeral": false,
                    "approvalPolicy": "never",
                    "sandbox": "workspace-write",
                    "serviceName": "Clasp"
                ],
                session: session
            )
            let threadID = try JSONDecoder().decode(
                ThreadStartResult.self,
                from: startData
            ).thread.id
            startingSessions.removeValue(forKey: sessionKey)
            sessionsByThreadID[threadID] = session

            _ = try await request(
                "thread/name/set",
                params: [
                    "threadId": threadID,
                    "name": conversationTitle(for: item)
                ],
                session: session
            )

            _ = try await request(
                "turn/start",
                params: [
                    "threadId": threadID,
                    "input": [[
                        "type": "text",
                        "text": AgentTaskHandoff.prompt(
                            for: item,
                            instruction: instruction
                        )
                    ]]
                ],
                session: session
            )
            save(threadID: threadID, for: item.id)
            return threadID
        } catch {
            startingSessions.removeValue(forKey: sessionKey)
            session.output.readabilityHandler = nil
            if session.process.isRunning {
                session.process.terminate()
            }
            throw error
        }
    }

    func availableProjects(defaultPath: String) async -> [AgentProjectOption] {
        let discoveredPaths = (try? await discoverThreadProjectPaths()) ?? []
        return AgentProjectCatalog.options(
            defaultPath: defaultPath,
            discoveredPaths: discoveredPaths
        )
    }

    func savedThreadID(for pageID: String) -> String? {
        threadAssociations()[pageID]
    }

    func removeSavedThreadID(for pageID: String) {
        var associations = threadAssociations()
        associations.removeValue(forKey: pageID)
        UserDefaults.standard.set(
            associations,
            forKey: "clasp.codexTaskThreadAssociations"
        )
    }

    private func request(
        _ method: String,
        params: [String: Any],
        session: Session
    ) async throws -> Data {
        let requestID = session.nextRequestID
        session.nextRequestID += 1
        return try await withCheckedThrowingContinuation { continuation in
            session.pending[requestID] = continuation
            do {
                try write(
                    ["id": requestID, "method": method, "params": params],
                    to: session
                )
            } catch {
                session.pending.removeValue(forKey: requestID)
                continuation.resume(throwing: error)
            }
        }
    }

    private func discoverThreadProjectPaths() async throws -> [String] {
        let session = try openSession(pageID: "project-discovery", reportsProgress: false)
        defer {
            session.reachedTerminalState = true
            session.output.readabilityHandler = nil
            try? session.input.close()
            if session.process.isRunning {
                session.process.terminate()
            }
        }

        _ = try await request(
            "initialize",
            params: [
                "clientInfo": [
                    "name": "clasp",
                    "title": "Clasp",
                    "version": "0.1"
                ],
                "capabilities": ["experimentalApi": true]
            ],
            session: session
        )
        try notify("initialized", params: nil, session: session)

        var paths: [String] = []
        var cursor: String?
        repeat {
            var params: [String: Any] = [
                "limit": 100,
                "archived": false
            ]
            if let cursor { params["cursor"] = cursor }
            let data = try await request("thread/list", params: params, session: session)
            let page = try JSONDecoder().decode(ThreadListResult.self, from: data)
            paths.append(contentsOf: page.data.compactMap(\.cwd))
            cursor = page.nextCursor
        } while cursor != nil
        return paths
    }

    private func openSession(
        pageID: String,
        reportsProgress: Bool = true
    ) throws -> Session {
        guard let executableURL = executableURL() else {
            throw CodexTaskError.appNotInstalled
        }
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let session = Session(
            pageID: pageID,
            process: process,
            input: inputPipe.fileHandleForWriting,
            output: outputPipe.fileHandleForReading,
            reportsProgress: reportsProgress
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
            return session
        } catch {
            session.output.readabilityHandler = nil
            throw CodexTaskError.couldNotStart
        }
    }

    private func notify(
        _ method: String,
        params: [String: Any]?,
        session: Session
    ) throws {
        var payload: [String: Any] = ["method": method]
        if let params {
            payload["params"] = params
        }
        try write(payload, to: session)
    }

    private func write(_ payload: [String: Any], to session: Session) throws {
        var data = try JSONSerialization.data(withJSONObject: payload)
        data.append(0x0A)
        try session.input.write(contentsOf: data)
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

    private func handle(_ data: Data, from session: Session) {
        guard let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if let requestID = (message["id"] as? NSNumber)?.intValue,
           let continuation = session.pending.removeValue(forKey: requestID) {
            if let error = message["error"] as? [String: Any] {
                let detail = error["message"] as? String ?? "Unknown protocol error"
                continuation.resume(throwing: CodexTaskError.protocolFailure(detail))
            } else {
                let result = message["result"] ?? [:]
                do {
                    continuation.resume(
                        returning: try JSONSerialization.data(withJSONObject: result)
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            return
        }

        guard let method = message["method"] as? String,
              let params = message["params"] as? [String: Any]
        else {
            return
        }
        let threadID = params["threadId"] as? String
        if let threadID, sessionsByThreadID[threadID] !== session {
            return
        }

        switch method {
        case "item/completed":
            guard let item = params["item"] as? [String: Any],
                  item["type"] as? String == "agentMessage",
                  let text = item["text"] as? String
            else {
                return
            }
            session.declaredOutcome = AgentTaskOutcome.declared(in: text)
        case "thread/status/changed":
            guard let status = params["status"] as? [String: Any],
                  status["type"] as? String == "active",
                  let flags = status["activeFlags"] as? [String],
                  flags.contains("waitingOnApproval") || flags.contains("waitingOnUserInput")
            else {
                return
            }
            session.reachedTerminalState = true
            emit(.waiting, for: session)
            stop(session)
        case "turn/completed":
            guard let turn = params["turn"] as? [String: Any],
                  let status = turn["status"] as? String
            else {
                return
            }
            session.reachedTerminalState = true
            let progress = status == "completed"
                ? session.declaredOutcome?.progress ?? .waiting
                : .failed
            emit(progress, for: session)
            stop(session)
        case "error":
            session.reachedTerminalState = true
            emit(.failed, for: session)
            stop(session)
        default:
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
        for continuation in session.pending.values {
            continuation.resume(throwing: CodexTaskError.couldNotStart)
        }
        session.pending.removeAll()
        if !session.reachedTerminalState, session.reportsProgress {
            emit(.failed, for: session)
        }
        stop(session)
    }

    private func stop(_ session: Session) {
        session.output.readabilityHandler = nil
        var releasedThreadID: String?
        if let entry = sessionsByThreadID.first(where: { $0.value === session }) {
            sessionsByThreadID.removeValue(forKey: entry.key)
            releasedThreadID = entry.key
        }
        if session.process.isRunning {
            session.process.terminate()
        }
        if let releasedThreadID {
            Task { @MainActor [onThreadReleased] in
                try? await Task.sleep(for: .milliseconds(250))
                onThreadReleased(releasedThreadID)
            }
        }
    }

    private func executableURL() -> URL? {
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex"
        ]
        return candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }).map(URL.init(fileURLWithPath:))
    }

    private func conversationTitle(for item: NotionListItem) -> String {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return "[\(item.taskID)] \(title.isEmpty ? "Untitled Task" : title)"
    }

    private func save(threadID: String, for pageID: String) {
        var associations = threadAssociations()
        associations[pageID] = threadID
        UserDefaults.standard.set(
            associations,
            forKey: "clasp.codexTaskThreadAssociations"
        )
    }

    private func threadAssociations() -> [String: String] {
        UserDefaults.standard.dictionary(
            forKey: "clasp.codexTaskThreadAssociations"
        ) as? [String: String] ?? [:]
    }
}
