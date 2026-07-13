import Foundation

enum FolderJobTests {
    static let all: [TestCase] = [
        ("folder job counts statuses in one summary", countsStatuses)
    ]

    private static func countsStatuses() async throws {
        let root = URL(fileURLWithPath: "/tmp/folder-job-tests")
        let statuses: [ConversionStatus] = [
            .pending, .running, .done, .failed("fixture"), .cancelled
        ]
        let files = statuses.enumerated().map { index, status in
            SourceFile(
                sourceURL: root.appendingPathComponent("\(index).pdf"),
                outputURL: root.appendingPathComponent("\(index).md"),
                status: status
            )
        }

        let counts = FolderJob(rootURL: root, files: files).counts

        try expectEqual(counts.pending, 1)
        try expectEqual(counts.running, 1)
        try expectEqual(counts.succeeded, 1)
        try expectEqual(counts.failed, 1)
        try expectEqual(counts.cancelled, 1)
        try expectEqual(counts.completed, 3)
    }
}
