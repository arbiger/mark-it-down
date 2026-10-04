import Foundation

private enum InspectorBehavior: Sendable {
    case result(PDFInspection, markdown: String?)
    case parserFailure
    case cancellation
}

private enum InspectorTestError: Error {
    case parserFailure
}

private actor RecordingConverter: DocumentConverting {
    private var calls = 0
    private let content: String

    init(content: String = "fallback") {
        self.content = content
    }

    func convert(pythonPath: URL, source: URL, output: URL) async throws {
        calls += 1
        try content.write(to: output, atomically: true, encoding: .utf8)
    }

    func callCount() -> Int { calls }
}

private actor StubInspector: PDFInspecting {
    private var calls = 0
    private let behavior: InspectorBehavior

    init(_ behavior: InspectorBehavior) {
        self.behavior = behavior
    }

    func inspect(
        pythonPath: URL,
        source: URL,
        temporaryOutput: URL
    ) async throws -> PDFInspection {
        calls += 1
        switch behavior {
        case .result(let inspection, let markdown):
            if let markdown {
                try markdown.write(to: temporaryOutput, atomically: true, encoding: .utf8)
            }
            return inspection
        case .parserFailure:
            throw InspectorTestError.parserFailure
        case .cancellation:
            throw CancellationError()
        }
    }

    func callCount() -> Int { calls }
}

enum HybridConversionTests {
    static let all: [TestCase] = [
        ("non-PDF uses MarkItDown once and never inspector", nonPDFUsesMarkItDown),
        ("clean text_based PDF writes output", cleanTextPDFUsesInspector),
        ("text_based OCR pages fail", textPDFWithOCRPagesFails),
        ("scanned OCR pages fail", scannedPDFFails),
        ("image_based empty pages fail", imageBasedPDFFails),
        ("mixed PDF fails", mixedPDFFails),
        ("encoding fallback once", encodingIssueFallsBackOnce),
        ("parser fallback once", parserFailureFallsBackOnce),
        ("cancellation propagates without fallback", cancellationPropagates),
        ("unsupported schema falls back once", unsupportedSchemaFallsBackOnce),
        ("unknown classification falls back once", unknownClassificationFallsBackOnce),
        ("markdownWritten false fails", markdownNotWrittenFails),
        ("missing inspector output fails", missingInspectorOutputFails),
        ("whitespace inspector output fails", whitespaceInspectorOutputFails),
        ("helper runner invokes injected path", helperRunnerUsesInjectedPath),
        ("helper runner rejects malformed JSON", helperRunnerRejectsMalformedJSON),
        ("helper runner preserves nonzero stderr", helperRunnerPreservesFailure)
    ]

    private static func inspection(
        _ classification: PDFClassification,
        pages: [Int] = [],
        encodingSuspect: Bool = false,
        markdownWritten: Bool = false,
        schemaVersion: Int = 1
    ) -> PDFInspection {
        PDFInspection(
            schemaVersion: schemaVersion,
            classification: classification,
            pagesNeedingOCR: pages,
            encodingSuspect: encodingSuspect,
            markdownWritten: markdownWritten
        )
    }

    private static func withURLs<T>(
        extension pathExtension: String = "pdf",
        _ body: (URL, URL, URL) async throws -> T
    ) async throws -> T {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let source = directory.url.appendingPathComponent("input.\(pathExtension)")
        let output = directory.url.appendingPathComponent("output.md")
        try Data().write(to: source)
        return try await body(directory.url, source, output)
    }

    private static func convert(
        converter: RecordingConverter,
        inspector: StubInspector,
        source: URL,
        output: URL
    ) async throws {
        try await HybridConversionRouter(
            markitdown: converter,
            inspector: inspector
        ).convert(
            pythonPath: URL(fileURLWithPath: "/tmp/test-python"),
            source: source,
            output: output
        )
    }

