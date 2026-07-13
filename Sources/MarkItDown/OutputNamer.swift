import Foundation

enum OutputNamer {
    static func nextAvailable(for desiredURL: URL, fileManager: FileManager = .default) -> URL {
        if !fileManager.fileExists(atPath: desiredURL.path) {
            return desiredURL
        }
        let dir = desiredURL.deletingLastPathComponent()
        let stem = desiredURL.deletingPathExtension().lastPathComponent
        let ext = desiredURL.pathExtension
        var n = 1
        while true {
            let candidateName = ext.isEmpty
                ? "\(stem)(\(n))"
                : "\(stem)(\(n)).\(ext)"
            let candidate = dir.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            n += 1
        }
    }
}