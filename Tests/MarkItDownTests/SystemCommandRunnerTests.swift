import Foundation

enum SystemCommandRunnerTests {
    private static let shell = URL(fileURLWithPath: "/bin/sh")

    static let all: [TestCase] = [
        ("command runner captures both streams and exit code", capturesStreamsAndExitCode),
        ("command runner drains large output", drainsLargeOutput),
        ("command runner terminates on task cancellation", terminatesOnCancellation),
        ("markitdown runner accepts nonempty Markdown", acceptsNonemptyMarkdown),
        ("markitdown runner rejects and removes empty PDF output", rejectsEmptyPDFOutput),
        ("markitdown runner rejects missing output", rejectsMissingOutput)
    ]

    private static func capturesStreamsAndExitCode() async throws {
        let result = try await SystemCommandRunner().run(
            executable: shell,
            arguments: ["-c", "printf out; printf err >&2; exit 7"]
        )

        try expectEqual(result.exitCode, 7)
        try expectEqual(result.stdout, "out")
        try expectEqual(result.stderr, "err")
    }

    private static func drainsLargeOutput() async throws {
        let result = try await SystemCommandRunner().run(
            executable: shell,
            arguments: ["-c", "yes o | head -c 1048576; yes e | head -c 1048576 >&2"]
        )

        try expectEqual(result.exitCode, 0)
        try expectEqual(result.stdout.utf8.count, 1_048_576)
        try expectEqual(result.stderr.utf8.count, 1_048_576)
    }

    private static func terminatesOnCancellation() async throws {
        let task = Task {
            try await SystemCommandRunner().run(
                executable: shell,
                arguments: ["-c", "sleep 30"]
            )
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        do {
            _ = try await task.value
            throw TestFailure(description: "Expected command runner to throw CancellationError")
        } catch is CancellationError {
            return
        }
    }

    private static func acceptsNonemptyMarkdown() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        defer { temporaryDirectory.remove() }
        let source = temporaryDirectory.url.appendingPathComponent("source.pdf")
        let output = temporaryDirectory.url.appendingPathComponent("source.md")

        try await MarkitdownRunner(
            runner: OutputWritingCommandRunner(contents: "# Extracted\n")
        ).convert(pythonPath: shell, source: source, output: output)

        try expect(FileManager.default.fileExists(atPath: output.path), "Expected Markdown output")
    }

    private static func rejectsEmptyPDFOutput() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        defer { temporaryDirectory.remove() }
        let source = temporaryDirectory.url.appendingPathComponent("outlined.pdf")
        let output = temporaryDirectory.url.appendingPathComponent("outlined.md")

        do {
            try await MarkitdownRunner(
                runner: OutputWritingCommandRunner(contents: " \n\t")
            ).convert(pythonPath: shell, source: source, output: output)
            throw TestFailure(description: "Expected empty PDF output to fail")
        } catch let error as MarkitdownRunnerError {
            guard case .noExtractableContent(let isPDF) = error else { throw error }
            try expect(isPDF, "Expected the failure to identify a PDF")
            try expect(
                error.localizedDescription.contains("OCR"),
                "Expected actionable OCR guidance"
            )
            try expect(
                !FileManager.default.fileExists(atPath: output.path),
                "Expected empty Markdown output to be removed"
            )
        }
    }

    private static func rejectsMissingOutput() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        defer { temporaryDirectory.remove() }
        let source = temporaryDirectory.url.appendingPathComponent("source.pdf")
        let output = temporaryDirectory.url.appendingPathComponent("source.md")

        do {
            try await MarkitdownRunner(
                runner: OutputWritingCommandRunner(contents: nil)
            ).convert(pythonPath: shell, source: source, output: output)
            throw TestFailure(description: "Expected missing output to fail")
        } catch MarkitdownRunnerError.missingOutput {
            return
        }
    }
}

private struct OutputWritingCommandRunner: CommandRunner {
    let contents: String?

    func run(executable: URL, arguments: [String]) async throws -> CommandRunnerResult {
        if let contents, let outputPath = arguments.last {
            try contents.write(
                to: URL(fileURLWithPath: outputPath),
                atomically: true,
                encoding: .utf8
            )
        }
        return CommandRunnerResult(exitCode: 0, stdout: "", stderr: "")
    }
}
