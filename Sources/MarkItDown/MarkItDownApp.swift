import SwiftUI

@main
struct MarkItDownApp: App {
    var body: some Scene {
        WindowGroup("Mark-It-Down") {
            Text("Mark-It-Down")
                .frame(width: 520, height: 640)
        }
        .windowResizability(.contentSize)
    }
}