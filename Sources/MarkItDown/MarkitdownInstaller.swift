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
    /// Scan a list of candidate pythons for one that already has `markitdown` importable.
    /// If none do, install markitdown into the first candidate. Returns the python URL to use,
    /// or nil if no candidate is acceptable or install fails.
    static func findOrInstall(
        candidates: [URL],
        runner: CommandRunner = SystemCommandRunner()
    ) async throws -> URL? {
        // Pass 1: pick the first python where `import markitdown` works. This avoids copying
        // when the user already has markitdown in a venv at e.g. /tmp/markitdown-work/venv.
        for python in candidates {
            let probe = try await runner.run(
                executable: python,
                arguments: ["-c", "import markitdown"]
            )
            if probe.exitCode == 0 {
                return python
            }
        }
        // Pass 2: install into the first candidate.
        guard let python = candidates.first else { return nil }
        let ok = try await ensureInstalled(pythonPath: python, runner: runner)
        return ok ? python : nil
    }

    static func ensureInstalled(
        pythonPath: URL,
        runner: CommandRunner = SystemCommandRunner()
    ) async throws -> Bool {
        // Probe in priority order:
        //   1. `python -c "import markitdown"` — works on any python where markitdown is importable
        //      (e.g. inside a venv where pip show might not report it)
        let probeResult = try await runner.run(
            executable: pythonPath,
            arguments: ["-c", "import markitdown, sys; sys.stdout.write(markitdown.__file__)"]
        )
        if probeResult.exitCode == 0 {
            return true
        }
        //   2. pip install into the python. Use --break-system-packages to bypass PEP 668
        //      (Homebrew Python 3.11+ is externally-managed by default).
        let installResult = try await runner.run(
            executable: pythonPath,
            arguments: ["-m", "pip", "install", "--user", "--break-system-packages", "markitdown[all]"]
        )
        if installResult.exitCode == 0 {
            return true
        }
        //   3. Last resort: try without --user (system-wide install) with --break-system-packages.
        let systemInstall = try await runner.run(
            executable: pythonPath,
            arguments: ["-m", "pip", "install", "--break-system-packages", "markitdown[all]"]
        )
        return systemInstall.exitCode == 0
    }
}