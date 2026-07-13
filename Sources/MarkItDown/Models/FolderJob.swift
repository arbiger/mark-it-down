import Foundation

struct FolderJob: Equatable {
    let rootURL: URL
    let files: [SourceFile]
}