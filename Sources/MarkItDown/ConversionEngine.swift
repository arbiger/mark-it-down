import Foundation

actor ConversionEngine {
    private let markitdown: DocumentConverting
    private let maxConcurrent: Int

    init(markitdown: DocumentConverting, maxConcurrent: Int = 4) {
        self.markitdown = markitdown
        self.maxConcurrent = max(1, maxConcurrent)
    }

    func run(
        job: FolderJob,
        pythonPath: URL,
        update: @MainActor @Sendable @escaping (UUID, ConversionStatus) async -> Void
    ) async {
        await withTaskGroup(of: Void.self) { group in
            var inFlight = 0
            var iterator = job.files.makeIterator()

            while !Task.isCancelled, let file = iterator.next() {
                if inFlight >= maxConcurrent {
                    await group.next()
                    inFlight -= 1
                    if Task.isCancelled { break }
                }
                inFlight += 1
                let id = file.id
                let source = file.sourceURL
                let output = file.outputURL
                let runner = self.markitdown

                group.addTask {
                    do {
                        try Task.checkCancellation()
                        await update(id, .running)
                        try await runner.convert(pythonPath: pythonPath, source: source, output: output)
                        try Task.checkCancellation()
                        await update(id, .done)
                    } catch is CancellationError {
                        await update(id, .cancelled)
                    } catch {
                        await update(id, .failed(error.localizedDescription))
                    }
                }
            }
            if Task.isCancelled {
                group.cancelAll()
            }
            await group.waitForAll()
        }
    }
}
