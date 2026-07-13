import Foundation
import Observation

enum AppMode: Equatable {
    case empty
    case scanning
    case scanFailed(String)
    case noPython
    case installing(progress: String)
    case installFailed(String)
    case preview
    case converting
    case done(succeeded: Int, failed: Int)
}

@Observable
@MainActor
final class AppState {
    var mode: AppMode = .empty
    var job: FolderJob?
    var pythonPath: URL?
}
