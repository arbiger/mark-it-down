import Foundation

enum OutputNamer {
    static func nextAvailable(for desiredURL: URL, fileManager: FileManager = .default) -> URL {
        var reserved: Set<URL> = []
        return nextAvailable(for: desiredURL, fileManager: fileManager, reserving: &reserved)
    }

    static func nextAvailable(
        for desiredURL: URL,
        fileManager: FileManager = .default,
        reserving reserved: inout Set<URL>
    ) -> URL {
        let dir = desiredURL.deletingLastPathComponent()
        let stem = desiredURL.deletingPathExtension().lastPathComponent
        let ext = desiredURL.pathExtension
        var n = 0

        while true {
            let candidateName: String
            if n == 0 {
                candidateName = desiredURL.lastPathComponent
            } else {
                candidateName = ext.isEmpty
                    ? "\(stem)(\(n))"
                    : "\(stem)(\(n)).\(ext)"
            }
            let candidate = dir.appendingPathComponent(candidateName).standardizedFileURL
            if !fileManager.fileExists(atPath: candidate.path), !reserved.contains(candidate) {
                reserved.insert(candidate)
                return candidate
            }
            n += 1
        }
    }
}
