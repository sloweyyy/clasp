import Foundation

public struct AgentProjectOption: Identifiable, Equatable, Hashable, Sendable {
    public let path: String

    public var id: String { path }

    public var name: String {
        URL(fileURLWithPath: path, isDirectory: true).lastPathComponent
    }

    public init(path: String) {
        self.path = path
    }
}

public enum AgentProjectCatalog {
    public static func options(
        defaultPath: String,
        discoveredPaths: [String]
    ) -> [AgentProjectOption] {
        let normalizedDefault = normalize(defaultPath)
        var seen = Set<String>()
        var paths: [String] = []

        for candidate in [normalizedDefault] + discoveredPaths.map(normalize) {
            var isDirectory: ObjCBool = false
            guard !candidate.isEmpty,
                  seen.insert(candidate).inserted,
                  FileManager.default.fileExists(
                    atPath: candidate,
                    isDirectory: &isDirectory
                  ),
                  isDirectory.boolValue
            else {
                continue
            }
            paths.append(candidate)
        }

        return paths
            .sorted { left, right in
                if left == normalizedDefault { return true }
                if right == normalizedDefault { return false }
                let leftName = URL(fileURLWithPath: left).lastPathComponent
                let rightName = URL(fileURLWithPath: right).lastPathComponent
                let nameOrder = leftName.localizedCaseInsensitiveCompare(rightName)
                if nameOrder == .orderedSame { return left < right }
                return nameOrder == .orderedAscending
            }
            .map(AgentProjectOption.init(path:))
    }

    private static func normalize(_ path: String) -> String {
        let expanded = NSString(
            string: path.trimmingCharacters(in: .whitespacesAndNewlines)
        ).expandingTildeInPath
        guard !expanded.isEmpty else { return "" }
        return URL(fileURLWithPath: expanded, isDirectory: true)
            .standardizedFileURL
            .path
    }
}
