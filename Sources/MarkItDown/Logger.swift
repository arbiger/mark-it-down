import Foundation

actor Logger {
    private let fileURL: URL
    private let fm: FileManager
    private let formatter: ISO8601DateFormatter

    init(fileURL: URL, fileManager: FileManager = .default) throws {
        self.fileURL = fileURL
        self.fm = fileManager
        self.formatter = ISO8601DateFormatter()
        self.formatter.formatOptions = [.withInternetDateTime]

        let dir = fileURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: fileURL.path) {
            try "".write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    static func defaultLogURL(fileManager: FileManager = .default) throws -> URL {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = support.appendingPathComponent("Mark-It-Down", isDirectory: true)
        return dir.appendingPathComponent("log.txt")
    }

    func log(_ level: String, _ message: String) {
        let timestamp = formatter.string(from: Date())
        let line = "\(timestamp) [\(level)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if fm.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        } else {
            try? data.write(to: fileURL)
        }
    }
}