    private static func assertNoTemporaryFiles(in directory: URL) throws {
        let leftovers = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".tmp-") }
        try expect(leftovers.isEmpty, "Expected temporary files to be cleaned: \(leftovers)")
    }

    private static func assertOCRFailure(
        classification: PDFClassification,
        pages: [Int]
    ) async throws {
        try await withURLs { directory, source, output in
            let converter = RecordingConverter()
            let inspector = StubInspector(.result(
                inspection(classification, pages: pages),
                markdown: nil
            ))

            do {
                try await convert(
                    converter: converter,
                    inspector: inspector,
                    source: source,
                    output: output
                )
                throw TestFailure(description: "Expected OCR-required failure")
            } catch HybridConversionError.ocrRequired(let actualPages) {
                try expectEqual(actualPages, pages)
                let message = HybridConversionError.ocrRequired(pages: actualPages)
                    .localizedDescription
                try expect(message.contains("OCR"), "Expected actionable OCR guidance")
                if pages.isEmpty {
                    try expect(message.contains("one or more"), "Expected useful generic guidance")
                    try expect(!message.contains("page(s) ."), "Expected natural OCR wording")
                } else {
                    for page in pages {
                        try expect(message.contains(String(page)), "Expected page \(page) in guidance")
                    }
                }
            }

            try expectEqual(await inspector.callCount(), 1)
            try expectEqual(await converter.callCount(), 0)
            try expect(!FileManager.default.fileExists(atPath: output.path), "Expected no final output")
            try assertNoTemporaryFiles(in: directory)
        }
    }

    private static func nonPDFUsesMarkItDown() async throws {
        try await withURLs(extension: "txt") { directory, source, output in
            let converter = RecordingConverter(content: "general converter")
            let inspector = StubInspector(.result(inspection(.textBased), markdown: nil))
            try await convert(converter: converter, inspector: inspector, source: source, output: output)
            try expectEqual(try String(contentsOf: output, encoding: .utf8), "general converter")
            try expectEqual(await converter.callCount(), 1)
            try expectEqual(await inspector.callCount(), 0)
            try assertNoTemporaryFiles(in: directory)
        }
    }

    private static func cleanTextPDFUsesInspector() async throws {
        try await withURLs { directory, source, output in
            let converter = RecordingConverter()
            let inspector = StubInspector(.result(
                inspection(.textBased, markdownWritten: true),
                markdown: "# fast"
            ))
            try await convert(converter: converter, inspector: inspector, source: source, output: output)
            try expectEqual(try String(contentsOf: output, encoding: .utf8), "# fast")
            try expectEqual(await inspector.callCount(), 1)
            try expectEqual(await converter.callCount(), 0)
            try assertNoTemporaryFiles(in: directory)
        }
    }

    private static func textPDFWithOCRPagesFails() async throws {
        try await assertOCRFailure(classification: .textBased, pages: [2])
    }

    private static func scannedPDFFails() async throws {
        try await assertOCRFailure(classification: .scanned, pages: [1, 3])
    }

    private static func imageBasedPDFFails() async throws {
        try await assertOCRFailure(classification: .imageBased, pages: [])
    }

    private static func mixedPDFFails() async throws {
        try await assertOCRFailure(classification: .mixed, pages: [1])
    }

    private static func encodingIssueFallsBackOnce() async throws {
        try await withURLs { directory, source, output in
            let converter = RecordingConverter(content: "fallback")
            let inspector = StubInspector(.result(
                inspection(.textBased, encodingSuspect: true, markdownWritten: true),
                markdown: "partial inspector output"
            ))
            try await convert(converter: converter, inspector: inspector, source: source, output: output)
            try expectEqual(try String(contentsOf: output, encoding: .utf8), "fallback")
            try expectEqual(await inspector.callCount(), 1)
            try expectEqual(await converter.callCount(), 1)
            try assertNoTemporaryFiles(in: directory)
        }
    }

    private static func parserFailureFallsBackOnce() async throws {
        try await withURLs { directory, source, output in
            let converter = RecordingConverter(content: "fallback")
            let inspector = StubInspector(.parserFailure)
            try await convert(converter: converter, inspector: inspector, source: source, output: output)
            try expectEqual(try String(contentsOf: output, encoding: .utf8), "fallback")
            try expectEqual(await inspector.callCount(), 1)
            try expectEqual(await converter.callCount(), 1)
            try assertNoTemporaryFiles(in: directory)
        }
    }

    private static func cancellationPropagates() async throws {
        try await withURLs { directory, source, output in
            let converter = RecordingConverter()
            let inspector = StubInspector(.cancellation)

            do {
                try await convert(
                    converter: converter,
                    inspector: inspector,
                    source: source,
                    output: output
                )
                throw TestFailure(description: "Expected cancellation")
            } catch is CancellationError {
                // Expected.
            }

            try expectEqual(await inspector.callCount(), 1)
            try expectEqual(await converter.callCount(), 0)
            try expect(!FileManager.default.fileExists(atPath: output.path), "Expected no final output")
            try assertNoTemporaryFiles(in: directory)
        }
    }

    private static func unsupportedSchemaFallsBackOnce() async throws {
        try await assertFallback(
            inspection: inspection(
                .textBased,
                markdownWritten: true,
                schemaVersion: 2
            ),
            inspectorMarkdown: "unsupported schema"
        )
    }

    private static func unknownClassificationFallsBackOnce() async throws {
        try await assertFallback(
            inspection: inspection(.unknown, markdownWritten: true),
            inspectorMarkdown: "unknown classification"
        )
    }

    private static func assertFallback(
        inspection: PDFInspection,
        inspectorMarkdown: String?
    ) async throws {
        try await withURLs { directory, source, output in
            let converter = RecordingConverter(content: "fallback")
            let inspector = StubInspector(.result(
                inspection,
                markdown: inspectorMarkdown
            ))

            try await convert(
                converter: converter,
                inspector: inspector,
                source: source,
                output: output
            )

            try expectEqual(try String(contentsOf: output, encoding: .utf8), "fallback")
            try expectEqual(await inspector.callCount(), 1)
            try expectEqual(await converter.callCount(), 1)
            try assertNoTemporaryFiles(in: directory)
        }
    }

    private static func markdownNotWrittenFails() async throws {
        try await assertEmptyInspectorFailure(
            inspection: inspection(.textBased, markdownWritten: false),
            inspectorMarkdown: nil
        )
    }

    private static func missingInspectorOutputFails() async throws {
        try await assertEmptyInspectorFailure(
            inspection: inspection(.textBased, markdownWritten: true),
            inspectorMarkdown: nil
        )
    }

    private static func whitespaceInspectorOutputFails() async throws {
        try await assertEmptyInspectorFailure(
            inspection: inspection(.textBased, markdownWritten: true),
            inspectorMarkdown: " \n\t"
        )
    }

    private static func assertEmptyInspectorFailure(
        inspection: PDFInspection,
        inspectorMarkdown: String?
    ) async throws {
        try await withURLs { directory, source, output in
            let converter = RecordingConverter()
            let inspector = StubInspector(.result(
                inspection,
                markdown: inspectorMarkdown
            ))

            do {
                try await convert(
                    converter: converter,
                    inspector: inspector,
                    source: source,
                    output: output
                )
                throw TestFailure(description: "Expected empty inspector output to fail")
            } catch MarkitdownRunnerError.noExtractableContent(let isPDF) {
                try expect(isPDF, "Expected PDF empty-content failure")
            }

            try expectEqual(await inspector.callCount(), 1)
            try expectEqual(await converter.callCount(), 0)
            try expect(!FileManager.default.fileExists(atPath: output.path), "Expected no final output")
            try assertNoTemporaryFiles(in: directory)
        }
    }

    private static func helperRunnerUsesInjectedPath() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let python = directory.url.appendingPathComponent("python")
        let helper = directory.url.appendingPathComponent("helper.py")
        let source = directory.url.appendingPathComponent("source.pdf")
        let temporaryOutput = directory.url.appendingPathComponent("temporary.md")
        let json = """
        {"schemaVersion":1,"classification":"text_based","pagesNeedingOCR":[],"encodingSuspect":false,"markdownWritten":true}
        """
        let runner = QueuedCommandRunner([
            .result(CommandRunnerResult(exitCode: 0, stdout: json, stderr: ""))
        ])

        let result = try await PDFInspectorRunner(
            runner: runner,
            helper: helper
        ).inspect(
            pythonPath: python,
            source: source,
            temporaryOutput: temporaryOutput
        )

        try expectEqual(result.classification, .textBased)
        try expect(result.markdownWritten, "Expected decoded markdownWritten flag")
        let invocations = await runner.invocations
        try expectEqual(invocations.count, 1)
        try expectEqual(invocations[0].0, python)
        try expectEqual(
            invocations[0].1,
            [helper.path, source.path, temporaryOutput.path]
        )
    }

    private static func helperRunnerRejectsMalformedJSON() async throws {
        let runner = QueuedCommandRunner([
            .result(CommandRunnerResult(exitCode: 0, stdout: "not-json", stderr: ""))
        ])

        do {
            _ = try await PDFInspectorRunner(
                runner: runner,
                helper: URL(fileURLWithPath: "/tmp/helper.py")
            ).inspect(
                pythonPath: URL(fileURLWithPath: "/tmp/python"),
                source: URL(fileURLWithPath: "/tmp/source.pdf"),
                temporaryOutput: URL(fileURLWithPath: "/tmp/temporary.md")
            )
            throw TestFailure(description: "Expected malformed JSON failure")
        } catch HybridConversionError.invalidInspection {
            // Expected.
        }
    }

    private static func helperRunnerPreservesFailure() async throws {
        let runner = QueuedCommandRunner([
            .result(CommandRunnerResult(exitCode: 7, stdout: "", stderr: "parser marker"))
        ])

        do {
            _ = try await PDFInspectorRunner(
                runner: runner,
                helper: URL(fileURLWithPath: "/tmp/helper.py")
            ).inspect(
                pythonPath: URL(fileURLWithPath: "/tmp/python"),
                source: URL(fileURLWithPath: "/tmp/source.pdf"),
                temporaryOutput: URL(fileURLWithPath: "/tmp/temporary.md")
            )
            throw TestFailure(description: "Expected nonzero helper failure")
        } catch MarkitdownRunnerError.nonZeroExit(let code, let stderr) {
            try expectEqual(code, 7)
            try expectEqual(stderr, "parser marker")
        }
    }
}
