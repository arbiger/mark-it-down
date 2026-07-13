import Foundation

protocol MarkitdownRunning {
    func convert(pythonPath: URL, source: URL, output: URL) async throws
}

enum MarkitdownRunnerError: Error {
    case nonZeroExit(code: Int32, stderr: String)
}

struct MarkitdownRunner: MarkitdownRunning {
    private let runner: CommandRunner

    init(runner: CommandRunner = SystemCommandRunner()) {
        self.runner = runner
    }

    func convert(pythonPath: URL, source: URL, output: URL) async throws {
        let result = try await runner.run(
            executable: pythonPath,
            arguments: ["-m", "markitdown", source.path, "-o", output.path]
        )
        if result.exitCode != 0 {
            throw MarkitdownRunnerError.nonZeroExit(code: result.exitCode, stderr: result.stderr)
        }
    }
}