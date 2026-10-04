import Foundation

actor ControlledMarkitdownRunner: DocumentConverting {
    private(set) var started: [String] = []
    private(set) var peakConcurrent = 0
    private var concurrent = 0
    private let delay: Duration
    private let failingName: String?

    init(delay: Duration = .milliseconds(50), failingName: String? = nil) {
        self.delay = delay
        self.failingName = failingName
    }

    func convert(pythonPath: URL, source: URL, output: URL) async throws {
        started.append(source.lastPathComponent)
        concurrent += 1
        peakConcurrent = max(peakConcurrent, concurrent)
        defer { concurrent -= 1 }

        try await Task.sleep(for: delay)
        if source.lastPathComponent == failingName {
            throw MarkitdownRunnerError.nonZeroExit(code: 1, stderr: "fixture failure")
        }
    }
}

actor StatusRecorder {
    private(set) var statuses: [UUID: ConversionStatus] = [:]

    @MainActor
    func record(id: UUID, status: ConversionStatus) async {
        await set(id: id, status: status)
    }

    private func set(id: UUID, status: ConversionStatus) {
        statuses[id] = status
    }
}

enum ConversionEngineTests {
    static let all: [TestCase] = [
        ("conversion engine respects concurrency limit", respectsConcurrencyLimit),
        ("conversion engine isolates individual failures", isolatesFailures),
        ("conversion engine stops scheduling after cancellation", stopsAfterCancellation)
    ]

    private static func makeJob(count: Int) -> FolderJob {
        let root = URL(fileURLWithPath: "/tmp/markitdown-engine-tests")
        let files = (0..<count).map { index in
            SourceFile(
                sourceURL: root.appendingPathComponent("source-\(index).pdf"),
                outputURL: root.appendingPathComponent("source-\(index).md")
            )
        }
        return FolderJob(rootURL: root, files: files)
    }

    private static func respectsConcurrencyLimit() async throws {
        let runner = ControlledMarkitdownRunner()
        let recorder = StatusRecorder()
        let engine = ConversionEngine(markitdown: runner, maxConcurrent: 2)
        let job = makeJob(count: 6)

        await engine.run(job: job, pythonPath: URL(fileURLWithPath: "/usr/bin/python3")) {
            id, status in
            await recorder.record(id: id, status: status)
        }

        try expectEqual(await runner.peakConcurrent, 2)
        let statuses = await recorder.statuses
        try expectEqual(statuses.count, 6)
        try expect(statuses.values.allSatisfy { $0 == .done }, "Expected every conversion to finish")
    }

    private static func isolatesFailures() async throws {
        let runner = ControlledMarkitdownRunner(failingName: "source-2.pdf")
        let recorder = StatusRecorder()
        let engine = ConversionEngine(markitdown: runner, maxConcurrent: 2)
        let job = makeJob(count: 4)

        await engine.run(job: job, pythonPath: URL(fileURLWithPath: "/usr/bin/python3")) {
            id, status in
            await recorder.record(id: id, status: status)
        }

        let statuses = await recorder.statuses
        let failedID = job.files.first { $0.sourceURL.lastPathComponent == "source-2.pdf" }!.id
        guard case .failed(let message) = statuses[failedID] else {
            throw TestFailure(description: "Expected source-2.pdf to fail")
        }
        try expect(message.contains("fixture failure"), "Expected stderr in conversion failure")
        try expectEqual(statuses.values.filter { $0 == .done }.count, 3)
    }

    private static func stopsAfterCancellation() async throws {
        let runner = ControlledMarkitdownRunner(delay: .seconds(5))
        let recorder = StatusRecorder()
        let engine = ConversionEngine(markitdown: runner, maxConcurrent: 2)
        let job = makeJob(count: 10)

        let task = Task {
            await engine.run(job: job, pythonPath: URL(fileURLWithPath: "/usr/bin/python3")) {
                id, status in
                await recorder.record(id: id, status: status)
            }
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await task.value

        let started = await runner.started
        let statuses = await recorder.statuses
        try expect(started.count < job.files.count, "Cancellation should stop new scheduling")
        try expect(
            statuses.values.contains { $0 == .cancelled },
            "Interrupted conversions should be cancelled"
        )
        try expect(
            !statuses.values.contains { if case .failed = $0 { return true }; return false },
            "Cancellation must not be reported as failure"
        )
    }
}
