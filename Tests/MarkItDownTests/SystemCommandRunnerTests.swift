import Foundation

enum SystemCommandRunnerTests {
    private static let shell = URL(fileURLWithPath: "/bin/sh")

    static let all: [TestCase] = [
        ("command runner captures both streams and exit code", capturesStreamsAndExitCode),
        ("command runner drains large output", drainsLargeOutput),
        ("command runner terminates on task cancellation", terminatesOnCancellation)
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
}
