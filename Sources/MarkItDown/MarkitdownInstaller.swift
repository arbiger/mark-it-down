import Foundation

struct CommandRunnerResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

protocol CommandRunner: Sendable {
    func run(executable: URL, arguments: [String]) async throws -> CommandRunnerResult
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

enum MarkitdownInstallerError: LocalizedError {
    case preparationFailed(stage: String, pythonPath: URL, details: String)

    var errorDescription: String? {
        switch self {
        case .preparationFailed(let stage, let pythonPath, let details):
            let environment = pythonPath
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .path
            let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = trimmed.isEmpty ? "" : " \(trimmed)"
            return "Could not prepare the private Mark-It-Down environment at \(environment). \(stage) failed.\(suffix)"
        }
    }
}

enum MarkitdownInstaller {
    static let markitdownVersion = "0.1.7"
    static let pdfInspectorVersion = "0.2.6"

    private static let versionProbe = """
    import importlib.metadata as metadata
    ok = (
        metadata.version("markitdown") == "\(markitdownVersion)"
        and metadata.version("pdf-inspector") == "\(pdfInspectorVersion)"
    )
    raise SystemExit(0 if ok else 1)
    """

    static func appPrivatePython(baseURL: URL? = nil) -> URL {
        let base = baseURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mark-It-Down/runtime", isDirectory: true)
        return base.appendingPathComponent("venv/bin/python3")
    }

    static func findOrInstall(
        candidates: [URL],
        runner: CommandRunner = SystemCommandRunner(),
        baseURL: URL? = nil,
        requirementsURL: URL? = nil,
        fileManager: FileManager = .default
    ) async throws -> URL? {
        guard let basePython = candidates.first else { return nil }

        let privatePython = appPrivatePython(baseURL: baseURL)
        let environmentRoot = privatePython
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let requirements = requirementsURL ?? defaultRequirementsURL()

        if fileManager.fileExists(atPath: privatePython.path) {
            do {
                let probe = try await runner.run(
                    executable: privatePython,
                    arguments: ["-c", versionProbe]
                )
                if probe.exitCode == 0 {
                    return privatePython
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A damaged private environment is repaired below.
            }
        }

        do {
            try fileManager.createDirectory(
                at: environmentRoot.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw failure(
                stage: "Application Support directory creation",
                pythonPath: privatePython,
                details: error.localizedDescription
            )
        }

        let createResult: CommandRunnerResult
        do {
            createResult = try await runner.run(
                executable: basePython,
                arguments: ["-m", "venv", "--clear", environmentRoot.path]
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw failure(
                stage: "Virtual environment creation",
                pythonPath: privatePython,
                details: error.localizedDescription
            )
        }
        guard createResult.exitCode == 0 else {
            throw failure(
                stage: "Virtual environment creation",
                pythonPath: privatePython,
                result: createResult
            )
        }

        let installResult: CommandRunnerResult
        do {
            installResult = try await runner.run(
                executable: privatePython,
                arguments: [
                    "-m", "pip", "install",
                    "--disable-pip-version-check",
                    "--upgrade",
                    "-r", requirements.path
                ]
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw failure(
                stage: "Pinned dependency installation",
                pythonPath: privatePython,
                details: error.localizedDescription
            )
        }
        guard installResult.exitCode == 0 else {
            throw failure(
                stage: "Pinned dependency installation",
                pythonPath: privatePython,
                result: installResult
            )
        }

        let verificationResult: CommandRunnerResult
        do {
            verificationResult = try await runner.run(
                executable: privatePython,
                arguments: ["-c", versionProbe]
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw failure(
                stage: "Pinned dependency verification",
                pythonPath: privatePython,
                details: error.localizedDescription
            )
        }
        guard verificationResult.exitCode == 0 else {
            throw failure(
                stage: "Pinned dependency verification",
                pythonPath: privatePython,
                result: verificationResult
            )
        }

        return privatePython
    }

    static func ensureInstalled(
        pythonPath: URL,
        runner: CommandRunner = SystemCommandRunner()
    ) async throws -> Bool {
        try await findOrInstall(candidates: [pythonPath], runner: runner) != nil
    }

    private static func defaultRequirementsURL() -> URL {
        if let bundled = Bundle.main.url(
            forResource: "requirements-macos",
            withExtension: "txt"
        ) {
            return bundled
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/requirements-macos.txt")
    }

    private static func failure(
        stage: String,
        pythonPath: URL,
        result: CommandRunnerResult
    ) -> MarkitdownInstallerError {
        let details = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return failure(
            stage: stage,
            pythonPath: pythonPath,
            details: details.isEmpty ? fallback : details
        )
    }

    private static func failure(
        stage: String,
        pythonPath: URL,
        details: String
    ) -> MarkitdownInstallerError {
        .preparationFailed(
            stage: stage,
            pythonPath: pythonPath,
            details: details
        )
    }
}
