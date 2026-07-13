import Foundation

enum OutputAndScannerTests {
    static let all: [TestCase] = [
        ("scan sorts sources and reserves unique outputs", scanSortsAndReserves),
        ("scan excludes existing Markdown outputs", scanExcludesMarkdownOutputs),
        ("scan includes only visible supported regular files", scanFiltersInputs)
    ]

    private static func scanSortsAndReserves() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        defer { temporaryDirectory.remove() }
        try temporaryDirectory.createFile("report.pdf")
        try temporaryDirectory.createFile("report.docx")

        let files = try FileScanner.scan(root: temporaryDirectory.url)

        try expectEqual(files.map { $0.sourceURL.lastPathComponent }, ["report.docx", "report.pdf"])
        try expectEqual(files.map { $0.outputURL.lastPathComponent }, ["report.md", "report(1).md"])
    }

    private static func scanExcludesMarkdownOutputs() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        defer { temporaryDirectory.remove() }
        try temporaryDirectory.createFile("report.md", contents: Data("existing".utf8))
        try temporaryDirectory.createFile("report.pdf")
        try temporaryDirectory.createFile("report.docx")

        let files = try FileScanner.scan(root: temporaryDirectory.url)

        try expectEqual(files.map { $0.sourceURL.lastPathComponent }, ["report.docx", "report.pdf"])
        try expectEqual(files.map { $0.outputURL.lastPathComponent }, ["report(1).md", "report(2).md"])
    }

    private static func scanFiltersInputs() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        defer { temporaryDirectory.remove() }
        try temporaryDirectory.createFile(".hidden.pdf")
        try temporaryDirectory.createFile("notes.bin")
        try temporaryDirectory.createFile("nested/visible.pdf")
        try FileManager.default.createDirectory(
            at: temporaryDirectory.url.appendingPathComponent("Folder.app"),
            withIntermediateDirectories: true
        )
        try temporaryDirectory.createFile("Folder.app/inside.pdf")

        let files = try FileScanner.scan(root: temporaryDirectory.url)

        try expectEqual(files.map { $0.sourceURL.lastPathComponent }, ["visible.pdf"])
    }
}
