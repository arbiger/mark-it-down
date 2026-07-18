import SwiftUI

@main
struct MarkItDownApp: App {
    @State private var state = AppState()
    @State private var dropDelegate = ItemDropDelegate()
    @State private var coordinator: AppCoordinator?

    var body: some Scene {
        WindowGroup("Mark-It-Down") {
            ContentView(
                state: state,
                dropDelegate: dropDelegate,
                onPickItems: { coordinator?.pickItems() },
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
        dropDelegate.onItems = { [weak coord] urls in
            coord?.loadItems(urls)
        }
        await coord.bootstrap()
    }
}
