import AppKit
import Foundation

@MainActor
final class AppCoordinator {
    let state: AppState
    let dropDelegate: ItemDropDelegate
    private let markitdownRunner: MarkitdownRunning
    private let engine: ConversionEngine
    private let logger: Logger?

    private var scanTask: Task<Void, Never>?
    private var currentConversionTask: Task<Void, Never>?
    private var activeScanID: UUID?
    private var activeConversionID: UUID?

    init(
        state: AppState,
        dropDelegate: ItemDropDelegate,
        markitdownRunner: MarkitdownRunning = MarkitdownRunner(),
        engine: ConversionEngine? = nil,
        logger: Logger? = nil
    ) {
        self.state = state
        self.dropDelegate = dropDelegate
        self.markitdownRunner = markitdownRunner
        self.engine = engine ?? ConversionEngine(markitdown: markitdownRunner)
        self.logger = logger
    }

    func bootstrap() async {
        do {
            let candidates = try await PythonLocator.locateAll()
            guard !candidates.isEmpty else {
                state.mode = .noPython
                await logger?.log("WARN", "No suitable Python 3.10+ found")
                return
            }
            state.mode = .installing(progress: "Looking for existing markitdown…")
            let chosen = try await MarkitdownInstaller.findOrInstall(candidates: candidates)
            if let chosen {
                state.pythonPath = chosen
                state.mode = .empty
                await logger?.log("INFO", "Bootstrap complete: \(chosen.path)")
            } else {
                let first = candidates.first!.path
                state.mode = .installFailed(
                    "Could not install markitdown. Run manually:\n" +
                    "\(first) -m pip install --user --break-system-packages 'markitdown[all]'"
                )
            }
        } catch {
            state.mode = .installFailed(String(describing: error))
        }
    }

    func pickItems() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Choose"
        panel.message = "Choose one or more files or folders to convert"
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            loadItems(panel.urls)
        }
    }

    func loadFolder(_ url: URL) {
        loadItems([url])
    }

    func loadItems(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        scanTask?.cancel()
        let scanID = UUID()
        activeScanID = scanID
        state.mode = .scanning

        scanTask = Task { @MainActor [weak self] in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try FileScanner.scan(items: urls)
                }.value
                try Task.checkCancellation()
                guard let self, self.activeScanID == scanID else { return }
                self.activeScanID = nil
                self.scanTask = nil
                self.state.job = FolderJob(rootURL: result.rootURL, files: result.files)
                self.state.mode = .preview
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.activeScanID == scanID else { return }
                self.activeScanID = nil
                self.scanTask = nil
                self.state.mode = .scanFailed(error.localizedDescription)
            }
        }
    }

    func startConversion() {
        guard let job = state.job, let pythonPath = state.pythonPath else { return }
        state.mode = .converting
        var fresh = job
        for i in fresh.files.indices {
            fresh.files[i].status = .pending
            fresh.files[i].errorMessage = nil
        }
        state.job = fresh

        currentConversionTask?.cancel()
        let conversionID = UUID()
        activeConversionID = conversionID
        currentConversionTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            await self.engine.run(
                job: fresh,
                pythonPath: pythonPath,
                update: { [weak self] id, status in
                    guard let self, self.activeConversionID == conversionID else { return }
                    self.applyStatus(id: id, status: status)
                }
            )
            guard self.activeConversionID == conversionID else { return }
            self.activeConversionID = nil
            self.currentConversionTask = nil
            self.markDone()
        }
    }

    func stopConversion() {
        activeConversionID = nil
        currentConversionTask?.cancel()
        currentConversionTask = nil
        state.mode = .preview
    }

    func showInFinder() {
        guard let job = state.job else { return }
        let outputs = job.files.map(\.outputURL).filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        NSWorkspace.shared.activateFileViewerSelecting(outputs.isEmpty ? [job.rootURL] : outputs)
    }

    func reset() {
        activeScanID = nil
        scanTask?.cancel()
        scanTask = nil
        activeConversionID = nil
        currentConversionTask?.cancel()
        currentConversionTask = nil
        state.job = nil
        state.mode = .empty
    }

    private func applyStatus(id: UUID, status: ConversionStatus) {
        guard var job = state.job else { return }
        guard let idx = job.files.firstIndex(where: { $0.id == id }) else { return }
        job.files[idx].status = status
        if case .failed(let msg) = status {
            job.files[idx].errorMessage = msg
        }
        state.job = job
    }

    private func markDone() {
        guard let job = state.job else { return }
        let counts = job.counts
        state.mode = .done(succeeded: counts.succeeded, failed: counts.failed)
    }
}
