import SwiftUI

@main
struct MarkItDownApp: App {
    @State private var state = AppState()
    @State private var dropDelegate = FolderDropDelegate()
    @State private var coordinator: AppCoordinator?

    var body: some Scene {
        WindowGroup("Mark-It-Down") {
            ContentView(
                state: state,
                dropDelegate: dropDelegate,
                onPickFolder: { coordinator?.pickFolder() },
                onStart: { coordinator?.startConversion() },
                onStop: { coordinator?.stopConversion() },
                onShowInFinder: { coordinator?.showInFinder() },
                onConvertAnother: { coordinator?.reset() },
                onRecheckPython: {
                    Task { @MainActor in await coordinator?.bootstrap() }
                }
            )
            .task { await initialBootstrap() }
        }
        .windowResizability(.contentSize)
    }

    private func initialBootstrap() async {
        let coord = AppCoordinator(state: state, dropDelegate: dropDelegate)
        self.coordinator = coord
        dropDelegate.onFolder = { [weak coord] url in
            coord?.loadFolder(url)
        }
        await coord.bootstrap()
    }
}