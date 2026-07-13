import Foundation

struct CommandRunnerResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

protocol CommandRunner {
    func run(executable: URL, arguments: [String]) async throws -> CommandRunnerResult
}

struct SystemCommandRunner: CommandRunner {
    func run(executable: URL, arguments: [String]) async throws -> CommandRunnerResult {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CommandRunnerResult, Error>) in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            process.terminationHandler = { proc in
                let outData = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
                let errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
                let result = CommandRunnerResult(
                    exitCode: proc.terminationStatus,
                    stdout: String(data: outData, encoding: .utf8) ?? "",
                    stderr: String(data: errData, encoding: .utf8) ?? ""
                )
                cont.resume(returning: result)
            }
            do {
                try process.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}

enum MarkitdownInstaller {
    static func ensureInstalled(
        pythonPath: URL,
        runner: CommandRunner = SystemCommandRunner()
    ) async throws -> Bool {
        let showResult = try await runner.run(
            executable: pythonPath,
            arguments: ["-m", "pip", "show", "markitdown"]
        )
        if showResult.exitCode == 0 {
            return true
        }
        let installResult = try await runner.run(
            executable: pythonPath,
            arguments: ["-m", "pip", "install", "--user", "markitdown[all]"]
        )
        return installResult.exitCode == 0
    }
}