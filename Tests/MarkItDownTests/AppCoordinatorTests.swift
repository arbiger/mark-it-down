import Foundation

enum AppCoordinatorTests {
    static let all: [TestCase] = [
        ("stopped conversion cannot publish stale completion", stoppedConversionStaysStopped)
    ]

    private static func stoppedConversionStaysStopped() async throws {
        let runner = ControlledMarkitdownRunner(delay: .seconds(5))
        let engine = ConversionEngine(markitdown: runner, maxConcurrent: 1)
        let root = URL(fileURLWithPath: "/tmp/coordinator-tests")
        let job = FolderJob(
            rootURL: root,
            files: [
                SourceFile(
                    sourceURL: root.appendingPathComponent("source.pdf"),
                    outputURL: root.appendingPathComponent("source.md")
                )
            ]
        )

        let coordinator = await MainActor.run {
            let state = AppState()
            state.pythonPath = URL(fileURLWithPath: "/usr/bin/python3")
            state.job = job
            state.mode = .preview
            return AppCoordinator(
                state: state,
                dropDelegate: ItemDropDelegate(),
                markitdownRunner: runner,
                engine: engine
            )
        }

        await MainActor.run { coordinator.startConversion() }
        try await Task.sleep(for: .milliseconds(100))
        await MainActor.run { coordinator.stopConversion() }
        try await Task.sleep(for: .milliseconds(200))

        let mode = await MainActor.run { coordinator.state.mode }
        try expectEqual(mode, .preview)
    }
}
