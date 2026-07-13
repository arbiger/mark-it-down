import Foundation

struct FolderJob: Equatable {
    let rootURL: URL
    var files: [SourceFile]

    var counts: ConversionCounts {
        files.reduce(into: ConversionCounts()) { counts, file in
            switch file.status {
            case .pending: counts.pending += 1
            case .running: counts.running += 1
            case .done: counts.succeeded += 1
            case .failed: counts.failed += 1
            case .cancelled: counts.cancelled += 1
            }
        }
    }
}

struct ConversionCounts: Equatable {
    var pending = 0
    var running = 0
    var succeeded = 0
    var failed = 0
    var cancelled = 0

    var completed: Int {
        succeeded + failed + cancelled
    }
}
