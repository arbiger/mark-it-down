import Foundation

struct CommandRunnerResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

protocol CommandRunner {
    func run(executable: URL, arguments: [String]) async throws -> CommandRunnerResult
}

enum MarkitdownInstallerError: LocalizedError {
    case installationFailed(pythonPath: URL, stderr: String)

    var errorDescription: String? {
        switch self {
        case .installationFailed(let pythonPath, let stderr):
            let details = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let command = "\(pythonPath.path) -m pip install --user "
                + "--break-system-packages 'markitdown[all]'"
            let prefix = details.isEmpty ? "Could not install markitdown." : details
            return "\(prefix)\n\nRun manually:\n\(command)"
        }
    }
}

struct SystemCommandRunner: CommandRunner {
    func run(executable: URL, arguments: [String]) async throws -> CommandRunnerResult {
        try Task.checkCancellation()

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()

        let stdoutTask = Task.detached {
            (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
        }
        let stderrTask = Task.detached {
            (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
        }

        let exitCode = await withTaskCancellationHandler {
            await Task.detached {
                process.waitUntilExit()
                return process.terminationStatus
            }.value
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }

        let outData = await stdoutTask.value
        let errData = await stderrTask.value
        try Task.checkCancellation()

        return CommandRunnerResult(
            exitCode: exitCode,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
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
            do {
                let probe = try await runner.run(
                    executable: python,
                    arguments: ["-c", "import markitdown"]
                )
                if probe.exitCode == 0 {
                    return python
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
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
        if systemInstall.exitCode == 0 {
            return true
        }

        let finalError = systemInstall.stderr.isEmpty
            ? installResult.stderr
            : systemInstall.stderr
        throw MarkitdownInstallerError.installationFailed(
            pythonPath: pythonPath,
            stderr: finalError
        )
    }
}
