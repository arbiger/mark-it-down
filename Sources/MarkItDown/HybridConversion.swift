import Foundation

enum PDFClassification: String, Codable, Sendable {
    case textBased = "text_based"
    case imageBased = "image_based"
    case mixed
    case scanned
    case unknown
}

struct PDFInspection: Codable, Sendable {
    let schemaVersion: Int
    let classification: PDFClassification
    let pagesNeedingOCR: [Int]
    let encodingSuspect: Bool
    let markdownWritten: Bool
}

protocol PDFInspecting: Sendable {
    func inspect(pythonPath: URL, source: URL, temporaryOutput: URL) async throws -> PDFInspection
}

enum HybridConversionError: LocalizedError, Sendable {
    case ocrRequired(pages: [Int])
    case invalidInspection

    var errorDescription: String? {
        switch self {
        case .ocrRequired(let pages):
            let list = pages.map(String.init).joined(separator: ", ")
            let detail = list.isEmpty ? "one or more pages" : "page(s) \(list)"
            return "OCR is required for \(detail). Export a selectable-text PDF or run OCR before converting."
        case .invalidInspection:
            return "PDF Inspector returned an invalid result."
        }
    }
}

struct HybridConversionRouter: DocumentConverting {
    let markitdown: DocumentConverting
    let inspector: PDFInspecting?

    init(markitdown: DocumentConverting, inspector: PDFInspecting? = nil) {
        self.markitdown = markitdown
        self.inspector = inspector
    }

    func convert(pythonPath: URL, source: URL, output: URL) async throws {
        guard source.pathExtension.lowercased() == "pdf", let inspector else {
            try await markitdown.convert(pythonPath: pythonPath, source: source, output: output)
            return
        }
        do {
            let temp = output.deletingLastPathComponent().appendingPathComponent(".tmp-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: temp) }
            let result = try await inspector.inspect(pythonPath: pythonPath, source: source, temporaryOutput: temp)
            guard result.schemaVersion == 1 else { throw HybridConversionError.invalidInspection }

            if !result.pagesNeedingOCR.isEmpty {
                throw HybridConversionError.ocrRequired(pages: result.pagesNeedingOCR)
            }

            switch result.classification {
            case .scanned, .imageBased, .mixed:
                throw HybridConversionError.ocrRequired(pages: result.pagesNeedingOCR)
            case .unknown:
                throw HybridConversionError.invalidInspection
            case .textBased:
                break
            }

            if result.encodingSuspect {
                try await markitdown.convert(
                    pythonPath: pythonPath,
                    source: source,
                    output: output
                )
                return
            }

            guard result.markdownWritten,
                  FileManager.default.fileExists(atPath: temp.path),
                  let markdown = try? String(contentsOf: temp, encoding: .utf8),
                  !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MarkitdownRunnerError.noExtractableContent(isPDF: true)
            }

            try FileManager.default.moveItem(at: temp, to: output)
        } catch is CancellationError {
            throw CancellationError()
        } catch HybridConversionError.ocrRequired(let pages) {
            throw HybridConversionError.ocrRequired(pages: pages)
        } catch MarkitdownRunnerError.noExtractableContent(let isPDF) {
            throw MarkitdownRunnerError.noExtractableContent(isPDF: isPDF)
        } catch {
            try await markitdown.convert(pythonPath: pythonPath, source: source, output: output)
        }
    }
}

struct PDFInspectorRunner: PDFInspecting {
    private let runner: CommandRunner
    private let helper: URL
    init(runner: CommandRunner = SystemCommandRunner(), helper: URL? = nil) {
        self.runner = runner
        self.helper = helper ?? Bundle.main.url(forResource: "markitdown_pdf_inspector", withExtension: "py") ?? URL(fileURLWithPath: "Resources/markitdown_pdf_inspector.py")
    }

    func inspect(pythonPath: URL, source: URL, temporaryOutput: URL) async throws -> PDFInspection {
        let result = try await runner.run(executable: pythonPath, arguments: [helper.path, source.path, temporaryOutput.path])
        guard result.exitCode == 0 else { throw MarkitdownRunnerError.nonZeroExit(code: result.exitCode, stderr: result.stderr) }
        guard let data = result.stdout.data(using: .utf8), let inspection = try? JSONDecoder().decode(PDFInspection.self, from: data) else {
            throw HybridConversionError.invalidInspection
        }
        return inspection
    }
}
