import AppKit
import Foundation

@MainActor
final class AppCoordinator {
    let state: AppState
    let dropDelegate: FolderDropDelegate
    private let markitdownRunner: MarkitdownRunning
    private let engine: ConversionEngine
    private let logger: Logger?

    private var currentConversionTask: Task<Void, Never>?

    init(
        state: AppState,
        dropDelegate: FolderDropDelegate,
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
            let pythonPath = try await PythonLocator.locate()
            guard let pythonPath = pythonPath else {
                state.mode = .noPython
                await logger?.log("WARN", "No suitable Python 3.10+ found")
                return
            }
            state.pythonPath = pythonPath
            state.mode = .installing(progress: "Checking markitdown…")
            let installed = try await MarkitdownInstaller.ensureInstalled(pythonPath: pythonPath)
            if installed {
                state.mode = .empty
                await logger?.log("INFO", "Bootstrap complete: \(pythonPath.path)")
            } else {
                state.mode = .installFailed(
                    "Could not install markitdown. Run manually:\n" +
                    "\(pythonPath.path) -m pip install --user 'markitdown[all]'"
                )
            }
        } catch {
            state.mode = .installFailed(String(describing: error))
        }
    }

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            loadFolder(url)
        }
    }

    func loadFolder(_ url: URL) {
        do {
            let files = try FileScanner.scan(root: url)
            let job = FolderJob(rootURL: url, files: files)
            state.job = job
            state.mode = .preview
        } catch {
            state.mode = .installFailed("Failed to scan folder: \(error)")
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

        currentConversionTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            await self.engine.run(
                job: fresh,
                pythonPath: pythonPath,
                update: { id, status in
                    await self.applyStatus(id: id, status: status)
                }
            )
            await self.markDone()
        }
    }

    func stopConversion() {
        currentConversionTask?.cancel()
        currentConversionTask = nil
        state.mode = .preview
    }

    func showInFinder() {
        guard let url = state.job?.rootURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func reset() {
        state.job = nil
        state.mode = .empty
    }

    private func applyStatus(id: UUID, status: ConversionStatus) async {
        guard var job = state.job else { return }
        guard let idx = job.files.firstIndex(where: { $0.id == id }) else { return }
        job.files[idx].status = status
        if case .failed(let msg) = status {
            job.files[idx].errorMessage = msg
        }
        state.job = job
    }

    private func markDone() async {
        guard let job = state.job else { return }
        let succeeded = job.files.filter {
            if case .done = $0.status { return true } else { return false }
        }.count
        let failed = job.files.count - succeeded
        state.mode = .done(succeeded: succeeded, failed: failed)
    }
}