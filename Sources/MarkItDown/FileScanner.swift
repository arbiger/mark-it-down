import Foundation

enum FileScannerError: Error {
    case rootNotADirectory(URL)
}

enum FileScanner {
    static func scan(root: URL, fileManager: FileManager = .default) throws -> [SourceFile] {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            throw FileScannerError.rootNotADirectory(root)
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var sourceURLs: [URL] = []
        for case let url as URL in enumerator {
            guard SupportedExtensions.isSupported(url) else { continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            sourceURLs.append(url)
        }

        sourceURLs.sort { $0.path < $1.path }
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
}
