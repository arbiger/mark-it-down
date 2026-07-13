import Foundation

enum PythonLocatorError: Error {
    case unsuitableVersion(URL, String)
}

enum PythonLocator {
    static let defaultProbePaths: [URL] = [
        URL(fileURLWithPath: "/opt/homebrew/bin/python3"),
        URL(fileURLWithPath: "/usr/local/bin/python3"),
        URL(fileURLWithPath: "/Library/Frameworks/Python.framework/Versions/Current/bin/python3"),
        URL(fileURLWithPath: "/usr/bin/python3")
    ]

    static func locate(
        fileManager: FileManager = .default,
        probePaths: [URL] = PythonLocator.defaultProbePaths,
        versionProvider: @escaping (URL) async throws -> String? = { url in
            try await runVersionCheck(pythonURL: url)
        }
    ) async throws -> URL? {
        try await locateAll(fileManager: fileManager, probePaths: probePaths, versionProvider: versionProvider).first
    }

    /// Returns ALL acceptable Python 3.10+ candidates, in probe order. Used by callers that
    /// want to scan across multiple pythons (e.g. looking for one that already has markitdown).
    static func locateAll(
        fileManager: FileManager = .default,
        probePaths: [URL] = PythonLocator.defaultProbePaths,
        versionProvider: @escaping (URL) async throws -> String? = { url in
            try await runVersionCheck(pythonURL: url)
        }
    ) async throws -> [URL] {
        var found: [URL] = []
        for path in probePaths {
            guard fileManager.isExecutableFile(atPath: path.path) else { continue }
            guard let versionString = try? await versionProvider(path) else { continue }
            if isAcceptable(versionString) {
                found.append(path)
            }
        }
        return found
    }

    static func isAcceptable(_ version: String) -> Bool {
        // Accepts "Python 3.10.5" / "3.10.5" / "3.10"
        let stripped = version.replacingOccurrences(of: "Python ", with: "")
        let parts = stripped.split(separator: ".")
        guard parts.count >= 2,
              let major = Int(parts[0]),
              let minor = Int(parts[1]) else {
            return false
        }
        if major > 3 { return true }
        return major == 3 && minor >= 10
    }

    private static func runVersionCheck(pythonURL: URL) async throws -> String? {
        try await withCheckedThrowingContinuation { cont in
            let process = Process()
            process.executableURL = pythonURL
            process.arguments = ["--version"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { proc in
                let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
                let s = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                cont.resume(returning: s)
            }
            do {
                try process.run()
            } catch {
                cont.resume(returning: nil)
            }
        }
    }
}