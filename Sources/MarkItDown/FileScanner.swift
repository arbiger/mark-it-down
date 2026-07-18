import Foundation

enum FileScannerError: Error {
    case rootNotADirectory(URL)
    case emptySelection
}

struct ScanResult: Sendable {
    let rootURL: URL
    let files: [SourceFile]
}

enum FileScanner {
    /// Expands selected folders recursively while preserving explicitly selected files.
    /// A file contained in a selected folder is returned only once.
    static func scan(items: [URL], fileManager: FileManager = .default) throws -> ScanResult {
        guard !items.isEmpty else {
            throw FileScannerError.emptySelection
        }

        var sourceURLs: Set<URL> = []
        for item in items.map(\.standardizedFileURL) {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory) else {
                continue
            }

            if isDirectory.boolValue {
                sourceURLs.formUnion(try collectSources(in: item, fileManager: fileManager))
            } else if isSupportedRegularFile(item, fileManager: fileManager) {
                sourceURLs.insert(item)
            }
        }

        let orderedSources = sourceURLs.sorted { $0.path < $1.path }
        let rootURL = selectionRoot(for: items, fileManager: fileManager)
        return ScanResult(
            rootURL: rootURL,
            files: makeSourceFiles(from: orderedSources, fileManager: fileManager)
        )
    }

    static func scan(root: URL, fileManager: FileManager = .default) throws -> [SourceFile] {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            throw FileScannerError.rootNotADirectory(root)
        }

        let sourceURLs = try collectSources(in: root, fileManager: fileManager)
            .sorted { $0.path < $1.path }
        return makeSourceFiles(from: sourceURLs, fileManager: fileManager)
    }

    private static func collectSources(
        in root: URL,
        fileManager: FileManager
    ) throws -> Set<URL> {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var sourceURLs: Set<URL> = []
        for case let url as URL in enumerator {
            guard isSupportedRegularFile(url, fileManager: fileManager) else { continue }
            sourceURLs.insert(url.standardizedFileURL)
        }
        return sourceURLs
    }

    private static func isSupportedRegularFile(_ url: URL, fileManager: FileManager) -> Bool {
        guard SupportedExtensions.isSupported(url) else { return false }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return false }
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        return values?.isRegularFile == true
    }

    private static func makeSourceFiles(
        from sourceURLs: [URL],
        fileManager: FileManager
    ) -> [SourceFile] {
        var reservedOutputs: Set<URL> = []
        return sourceURLs.map { sourceURL in
            let desired = sourceURL.deletingPathExtension().appendingPathExtension("md")
            let outputURL = OutputNamer.nextAvailable(
                for: desired,
                fileManager: fileManager,
                reserving: &reservedOutputs
            )
            return SourceFile(sourceURL: sourceURL, outputURL: outputURL)
        }
    }

    private static func selectionRoot(for items: [URL], fileManager: FileManager) -> URL {
        let first = items[0].standardizedFileURL
        var isDirectory: ObjCBool = false
        if items.count == 1,
           fileManager.fileExists(atPath: first.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return first
        }
        return first.deletingLastPathComponent()
    }
}
