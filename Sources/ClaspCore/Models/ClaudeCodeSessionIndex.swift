import Foundation

/// Discovers the project folders Claude Code has been used in by reading the
/// working directory recorded inside each stored session transcript under
/// `~/.claude/projects/<encoded-path>/<session-id>.jsonl`.
///
/// The directory names themselves encode the path lossily (`/` and `.` both
/// become `-`), so the authoritative `cwd` value is read from the session
/// records instead.
public enum ClaudeCodeSessionIndex {
    /// Only this many leading bytes of a transcript are scanned. The working
    /// directory is recorded on the first conversation records, so a bounded
    /// read keeps discovery cheap even for very large session files.
    private static let scanByteLimit = 256 * 1024

    private struct SessionRecord: Decodable {
        let cwd: String?
    }

    public static var defaultProjectsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
    }

    public static func discoverProjectPaths(
        projectsRoot: URL = defaultProjectsRoot
    ) -> [String] {
        let fileManager = FileManager.default
        guard let projectDirectories = try? fileManager.contentsOfDirectory(
            at: projectsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var paths: [String] = []
        var seen = Set<String>()
        for directory in projectDirectories {
            guard (try? directory.resourceValues(
                forKeys: [.isDirectoryKey]
            ))?.isDirectory == true else {
                continue
            }
            guard let path = workingDirectory(inProjectDirectory: directory),
                  seen.insert(path).inserted
            else {
                continue
            }
            paths.append(path)
        }
        return paths
    }

    private static func workingDirectory(
        inProjectDirectory directory: URL
    ) -> String? {
        let fileManager = FileManager.default
        guard let sessionFiles = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let newestFirst = sessionFiles
            .filter { $0.pathExtension == "jsonl" }
            .sorted { left, right in
                let leftDate = (try? left.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ))?.contentModificationDate ?? .distantPast
                let rightDate = (try? right.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ))?.contentModificationDate ?? .distantPast
                return leftDate > rightDate
            }

        for file in newestFirst {
            if let path = workingDirectory(inSessionFile: file) {
                return path
            }
        }
        return nil
    }

    private static func workingDirectory(inSessionFile file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else {
            return nil
        }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: scanByteLimit) else {
            return nil
        }

        let decoder = JSONDecoder()
        for line in data.split(separator: 0x0A) {
            guard let record = try? decoder.decode(
                SessionRecord.self,
                from: Data(line)
            ), let cwd = record.cwd, !cwd.isEmpty else {
                continue
            }
            return cwd
        }
        return nil
    }
}
