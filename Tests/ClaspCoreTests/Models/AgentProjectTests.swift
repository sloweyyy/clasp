import ClaspCore
import Foundation
import Testing

@Suite("Agent project catalog")
struct AgentProjectTests {
    @Test("Keeps the default first and deduplicates discovered project folders")
    func buildsProjectOptions() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let defaultProject = root.appendingPathComponent(
            "preferred-project",
            isDirectory: true
        )
        let anotherProject = root.appendingPathComponent("another-project", isDirectory: true)
        try FileManager.default.createDirectory(
            at: defaultProject,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: anotherProject,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let options = AgentProjectCatalog.options(
            defaultPath: defaultProject.path,
            discoveredPaths: [
                anotherProject.path,
                defaultProject.path,
                root.appendingPathComponent("missing").path
            ]
        )

        #expect(options.map(\.path) == [defaultProject.path, anotherProject.path])
        #expect(options.map(\.name) == ["preferred-project", "another-project"])
    }
}
