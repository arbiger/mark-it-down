import Foundation

protocol MarkitdownRunning: Sendable {
    func convert(pythonPath: URL, source: URL, output: URL) async throws
}

enum MarkitdownRunnerError: Error, Sendable {
    case nonZeroExit(code: Int32, stderr: String)
    case missingOutput
    case noExtractableContent(isPDF: Bool)
}

extension MarkitdownRunnerError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .nonZeroExit(let code, let stderr):
            let details = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return details.isEmpty ? "markitdown exited with code \(code)" : details
        case .missingOutput:
            return "Conversion finished without creating a Markdown file."
        case .noExtractableContent(let isPDF):
            if isPDF {
                return "No text could be extracted from this PDF. It may contain scanned pages or text converted to outlines. OCR is required, or export a PDF with selectable text."
            }
            return "Conversion produced an empty Markdown file because no extractable content was found."
        }
    }
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

        guard FileManager.default.fileExists(atPath: output.path) else {
            throw MarkitdownRunnerError.missingOutput
        }

        let markdown = try String(contentsOf: output, encoding: .utf8)
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            try? FileManager.default.removeItem(at: output)
            throw MarkitdownRunnerError.noExtractableContent(
                isPDF: source.pathExtension.lowercased() == "pdf"
            )
        }
    }
}
