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
        ("private probe returns only private interpreter", privateProbe),
        ("private bootstrap creates venv and installs pinned requirements", privateCreates),
        ("private bootstrap repairs wrong versions", privateRepairs),
        ("private bootstrap reports venv failure", privateVenvFailure),
        ("private bootstrap reports pip failure", privatePipFailure),
        ("private bootstrap reports verification failure", privateVerifyFailure)
    ]

    private static func result(
        _ code: Int32,
        stdout: String = "",
        stderr: String = ""
    ) -> CommandRunnerResult {
        CommandRunnerResult(exitCode: code, stdout: stdout, stderr: stderr)
    }

    private static func validatesVersions() async throws {
        for version in ["3.10", "Python 3.11.9", "3.12.8", "Python 3.13.1"] {
            try expect(PythonLocator.isAcceptable(version), "Expected \(version) to be accepted")
        }
        for version in ["3.9.20", "Python 3.14.0", "4.0", "Python 3", "not-python", ""] {
            try expect(!PythonLocator.isAcceptable(version), "Expected \(version) to be rejected")
        }
    }

    private static func withPaths<T>(
        _ body: (
            URL,
            URL,
            URL,
            URL,
            TemporaryDirectory
        ) async throws -> T
    ) async throws -> T {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let basePython = directory.url.appendingPathComponent("base-python")
        let privatePython = MarkitdownInstaller.appPrivatePython(baseURL: directory.url)
        let environmentRoot = privatePython
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let requirements = directory.url.appendingPathComponent("requirements.txt")
        try directory.createFile(
            "requirements.txt",
            contents: Data("pins".utf8)
        )
        return try await body(
            basePython,
            privatePython,
            environmentRoot,
            requirements,
            directory
        )
    }

    private static func privateProbe() async throws {
        try await withPaths { base, privatePython, _, requirements, directory in
            try directory.createFile("venv/bin/python3")
            let runner = QueuedCommandRunner([.result(result(0))])

            let selected = try await MarkitdownInstaller.findOrInstall(
                candidates: [base],
                runner: runner,
                baseURL: directory.url,
                requirementsURL: requirements
            )

            try expectEqual(selected, privatePython)
            let calls = await runner.invocations
            try expectEqual(calls.count, 1)
            try expectEqual(calls[0].0, privatePython)
            try assertVersionProbe(calls[0].1)
            try assertNoGlobalFlags(calls)
        }
    }

    private static func privateCreates() async throws {
        try await withPaths { base, privatePython, environmentRoot, requirements, directory in
            let runner = QueuedCommandRunner([
                .result(result(0)),
                .result(result(0)),
                .result(result(0))
            ])

            let selected = try await MarkitdownInstaller.findOrInstall(
                candidates: [base],
                runner: runner,
                baseURL: directory.url,
                requirementsURL: requirements
            )

            try expectEqual(selected, privatePython)
            let calls = await runner.invocations
            try expectEqual(calls.count, 3)
            try expectEqual(calls[0].0, base)
            try expectEqual(calls[0].1, ["-m", "venv", "--clear", environmentRoot.path])
            try expectEqual(calls[1].0, privatePython)
            try expectEqual(calls[1].1, [
                "-m", "pip", "install",
                "--disable-pip-version-check",
                "--upgrade",
                "-r", requirements.path
            ])
            try expectEqual(calls[2].0, privatePython)
            try assertVersionProbe(calls[2].1)
            try assertNoGlobalFlags(calls)
        }
    }

    private static func privateRepairs() async throws {
        try await withPaths { base, privatePython, environmentRoot, requirements, directory in
            try directory.createFile("venv/bin/python3")
            let runner = QueuedCommandRunner([
                .result(result(1)),
                .result(result(0)),
                .result(result(0)),
                .result(result(0))
            ])

            let selected = try await MarkitdownInstaller.findOrInstall(
                candidates: [base],
                runner: runner,
                baseURL: directory.url,
                requirementsURL: requirements
            )

            try expectEqual(selected, privatePython)
            let calls = await runner.invocations
            try expectEqual(calls.count, 4)
            try expectEqual(calls[0].0, privatePython)
            try assertVersionProbe(calls[0].1)
            try expectEqual(calls[1].0, base)
            try expectEqual(calls[1].1, ["-m", "venv", "--clear", environmentRoot.path])
            try expectEqual(calls[2].0, privatePython)
            try expectEqual(calls[3].0, privatePython)
            try assertVersionProbe(calls[3].1)
            try assertNoGlobalFlags(calls)
        }
    }

    private static func privateVenvFailure() async throws {
        try await assertFailure(
            responses: [.result(result(1, stderr: "venv marker"))],
            expected: ["Virtual environment", "venv marker"]
        )
    }

    private static func privatePipFailure() async throws {
        try await assertFailure(
            responses: [
                .result(result(0)),
                .result(result(1, stderr: "pip marker"))
            ],
            expected: ["Pinned dependency installation", "pip marker"]
        )
    }

    private static func privateVerifyFailure() async throws {
        try await assertFailure(
            responses: [
                .result(result(0)),
                .result(result(0)),
                .result(result(1, stderr: "verify marker"))
            ],
            expected: ["Pinned dependency verification", "verify marker"]
        )
    }

    private static func assertFailure(
        responses: [QueuedCommandRunner.Response],
        expected markers: [String]
    ) async throws {
        try await withPaths { base, _, _, requirements, directory in
            let runner = QueuedCommandRunner(responses)
            do {
                _ = try await MarkitdownInstaller.findOrInstall(
                    candidates: [base],
                    runner: runner,
                    baseURL: directory.url,
                    requirementsURL: requirements
                )
                throw TestFailure(description: "Expected private bootstrap failure")
            } catch let error as MarkitdownInstallerError {
                let message = error.localizedDescription
                try expect(message.contains(directory.url.path), "Expected private path in diagnostic")
                for marker in markers {
                    try expect(message.contains(marker), "Expected '\(marker)' in diagnostic")
                }
            }
            try assertNoGlobalFlags(await runner.invocations)
        }
    }

    private static func assertVersionProbe(_ arguments: [String]) throws {
        try expectEqual(arguments.count, 2)
        try expectEqual(arguments[0], "-c")
        let script = arguments[1]
        try expect(script.contains("raise SystemExit"), "Expected explicit version-probe exit")
        try expect(
            script.contains(MarkitdownInstaller.markitdownVersion),
            "Expected pinned MarkItDown version"
        )
        try expect(
            script.contains(MarkitdownInstaller.pdfInspectorVersion),
            "Expected pinned PDF Inspector version"
        )
        try expect(!script.contains("assert "), "Version probe must not rely on Python assert")
    }

    private static func assertNoGlobalFlags(
        _ calls: [(URL, [String])]
    ) throws {
        for (_, arguments) in calls {
            try expect(!arguments.contains("--user"), "Must not install into user-global Python")
            try expect(
                !arguments.contains("--break-system-packages"),
                "Must not bypass system package protections"
            )
        }
    }
}
