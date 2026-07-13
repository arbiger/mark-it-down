import Foundation

actor ConversionEngine {
    private let markitdown: MarkitdownRunning
    private let maxConcurrent: Int

    init(markitdown: MarkitdownRunning, maxConcurrent: Int = 4) {
        self.markitdown = markitdown
        self.maxConcurrent = max(1, maxConcurrent)
    }

    func run(
        job: FolderJob,
        pythonPath: URL,
        update: @MainActor @escaping (UUID, ConversionStatus) async -> Void
    ) async {
        await withTaskGroup(of: Void.self) { group in
            var inFlight = 0
            var iterator = job.files.makeIterator()

            while let file = iterator.next() {
                if inFlight >= maxConcurrent {
                    await group.next()
                    inFlight -= 1
                }
                inFlight += 1
                let id = file.id
                let source = file.sourceURL
                let output = file.outputURL
                let runner = self.markitdown

                group.addTask {
                    await update(id, .running)
                    do {
                        try await runner.convert(pythonPath: pythonPath, source: source, output: output)
                        await update(id, .done)
                    } catch {
                        let msg = (error as? MarkitdownRunnerError).map { String(describing: $0) }
                            ?? String(describing: error)
                        await update(id, .failed(msg))
                    }
                }
            }
            await group.waitForAll()
        }
    }
}