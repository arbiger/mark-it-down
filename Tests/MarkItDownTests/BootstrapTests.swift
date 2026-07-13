import Foundation

actor QueuedCommandRunner: CommandRunner {
    enum Response {
        case result(CommandRunnerResult)
        case error(TestError)
    }

    enum TestError: Error {
        case failed
    }

    private var responses: [Response]
    private(set) var invocations: [(URL, [String])] = []

    init(_ responses: [Response]) {
        self.responses = responses
    }

    func run(executable: URL, arguments: [String]) async throws -> CommandRunnerResult {
        invocations.append((executable, arguments))
        guard !responses.isEmpty else {
            throw TestFailure(description: "QueuedCommandRunner ran out of responses")
        }
        switch responses.removeFirst() {
        case .result(let result): return result
        case .error(let error): throw error
        }
    }
}

enum BootstrapTests {
    static let all: [TestCase] = [
        ("python version validation handles supported boundaries", validatesVersions),
        ("python probe failure continues to next candidate", skipsFailedProbe),
        ("installer preserves fallback command order", preservesInstallFallbackOrder),
        ("installer failure retains actionable diagnostics", retainsInstallFailureDiagnostics)
    ]

    private static func result(_ code: Int32, stderr: String = "") -> CommandRunnerResult {
        CommandRunnerResult(exitCode: code, stdout: "", stderr: stderr)
    }

    private static func validatesVersions() async throws {
        for version in ["3.10", "Python 3.13.1", "4.0"] {
            try expect(PythonLocator.isAcceptable(version), "Expected \(version) to be accepted")
        }
        for version in ["3.9.20", "Python 3", "not-python", ""] {
            try expect(!PythonLocator.isAcceptable(version), "Expected \(version) to be rejected")
        }
    }

    private static func skipsFailedProbe() async throws {
        let first = URL(fileURLWithPath: "/tmp/python-one")
        let second = URL(fileURLWithPath: "/tmp/python-two")
        let runner = QueuedCommandRunner([
            .error(.failed),
            .result(result(0))
        ])

        let selected = try await MarkitdownInstaller.findOrInstall(
            candidates: [first, second],
            runner: runner
        )

        try expectEqual(selected, second)
    }

    private static func preservesInstallFallbackOrder() async throws {
        let python = URL(fileURLWithPath: "/tmp/python")
        let runner = QueuedCommandRunner([
            .result(result(1)),
            .result(result(1, stderr: "user install failed")),
            .result(result(0))
        ])

        let installed = try await MarkitdownInstaller.ensureInstalled(
            pythonPath: python,
            runner: runner
        )

        try expect(installed, "Expected system install fallback to succeed")
        let invocations = await runner.invocations
        try expectEqual(invocations.map(\.1), [
            ["-c", "import markitdown, sys; sys.stdout.write(markitdown.__file__)"],
            ["-m", "pip", "install", "--user", "--break-system-packages", "markitdown[all]"],
            ["-m", "pip", "install", "--break-system-packages", "markitdown[all]"]
        ])
    }

    private static func retainsInstallFailureDiagnostics() async throws {
        let python = URL(fileURLWithPath: "/tmp/python")
        let runner = QueuedCommandRunner([
            .result(result(1)),
            .result(result(1, stderr: "user install failed")),
            .result(result(1, stderr: "system install failed"))
        ])

        do {
            _ = try await MarkitdownInstaller.ensureInstalled(pythonPath: python, runner: runner)
            throw TestFailure(description: "Expected installation failure")
        } catch let error as MarkitdownInstallerError {
            let description = error.localizedDescription
            try expect(description.contains("system install failed"), "Expected final stderr")
            try expect(description.contains("/tmp/python -m pip install"), "Expected manual command")
        }
    }
}
