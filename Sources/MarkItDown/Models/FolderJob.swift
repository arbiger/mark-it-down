import Foundation

struct FolderJob: Equatable {
    let rootURL: URL
    var files: [SourceFile]
}