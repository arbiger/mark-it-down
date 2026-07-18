import Foundation

enum OutputAndScannerTests {
    static let all: [TestCase] = [
        ("scan sorts sources and reserves unique outputs", scanSortsAndReserves),
        ("scan excludes existing Markdown outputs", scanExcludesMarkdownOutputs),
        ("scan includes only visible supported regular files", scanFiltersInputs),
        ("selected file does not scan sibling files", selectedFileDoesNotScanSiblings),
        ("multiple selected files convert only that selection", multipleFilesPreserveSelection),
        ("mixed file and folder selection expands and deduplicates", mixedSelectionExpandsAndDeduplicates)
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

    private static func selectedFileDoesNotScanSiblings() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        defer { temporaryDirectory.remove() }
        let selected = temporaryDirectory.url.appendingPathComponent("selected.pdf")
        try temporaryDirectory.createFile("selected.pdf")
        try temporaryDirectory.createFile("sibling.docx")

        let result = try FileScanner.scan(items: [selected])

        try expectEqual(result.files.map { $0.sourceURL.lastPathComponent }, ["selected.pdf"])
    }

    private static func multipleFilesPreserveSelection() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        defer { temporaryDirectory.remove() }
        let first = temporaryDirectory.url.appendingPathComponent("first.pdf")
        let second = temporaryDirectory.url.appendingPathComponent("second.docx")
        try temporaryDirectory.createFile("first.pdf")
        try temporaryDirectory.createFile("second.docx")
        try temporaryDirectory.createFile("unselected.xlsx")

        let result = try FileScanner.scan(items: [second, first])

        try expectEqual(
            result.files.map { $0.sourceURL.lastPathComponent },
            ["first.pdf", "second.docx"]
        )
    }

    private static func mixedSelectionExpandsAndDeduplicates() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        defer { temporaryDirectory.remove() }
        let folder = temporaryDirectory.url.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let nested = temporaryDirectory.url.appendingPathComponent("folder/nested.pdf")
        let explicit = temporaryDirectory.url.appendingPathComponent("explicit.docx")
        try temporaryDirectory.createFile("folder/nested.pdf")
        try temporaryDirectory.createFile("explicit.docx")

        let result = try FileScanner.scan(items: [folder, nested, explicit])

        try expectEqual(
            result.files.map { $0.sourceURL.lastPathComponent },
            ["explicit.docx", "nested.pdf"]
        )
    }
}
