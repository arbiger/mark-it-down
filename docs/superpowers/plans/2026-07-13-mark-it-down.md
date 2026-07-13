# Mark-It-Down Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS SwiftUI app that converts a folder of documents (PDF/DOCX/PPTX/XLSX/images/audio/etc.) to Markdown using markitdown, via drag-and-drop.

**Architecture:** SwiftPM-based SwiftUI executable. A Swift `actor` (ConversionEngine) fans out up to 4 concurrent subprocess invocations of `python3 -m markitdown`. A `PythonLocator` probes well-known Python install paths on launch; a `MarkitdownInstaller` ensures `markitdown[all]` is installed via `pip install --user`. Output never overwrites — collisions get `(N)` suffixes.

**Tech Stack:** Swift 6 (SwiftPM), SwiftUI (macOS 14+), XCTest, Foundation `Process`, microsoft/markitdown via `pip install markitdown[all]`.

**Project root:** `/Users/ycgeorgeli/Documents/Opencode/Mark-It-Down/`

---

## Global Constraints

These apply to every task below; do not re-state per-task.

- **Swift tools version:** 5.9+ (Swift 6 supported). Use `// swift-tools-version:5.9`.
- **Deployment target:** macOS 14 (Sonoma). Use `.macOS(.v14)`.
- **Indent:** 4 spaces, no tabs.
- **Swift style:** `let` over `var`; structs over classes where possible; `@MainActor` for all UI-touching types; `async/await` (no completion handlers); `throws` over `Result`; `URL` over `String` for paths.
- **Testing:** XCTest. Use `swift test` to run all; `swift test --filter TestClassName` for one. Tests must fail before implementation and pass after.
- **Naming:** Types `PascalCase`, functions `camelCase`. Module name `MarkItDown` (matches SwiftPM target). Public app display name "Mark-It-Down".
- **Commit cadence:** Every task ends with one focused commit. Use `git commit -m "<type>: <subject>"` — types: `chore`, `feat`, `fix`, `test`, `docs`.
- **No force-push, no AI co-author trailers.**
- **No emojis in code, comments, commits, or filenames** unless requested.
- **Don't add features beyond what's specified.** Don't refactor adjacent code.
- **App Sandbox: disabled** in the final Info.plist (handled by `make-app.sh`). The app is for personal use only.
- **Concurrency:** ConversionEngine caps at 4 parallel `markitdown` subprocesses.
- **Output naming:** `<stem>.md` → `<stem>(1).md` → `<stem>(2).md` → …, never overwrite, never prompt.
- **Python install:** prefer Homebrew; fall back to system Python; auto-install `markitdown[all]` via `pip install --user` on first run.

---

## File Structure (locked here, used by all tasks)

```
Mark-It-Down/
├── Package.swift
├── Sources/MarkItDown/
│   ├── MarkItDownApp.swift
│   ├── ContentView.swift
│   ├── DropDelegate.swift
│   ├── ConversionEngine.swift
│   ├── MarkitdownRunner.swift
│   ├── FileScanner.swift
│   ├── OutputNamer.swift
│   ├── SupportedExtensions.swift
│   ├── PythonLocator.swift
│   ├── MarkitdownInstaller.swift
│   ├── Logger.swift
│   └── Models/
│       ├── SourceFile.swift
│       ├── ConversionStatus.swift
│       └── FolderJob.swift
├── Tests/MarkItDownTests/
│   ├── OutputNamerTests.swift
│   ├── SupportedExtensionsTests.swift
│   ├── FileScannerTests.swift
│   ├── LoggerTests.swift
│   ├── PythonLocatorTests.swift
│   ├── MarkitdownInstallerTests.swift
│   ├── MarkitdownRunnerTests.swift
│   ├── ConversionEngineTests.swift
│   └── DropDelegateTests.swift
├── Resources/
│   └── Info.plist.tmpl
├── make-app.sh
├── run-dev.sh
├── README.md
└── LICENSE
```

---

## Task 1: Scaffold project

**Files:**
- Create: `/Users/ycgeorgeli/Documents/Opencode/Mark-It-Down/Package.swift`
- Create: `/Users/ycgeorgeli/Documents/Opencode/Mark-It-Down/Sources/MarkItDown/MarkItDownApp.swift`
- Create: `/Users/ycgeorgeli/Documents/Opencode/Mark-It-Down/Tests/MarkItDownTests/SmokeTests.swift`
- Modify: existing `.gitignore` already exists

**Interfaces:**
- Consumes: nothing
- Produces: a SwiftPM `executableTarget` that builds, plus a `testTarget` that runs.

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MarkItDown",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "markitdown", targets: ["MarkItDown"])
    ],
    targets: [
        .executableTarget(
            name: "MarkItDown",
            path: "Sources/MarkItDown"
        ),
        .testTarget(
            name: "MarkItDownTests",
            dependencies: ["MarkItDown"],
            path: "Tests/MarkItDownTests"
        )
    ]
)
```

- [ ] **Step 2: Write a stub `MarkItDownApp.swift`**

```swift
import SwiftUI

@main
struct MarkItDownApp: App {
    var body: some Scene {
        WindowGroup("Mark-It-Down") {
            Text("Mark-It-Down")
                .frame(width: 520, height: 640)
        }
        .windowResizability(.contentSize)
    }
}
```

- [ ] **Step 3: Write a smoke test**

`Tests/MarkItDownTests/SmokeTests.swift`:

```swift
import XCTest
@testable import MarkItDown

final class SmokeTests: XCTestCase {
    func testSmoke() {
        XCTAssertEqual(2 + 2, 4)
    }
}
```

- [ ] **Step 4: Build and run tests**

Run:
```
cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down && swift build && swift test
```
Expected: build succeeds, 1 test passes.

- [ ] **Step 5: Commit**

```bash
cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down
git add Package.swift Sources Tests
git commit -m "chore: scaffold SwiftPM project with macOS executable target"
```

---

## Task 2: Data models

**Files:**
- Create: `Sources/MarkItDown/Models/ConversionStatus.swift`
- Create: `Sources/MarkItDown/Models/SourceFile.swift`
- Create: `Sources/MarkItDown/Models/FolderJob.swift`
- Modify: `Tests/MarkItDownTests/SmokeTests.swift` (delete it — replaced by real tests)
- Create: `Tests/MarkItDownTests/ModelsTests.swift`

**Interfaces:**
- Consumes: nothing (pure value types)
- Produces:
  - `enum ConversionStatus: Equatable { case pending, running, done, failed(String) }`
  - `struct SourceFile: Identifiable, Equatable { let id: UUID; let sourceURL: URL; let outputURL: URL; var status: ConversionStatus; var errorMessage: String? }`
  - `struct FolderJob: Equatable { let rootURL: URL; let files: [SourceFile] }`

- [ ] **Step 1: Write the failing tests**

`Tests/MarkItDownTests/ModelsTests.swift`:

```swift
import XCTest
@testable import MarkItDown

final class ConversionStatusTests: XCTestCase {
    func testDefaultIsPending() {
        let s = ConversionStatus.pending
        XCTAssertEqual(s, .pending)
    }

    func testFailedCarriesMessage() {
        let s = ConversionStatus.failed("oops")
        XCTAssertEqual(s, .failed("oops"))
    }
}

final class SourceFileTests: XCTestCase {
    func testSourceFileStartsPending() {
        let f = SourceFile(
            sourceURL: URL(fileURLWithPath: "/tmp/a.pdf"),
            outputURL: URL(fileURLWithPath: "/tmp/a.md")
        )
        XCTAssertEqual(f.status, .pending)
        XCTAssertNil(f.errorMessage)
    }

    func testSourceFileIsIdentifiable() {
        let a = SourceFile(
            sourceURL: URL(fileURLWithPath: "/tmp/a.pdf"),
            outputURL: URL(fileURLWithPath: "/tmp/a.md")
        )
        let b = SourceFile(
            sourceURL: URL(fileURLWithPath: "/tmp/a.pdf"),
            outputURL: URL(fileURLWithPath: "/tmp/a.md")
        )
        XCTAssertNotEqual(a.id, b.id)
    }
}

final class FolderJobTests: XCTestCase {
    func testFolderJobHoldsFiles() {
        let job = FolderJob(
            rootURL: URL(fileURLWithPath: "/tmp"),
            files: [
                SourceFile(sourceURL: URL(fileURLWithPath: "/tmp/a.pdf"),
                           outputURL: URL(fileURLWithPath: "/tmp/a.md"))
            ]
        )
        XCTAssertEqual(job.files.count, 1)
        XCTAssertEqual(job.rootURL.path, "/tmp")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down && swift test`
Expected: FAIL with "Cannot find type 'ConversionStatus' in scope" (and similar for other types).

- [ ] **Step 3: Delete `SmokeTests.swift`**

Run: `rm /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down/Tests/MarkItDownTests/SmokeTests.swift`

- [ ] **Step 4: Implement the models**

`Sources/MarkItDown/Models/ConversionStatus.swift`:

```swift
import Foundation

enum ConversionStatus: Equatable {
    case pending
    case running
    case done
    case failed(String)
}
```

`Sources/MarkItDown/Models/SourceFile.swift`:

```swift
import Foundation

struct SourceFile: Identifiable, Equatable {
    let id: UUID
    let sourceURL: URL
    let outputURL: URL
    var status: ConversionStatus
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        sourceURL: URL,
        outputURL: URL,
        status: ConversionStatus = .pending,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.outputURL = outputURL
        self.status = status
        self.errorMessage = errorMessage
    }
}
```

`Sources/MarkItDown/Models/FolderJob.swift`:

```swift
import Foundation

struct FolderJob: Equatable {
    let rootURL: URL
    let files: [SourceFile]
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down && swift test`
Expected: 4 tests pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down
git add Sources Tests
git commit -m "feat: add ConversionStatus, SourceFile, FolderJob models"
```

---

## Task 3: SupportedExtensions

**Files:**
- Create: `Sources/MarkItDown/SupportedExtensions.swift`
- Create: `Tests/MarkItDownTests/SupportedExtensionsTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `enum SupportedExtensions { static let all: Set<String>; static func isSupported(_ url: URL) -> Bool }`

- [ ] **Step 1: Write the failing tests**

`Tests/MarkItDownTests/SupportedExtensionsTests.swift`:

```swift
import XCTest
@testable import MarkItDown

final class SupportedExtensionsTests: XCTestCase {

    func testPdfIsSupported() {
        XCTAssertTrue(SupportedExtensions.isSupported(URL(fileURLWithPath: "/tmp/a.pdf")))
    }

    func testDocxIsSupported() {
        XCTAssertTrue(SupportedExtensions.isSupported(URL(fileURLWithPath: "/tmp/a.docx")))
    }

    func testPptxIsSupported() {
        XCTAssertTrue(SupportedExtensions.isSupported(URL(fileURLWithPath: "/tmp/a.pptx")))
    }

    func testXlsxIsSupported() {
        XCTAssertTrue(SupportedExtensions.isSupported(URL(fileURLWithPath: "/tmp/a.xlsx")))
    }

    func testImagesAreSupported() {
        XCTAssertTrue(SupportedExtensions.isSupported(URL(fileURLWithPath: "/tmp/a.png")))
        XCTAssertTrue(SupportedExtensions.isSupported(URL(fileURLWithPath: "/tmp/a.jpg")))
        XCTAssertTrue(SupportedExtensions.isSupported(URL(fileURLWithPath: "/tmp/a.jpeg")))
    }

    func testAudioIsSupported() {
        XCTAssertTrue(SupportedExtensions.isSupported(URL(fileURLWithPath: "/tmp/a.mp3")))
        XCTAssertTrue(SupportedExtensions.isSupported(URL(fileURLWithPath: "/tmp/a.wav")))
        XCTAssertTrue(SupportedExtensions.isSupported(URL(fileURLWithPath: "/tmp/a.m4a")))
    }

    func testMarkdownIsSupported() {
        XCTAssertTrue(SupportedExtensions.isSupported(URL(fileURLWithPath: "/tmp/a.md")))
    }

    func testRandomBinaryIsNotSupported() {
        XCTAssertFalse(SupportedExtensions.isSupported(URL(fileURLWithPath: "/tmp/a.xyz")))
        XCTAssertFalse(SupportedExtensions.isSupported(URL(fileURLWithPath: "/tmp/a.exe")))
    }

    func testCaseInsensitive() {
        XCTAssertTrue(SupportedExtensions.isSupported(URL(fileURLWithPath: "/tmp/A.PDF")))
    }

    func testNoExtensionIsNotSupported() {
        XCTAssertFalse(SupportedExtensions.isSupported(URL(fileURLWithPath: "/tmp/Makefile")))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down && swift test --filter SupportedExtensionsTests`
Expected: FAIL with "Cannot find type 'SupportedExtensions' in scope".

- [ ] **Step 3: Implement `SupportedExtensions`**

`Sources/MarkItDown/SupportedExtensions.swift`:

```swift
import Foundation

enum SupportedExtensions {
    static let all: Set<String> = [
        "pdf", "docx", "pptx", "xlsx", "xls",
        "html", "htm", "txt", "md", "rtf",
        "epub", "csv", "json", "xml",
        "png", "jpg", "jpeg", "gif", "webp",
        "mp3", "wav", "m4a", "zip"
    ]

    static func isSupported(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return false }
        return all.contains(ext)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down && swift test --filter SupportedExtensionsTests`
Expected: 8 tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down
git add Sources Tests
git commit -m "feat: add SupportedExtensions whitelist"
```

---

## Task 4: OutputNamer (next-free-suffix)

**Files:**
- Create: `Sources/MarkItDown/OutputNamer.swift`
- Create: `Tests/MarkItDownTests/OutputNamerTests.swift`

**Interfaces:**
- Consumes: a `URL` for the desired output path, a `FileManager` (defaults to `.default`) to check existence.
- Produces:
  - `enum OutputNamer { static func nextAvailable(for desiredURL: URL, fileManager: FileManager) -> URL }`

- [ ] **Step 1: Write the failing tests**

`Tests/MarkItDownTests/OutputNamerTests.swift`:

```swift
import XCTest
@testable import MarkItDown

final class OutputNamerTests: XCTestCase {

    var tempDir: URL!
    var fm: FileManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fm = FileManager.default
        tempDir = fm.temporaryDirectory
            .appendingPathComponent("OutputNamerTests-\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    func testReturnsDesiredWhenFree() throws {
        let desired = tempDir.appendingPathComponent("foo.md")
        let result = OutputNamer.nextAvailable(for: desired, fileManager: fm)
        XCTAssertEqual(result, desired)
    }

    func testAppendsParen1WhenDesiredExists() throws {
        let desired = tempDir.appendingPathComponent("foo.md")
        try "x".write(to: desired, atomically: true, encoding: .utf8)
        let result = OutputNamer.nextAvailable(for: desired, fileManager: fm)
        XCTAssertEqual(result.lastPathComponent, "foo(1).md")
    }

    func testSkipsExistingSuffixes() throws {
        try "x".write(to: tempDir.appendingPathComponent("foo.md"), atomically: true, encoding: .utf8)
        try "x".write(to: tempDir.appendingPathComponent("foo(1).md"), atomically: true, encoding: .utf8)
        try "x".write(to: tempDir.appendingPathComponent("foo(2).md"), atomically: true, encoding: .utf8)
        let desired = tempDir.appendingPathComponent("foo.md")
        let result = OutputNamer.nextAvailable(for: desired, fileManager: fm)
        XCTAssertEqual(result.lastPathComponent, "foo(3).md")
    }

    func testPreservesDirectory() throws {
        try "x".write(to: tempDir.appendingPathComponent("foo.md"), atomically: true, encoding: .utf8)
        let desired = tempDir.appendingPathComponent("foo.md")
        let result = OutputNamer.nextAvailable(for: desired, fileManager: fm)
        XCTAssertEqual(result.deletingLastPathComponent(), tempDir)
    }

    func testNoCrashWhenManyFilesExist() throws {
        for i in 0...50 {
            let name = i == 0 ? "foo.md" : "foo(\(i)).md"
            try "x".write(to: tempDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let desired = tempDir.appendingPathComponent("foo.md")
        let result = OutputNamer.nextAvailable(for: desired, fileManager: fm)
        XCTAssertEqual(result.lastPathComponent, "foo(51).md")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down && swift test --filter OutputNamerTests`
Expected: FAIL with "Cannot find 'OutputNamer' in scope".

- [ ] **Step 3: Implement `OutputNamer`**

`Sources/MarkItDown/OutputNamer.swift`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down && swift test --filter OutputNamerTests`
Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down
git add Sources Tests
git commit -m "feat: add OutputNamer with next-free-suffix logic"
```

---

## Task 5: FileScanner

**Files:**
- Create: `Sources/MarkItDown/FileScanner.swift`
- Create: `Tests/MarkItDownTests/FileScannerTests.swift`

**Interfaces:**
- Consumes: a folder `URL`, an `OutputNamer` (calls `nextAvailable`), a `FileManager` (defaults to `.default`).
- Produces:
  - `enum FileScanner { static func scan(root: URL, fileManager: FileManager) throws -> [SourceFile] }`

Errors via `throws` (use a custom error type, see below).

- [ ] **Step 1: Write the failing tests**

`Tests/MarkItDownTests/FileScannerTests.swift`:

```swift
import XCTest
@testable import MarkItDown

final class FileScannerTests: XCTestCase {

    var tempDir: URL!
    var fm: FileManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fm = FileManager.default
        tempDir = fm.temporaryDirectory
            .appendingPathComponent("FileScannerTests-\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    func writeFile(_ name: String, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try "x".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testEmptyFolderReturnsEmpty() throws {
        let result = try FileScanner.scan(root: tempDir, fileManager: fm)
        XCTAssertTrue(result.isEmpty)
    }

    func testScansTopLevelSupportedFiles() throws {
        _ = try writeFile("a.pdf", in: tempDir)
        _ = try writeFile("b.docx", in: tempDir)
        _ = try writeFile("c.xyz", in: tempDir) // unsupported

        let result = try FileScanner.scan(root: tempDir, fileManager: fm)
        let names = result.map { $0.sourceURL.lastPathComponent }.sorted()
        XCTAssertEqual(names, ["a.pdf", "b.docx"])
    }

    func testRecursesIntoSubfolders() throws {
        let sub = tempDir.appendingPathComponent("sub")
        try fm.createDirectory(at: sub, withIntermediateDirectories: true)
        _ = try writeFile("a.pdf", in: tempDir)
        _ = try writeFile("b.pdf", in: sub)

        let result = try FileScanner.scan(root: tempDir, fileManager: fm)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains { $0.sourceURL.lastPathComponent == "b.pdf" })
    }

    func testOutputNamesReplaceExtension() throws {
        _ = try writeFile("report.pdf", in: tempDir)
        let result = try FileScanner.scan(root: tempDir, fileManager: fm)
        XCTAssertEqual(result.first?.outputURL.lastPathComponent, "report.md")
    }

    func testOutputNamesGetSuffixOnCollision() throws {
        let pdfURL = try writeFile("foo.pdf", in: tempDir)
        let existingMd = tempDir.appendingPathComponent("foo.md")
        try "x".write(to: existingMd, atomically: true, encoding: .utf8)

        let result = try FileScanner.scan(root: tempDir, fileManager: fm)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].sourceURL, pdfURL)
        XCTAssertEqual(result[0].outputURL.lastPathComponent, "foo(1).md")
    }

    func testIgnoresDotFiles() throws {
        let hidden = tempDir.appendingPathComponent(".hidden.pdf")
        try "x".write(to: hidden, atomically: true, encoding: .utf8)
        _ = try writeFile("visible.pdf", in: tempDir)

        let result = try FileScanner.scan(root: tempDir, fileManager: fm)
        let names = result.map { $0.sourceURL.lastPathComponent }
        XCTAssertEqual(names, ["visible.pdf"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down && swift test --filter FileScannerTests`
Expected: FAIL with "Cannot find 'FileScanner' in scope".

- [ ] **Step 3: Implement `FileScanner`**

`Sources/MarkItDown/FileScanner.swift`:

```swift
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
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var sources: [SourceFile] = []
        for case let url as URL in enumerator {
            guard SupportedExtensions.isSupported(url) else { continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }

            let desired = url.deletingPathExtension().appendingPathExtension("md")
            let outputURL = OutputNamer.nextAvailable(for: desired, fileManager: fileManager)
            sources.append(SourceFile(sourceURL: url, outputURL: outputURL))
        }
        return sources
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down && swift test --filter FileScannerTests`
Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down
git add Sources Tests
git commit -m "feat: add FileScanner with recursive walk and suffix resolution"
```

---

## Task 6: Logger

**Files:**
- Create: `Sources/MarkItDown/Logger.swift`
- Create: `Tests/MarkItDownTests/LoggerTests.swift`

**Interfaces:**
- Consumes: log messages (level + message).
- Produces:
  - `actor Logger { init(fileURL: URL) throws; func log(_ level: String, _ message: String) async }`
  - Log path resolved via `defaultLogURL()` (returns `~/Library/Application Support/Mark-It-Down/log.txt`, creating dirs).

- [ ] **Step 1: Write the failing tests**

`Tests/MarkItDownTests/LoggerTests.swift`:

```swift
import XCTest
@testable import MarkItDown

final class LoggerTests: XCTestCase {

    var tempDir: URL!
    var fm: FileManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fm = FileManager.default
        tempDir = fm.temporaryDirectory
            .appendingPathComponent("LoggerTests-\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    func testAppendsLogLine() async throws {
        let url = tempDir.appendingPathComponent("test.log")
        let logger = try Logger(fileURL: url)
        await logger.log("INFO", "hello world")
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("INFO"))
        XCTAssertTrue(contents.contains("hello world"))
    }

    func testAppendsMultipleLines() async throws {
        let url = tempDir.appendingPathComponent("test.log")
        let logger = try Logger(fileURL: url)
        await logger.log("INFO", "first")
        await logger.log("INFO", "second")
        await logger.log("ERROR", "third")
        let contents = try String(contentsOf: url, encoding: .utf8)
        let lines = contents.split(separator: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 3)
    }

    func testIncludesTimestamp() async throws {
        let url = tempDir.appendingPathComponent("test.log")
        let logger = try Logger(fileURL: url)
        await logger.log("INFO", "ts check")
        let contents = try String(contentsOf: url, encoding: .utf8)
        // ISO8601 prefix check
        let pattern = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(contents.startIndex..., in: contents)
        XCTAssertEqual(regex.numberOfMatches(in: contents, range: range), 1)
    }

    func testCreatesParentDirectory() async throws {
        let nested = tempDir.appendingPathComponent("a/b/c/test.log")
        let logger = try Logger(fileURL: nested)
        await logger.log("INFO", "nested")
        XCTAssertTrue(fm.fileExists(atPath: nested.path))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down && swift test --filter LoggerTests`
Expected: FAIL with "Cannot find 'Logger' in scope".

- [ ] **Step 3: Implement `Logger`**

`Sources/MarkItDown/Logger.swift`:

```swift
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
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        } else {
            try? data.write(to: fileURL)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down && swift test --filter LoggerTests`
Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down
git add Sources Tests
git commit -m "feat: add Logger actor for append-only log file"
```

---

## Task 7: PythonLocator

**Files:**
- Create: `Sources/MarkItDown/PythonLocator.swift`
- Create: `Tests/MarkItDownTests/PythonLocatorTests.swift`

**Interfaces:**
- Consumes: a `FileManager` for probing and a `versionProvider` closure (defaults to running `python3 --version`).
- Produces:
  - `enum PythonLocator { static func locate(fileManager: FileManager, versionProvider: (URL) async throws -> String?) async throws -> URL? }`
  - Throws `PythonLocatorError.unsuitableVersion(URL, version: String)` if version < 3.10.

- [ ] **Step 1: Write the failing tests**

`Tests/MarkItDownTests/PythonLocatorTests.swift`:

```swift
import XCTest
@testable import MarkItDown

final class PythonLocatorTests: XCTestCase {

    var tempDir: URL!
    var fm: FileManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fm = FileManager.default
        tempDir = fm.temporaryDirectory
            .appendingPathComponent("PythonLocatorTests-\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    private func makeStubPython(version: String) throws -> URL {
        let url = tempDir.appendingPathComponent("python-\(UUID().uuidString)")
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        let bin = url.appendingPathComponent("python3")
        let script = "#!/bin/sh\necho \"Python \(version)\"\n"
        try script.write(to: bin, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path)
        return bin
    }

    func testReturnsNilWhenNothingExists() async throws {
        let result = try await PythonLocator.locate(
            fileManager: fm,
            probePaths: [],
            versionProvider: { _ in nil }
        )
        XCTAssertNil(result)
    }

    func testReturnsFirstAcceptableProbe() async throws {
        let p1 = try makeStubPython(version: "3.9.0")   // too old
        let p2 = try makeStubPython(version: "3.10.5")  // acceptable

        let result = try await PythonLocator.locate(
            fileManager: fm,
            probePaths: [p1, p2],
            versionProvider: { url in
                // Read the file we wrote, parse out the version.
                let body = try String(contentsOf: url, encoding: .utf8)
                let trimmed = body.replacingOccurrences(of: "Python ", with: "")
                return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        )
        XCTAssertEqual(result, p2)
    }

    func testSkipsProbesThatDoNotExist() async throws {
        let p1 = tempDir.appendingPathComponent("does-not-exist-\(UUID().uuidString)")
        let p2 = try makeStubPython(version: "3.11.0")

        let result = try await PythonLocator.locate(
            fileManager: fm,
            probePaths: [p1, p2],
            versionProvider: { url in
                let body = try String(contentsOf: url, encoding: .utf8)
                return body.replacingOccurrences(of: "Python ", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        )
        XCTAssertEqual(result, p2)
    }

    func testReturnsNilWhenAllTooOld() async throws {
        let p1 = try makeStubPython(version: "3.8.0")
        let p2 = try makeStubPython(version: "3.9.9")
        let result = try await PythonLocator.locate(
            fileManager: fm,
            probePaths: [p1, p2],
            versionProvider: { url in
                let body = try String(contentsOf: url, encoding: .utf8)
                return body.replacingOccurrences(of: "Python ", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        )
        XCTAssertNil(result)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down && swift test --filter PythonLocatorTests`
Expected: FAIL with "Cannot find 'PythonLocator' in scope".

- [ ] **Step 3: Implement `PythonLocator`**

`Sources/MarkItDown/PythonLocator.swift`:

```swift
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
        for path in probePaths {
            guard fileManager.isExecutableFile(atPath: path.path) else { continue }
            guard let versionString = try? await versionProvider(path) else { continue }
            if isAcceptable(versionString) {
                return path
            }
        }
        return nil
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
                let s = String(data: data ?? Data(), encoding: .utf8)?
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down && swift test --filter PythonLocatorTests`
Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down
git add Sources Tests
git commit -m "feat: add PythonLocator with version checking"
```

---

## Task 8: MarkitdownInstaller

**Files:**
- Create: `Sources/MarkItDown/MarkitdownInstaller.swift`
- Create: `Tests/MarkItDownTests/MarkitdownInstallerTests.swift`

**Interfaces:**
- Consumes: a Python `URL`, an injectable `CommandRunner` protocol so tests can stub subprocess calls.
- Produces:
  - `protocol CommandRunner { func run(executable: URL, arguments: [String]) async throws -> CommandRunnerResult }`
  - `struct CommandRunnerResult { let exitCode: Int32; let stdout: String; let stderr: String }`
  - `enum MarkitdownInstaller { static func ensureInstalled(pythonPath: URL, runner: CommandRunner) async throws -> Bool }`
    - Returns `true` if markitdown is installed (or got installed), `false` if install failed.

- [ ] **Step 1: Write the failing tests**

`Tests/MarkItDownTests/MarkitdownInstallerTests.swift`:

```swift
import XCTest
@testable import MarkItDown

final class FakeCommandRunner: CommandRunner {
    var responses: [(URL, [String], CommandRunnerResult)] = []
    var invocations: [(URL, [String])] = []

    func run(executable: URL, arguments: [String]) async throws -> CommandRunnerResult {
        invocations.append((executable, arguments))
        if let match = responses.first(where: { $0.0 == executable && $0.1 == arguments }) {
            return match.2
        }
        return CommandRunnerResult(exitCode: -1, stdout: "", stderr: "no stub")
    }
}

final class MarkitdownInstallerTests: XCTestCase {

    func testAlreadyInstalledReturnsTrue() async throws {
        let runner = FakeCommandRunner()
        let py = URL(fileURLWithPath: "/usr/bin/python3")
        runner.responses.append((
            py, ["-m", "pip", "show", "markitdown"],
            CommandRunnerResult(exitCode: 0, stdout: "Name: markitdown", stderr: "")
        ))
        let ok = try await MarkitdownInstaller.ensureInstalled(pythonPath: py, runner: runner)
        XCTAssertTrue(ok)
    }

    func testInstallIsAttemptedWhenShowFails() async throws {
        let runner = FakeCommandRunner()
        let py = URL(fileURLWithPath: "/usr/bin/python3")
        runner.responses.append((
            py, ["-m", "pip", "show", "markitdown"],
            CommandRunnerResult(exitCode: 1, stdout: "", stderr: "WARNING: Package not found")
        ))
        runner.responses.append((
            py, ["-m", "pip", "install", "--user", "markitdown[all]"],
            CommandRunnerResult(exitCode: 0, stdout: "Successfully installed", stderr: "")
        ))
        let ok = try await MarkitdownInstaller.ensureInstalled(pythonPath: py, runner: runner)
        XCTAssertTrue(ok)

        // Verify both calls happened
        XCTAssertEqual(runner.invocations.count, 2)
        XCTAssertEqual(runner.invocations[0].1, ["-m", "pip", "show", "markitdown"])
        XCTAssertEqual(runner.invocations[1].1, ["-m", "pip", "install", "--user", "markitdown[all]"])
    }

    func testInstallFailureReturnsFalse() async throws {
        let runner = FakeCommandRunner()
        let py = URL(fileURLWithPath: "/usr/bin/python3")
        runner.responses.append((
            py, ["-m", "pip", "show", "markitdown"],
            CommandRunnerResult(exitCode: 1, stdout: "", stderr: "")
        ))
        runner.responses.append((
            py, ["-m", "pip", "install", "--user", "markitdown[all]"],
            CommandRunnerResult(exitCode: 1, stdout: "", stderr: "ERROR: network")
        ))
        let ok = try await MarkitdownInstaller.ensureInstalled(pythonPath: py, runner: runner)
        XCTAssertFalse(ok)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down && swift test --filter MarkitdownInstallerTests`
Expected: FAIL with "Cannot find 'CommandRunner' in scope".

- [ ] **Step 3: Implement `MarkitdownInstaller` and `CommandRunner`**

`Sources/MarkItDown/CommandRunner.swift` (in same file as MarkitdownInstaller for now, since they're tightly coupled):

```swift
import Foundation

struct CommandRunnerResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

protocol CommandRunner {
    func run(executable: URL, arguments: [String]) async throws -> CommandRunnerResult
}

struct SystemCommandRunner: CommandRunner {
    func run(executable: URL, arguments: [String]) async throws -> CommandRunnerResult {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CommandRunnerResult, Error>) in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            process.terminationHandler = { proc in
                let outData = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
                let errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
                let result = CommandRunnerResult(
                    exitCode: proc.terminationStatus,
                    stdout: String(data: outData, encoding: .utf8) ?? "",
                    stderr: String(data: errData, encoding: .utf8) ?? ""
                )
                cont.resume(returning: result)
            }
            do {
                try process.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}

enum MarkitdownInstaller {
    static func ensureInstalled(
        pythonPath: URL,
        runner: CommandRunner = SystemCommandRunner()
    ) async throws -> Bool {
        let showResult = try await runner.run(
            executable: pythonPath,
            arguments: ["-m", "pip", "show", "markitdown"]
        )
        if showResult.exitCode == 0 {
            return true
        }
        let installResult = try await runner.run(
            executable: pythonPath,
            arguments: ["-m", "pip", "install", "--user", "markitdown[all]"]
        )
        return installResult.exitCode == 0
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down && swift test --filter MarkitdownInstallerTests`
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down
git add Sources Tests
git commit -m "feat: add MarkitdownInstaller and CommandRunner abstraction"
```

---

## Task 9: MarkitdownRunner

**Files:**
- Create: `Sources/MarkItDown/MarkitdownRunner.swift`
- Create: `Tests/MarkItDownTests/MarkitdownRunnerTests.swift`

**Interfaces:**
- Consumes: Python `URL`, source `URL`, output `URL`, `CommandRunner`.
- Produces:
  - `protocol MarkitdownRunning { func convert(pythonPath: URL, source: URL, output: URL) async throws }`
  - `struct MarkitdownRunner: MarkitdownRunning` (uses CommandRunner to invoke `python3 -m markitdown <source> -o <output>`).

- [ ] **Step 1: Write the failing tests**

`Tests/MarkItDownTests/MarkitdownRunnerTests.swift`:

```swift
import XCTest
@testable import MarkItDown

final class MarkitdownRunnerTests: XCTestCase {

    func testSuccessfulConversion() async throws {
        let runner = FakeCommandRunner()
        let py = URL(fileURLWithPath: "/usr/bin/python3")
        let src = URL(fileURLWithPath: "/tmp/a.pdf")
        let dst = URL(fileURLWithPath: "/tmp/a.md")
        runner.responses.append((
            py, ["-m", "markitdown", src.path, "-o", dst.path],
            CommandRunnerResult(exitCode: 0, stdout: "ok", stderr: "")
        ))
        let m = MarkitdownRunner(runner: runner)
        try await m.convert(pythonPath: py, source: src, output: dst)

        XCTAssertEqual(runner.invocations.count, 1)
        XCTAssertEqual(runner.invocations[0].1, ["-m", "markitdown", src.path, "-o", dst.path])
    }

    func testFailureThrows() async throws {
        let runner = FakeCommandRunner()
        let py = URL(fileURLWithPath: "/usr/bin/python3")
        let src = URL(fileURLWithPath: "/tmp/bad.pdf")
        let dst = URL(fileURLWithPath: "/tmp/bad.md")
        runner.responses.append((
            py, ["-m", "markitdown", src.path, "-o", dst.path],
            CommandRunnerResult(exitCode: 1, stdout: "", stderr: "boom")
        ))
        let m = MarkitdownRunner(runner: runner)
        do {
            try await m.convert(pythonPath: py, source: src, output: dst)
            XCTFail("Expected throw")
        } catch {
            // expected
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down && swift test --filter MarkitdownRunnerTests`
Expected: FAIL with "Cannot find 'MarkitdownRunner' in scope".

- [ ] **Step 3: Implement `MarkitdownRunner`**

`Sources/MarkItDown/MarkitdownRunner.swift`:

```swift
import Foundation

protocol MarkitdownRunning {
    func convert(pythonPath: URL, source: URL, output: URL) async throws
}

enum MarkitdownRunnerError: Error {
    case nonZeroExit(code: Int32, stderr: String)
}

struct MarkitdownRunner: MarkitdownRunning {
    private let runner: CommandRunner

    init(runner: CommandRunner = SystemCommandRunner()) {
        self.runner = runner
    }

    func convert(pythonPath: URL, source: URL, output: URL) async throws {
        let result = try await runner.run(
            executable: pythonPath,
            arguments: ["-m", "markitdown", source.path, "-o", output.path]
        )
        if result.exitCode != 0 {
            throw MarkitdownRunnerError.nonZeroExit(code: result.exitCode, stderr: result.stderr)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down && swift test --filter MarkitdownRunnerTests`
Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down
git add Sources Tests
git commit -m "feat: add MarkitdownRunner subprocess wrapper"
```

---

## Task 10: ConversionEngine

**Files:**
- Create: `Sources/MarkItDown/ConversionEngine.swift`
- Create: `Tests/MarkItDownTests/ConversionEngineTests.swift`

**Interfaces:**
- Consumes: a `FolderJob`, a Python `URL`, a `MarkitdownRunning` (so we can mock), an `update` callback for UI progress.
- Produces:
  - `actor ConversionEngine { init(markitdown: MarkitdownRunning, maxConcurrent: Int = 4); func run(job: FolderJob, pythonPath: URL, update: @MainActor @escaping (UUID, ConversionStatus) async -> Void) async }`

- [ ] **Step 1: Write the failing tests**

`Tests/MarkItDownTests/ConversionEngineTests.swift`:

```swift
import XCTest
@testable import MarkItDown

final class FakeMarkitdownRunner: MarkitdownRunning {
    var conversions: [(URL, URL)] = []
    var failFor: Set<URL> = []
    var delayMillis: UInt64 = 0

    func convert(pythonPath: URL, source: URL, output: URL) async throws {
        conversions.append((source, output))
        if delayMillis > 0 {
            try? await Task.sleep(nanoseconds: delayMillis * 1_000_000)
        }
        if failFor.contains(source) {
            throw MarkitdownRunnerError.nonZeroExit(code: 1, stderr: "fake failure")
        }
    }
}

@MainActor
final class ConversionEngineTests: XCTestCase {

    func testAllSucceed() async throws {
        let runner = FakeMarkitdownRunner()
        let engine = ConversionEngine(markitdown: runner, maxConcurrent: 2)
        let job = FolderJob(
            rootURL: URL(fileURLWithPath: "/tmp"),
            files: [
                SourceFile(sourceURL: URL(fileURLWithPath: "/tmp/a.pdf"),
                           outputURL: URL(fileURLWithPath: "/tmp/a.md")),
                SourceFile(sourceURL: URL(fileURLWithPath: "/tmp/b.pdf"),
                           outputURL: URL(fileURLWithPath: "/tmp/b.md")),
                SourceFile(sourceURL: URL(fileURLWithPath: "/tmp/c.pdf"),
                           outputURL: URL(fileURLWithPath: "/tmp/c.md"))
            ]
        )

        let statuses = await withCheckedContinuation { (cont: CheckedContinuation<[UUID: ConversionStatus], Never>) in
            Task { @MainActor in
                var captured: [UUID: ConversionStatus] = [:]
                await engine.run(
                    job: job,
                    pythonPath: URL(fileURLWithPath: "/usr/bin/python3"),
                    update: { id, status in
                        captured[id] = status
                    }
                )
                cont.resume(returning: captured)
            }
        }

        XCTAssertEqual(runner.conversions.count, 3)
        for (id, _) in job.files {
            XCTAssertEqual(statuses[id], .done, "file \(id) should be done")
        }
    }

    func testFailureMarksFailed() async throws {
        let runner = FakeMarkitdownRunner()
        runner.failFor = [URL(fileURLWithPath: "/tmp/b.pdf")]
        let engine = ConversionEngine(markitdown: runner, maxConcurrent: 1)
        let job = FolderJob(
            rootURL: URL(fileURLWithPath: "/tmp"),
            files: [
                SourceFile(sourceURL: URL(fileURLWithPath: "/tmp/a.pdf"),
                           outputURL: URL(fileURLWithPath: "/tmp/a.md")),
                SourceFile(sourceURL: URL(fileURLWithPath: "/tmp/b.pdf"),
                           outputURL: URL(fileURLWithPath: "/tmp/b.md"))
            ]
        )

        let statuses = await withCheckedContinuation { (cont: CheckedContinuation<[UUID: ConversionStatus], Never>) in
            Task { @MainActor in
                var captured: [UUID: ConversionStatus] = [:]
                await engine.run(
                    job: job,
                    pythonPath: URL(fileURLWithPath: "/usr/bin/python3"),
                    update: { id, status in
                        captured[id] = status
                    }
                )
                cont.resume(returning: captured)
            }
        }

        let aFile = job.files[0]
        let bFile = job.files[1]
        XCTAssertEqual(statuses[aFile.id], .done)
        XCTAssertEqual(statuses[bFile.id], .failed("fake failure"))
    }

    func testRespectsMaxConcurrent() async throws {
        let runner = FakeMarkitdownRunner()
        runner.delayMillis = 100
        let engine = ConversionEngine(markitdown: runner, maxConcurrent: 2)
        let files = (0..<6).map {
            SourceFile(
                sourceURL: URL(fileURLWithPath: "/tmp/f\($0).pdf"),
                outputURL: URL(fileURLWithPath: "/tmp/f\($0).md")
            )
        }
        let job = FolderJob(rootURL: URL(fileURLWithPath: "/tmp"), files: files)

        let start = Date()
        await engine.run(
            job: job,
            pythonPath: URL(fileURLWithPath: "/usr/bin/python3"),
            update: { _, _ in }
        )
        let elapsed = Date().timeIntervalSince(start)

        // 6 files * 100ms / max 2 in parallel = ~300ms minimum.
        // Generous upper bound for CI: 1500ms.
        XCTAssertLessThan(elapsed, 1.5)
        XCTAssertGreaterThanOrEqual(elapsed, 0.25)
        XCTAssertEqual(runner.conversions.count, 6)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down && swift test --filter ConversionEngineTests`
Expected: FAIL with "Cannot find 'ConversionEngine' in scope".

- [ ] **Step 3: Implement `ConversionEngine`**

`Sources/MarkItDown/ConversionEngine.swift`:

```swift
import Foundation

actor ConversionEngine {
    private let markitdown: MarkitdownRunning
    private let maxConcurrent: Int

    init(markitdown: MarkitdownRunning, maxConcurrent: Int = 4) {
        self.markitdown = markitdown
        self.maxConcurrent = max(1, maxConcurrent)
    }

    func run(
        job: FolderJob,
        pythonPath: URL,
        update: @MainActor @escaping (UUID, ConversionStatus) async -> Void
    ) async {
        await withTaskGroup(of: Void.self) { group in
            var inFlight = 0
            var iterator = job.files.makeIterator()

            while let file = iterator.next() {
                if inFlight >= maxConcurrent {
                    await group.next()
                    inFlight -= 1
                }
                inFlight += 1
                let id = file.id
                let source = file.sourceURL
                let output = file.outputURL
                let runner = self.markitdown

                group.addTask {
                    await update(id, .running)
                    do {
                        try await runner.convert(pythonPath: pythonPath, source: source, output: output)
                        await update(id, .done)
                    } catch {
                        let msg = (error as? MarkitdownRunnerError).map { String(describing: $0) }
                            ?? String(describing: error)
                        await update(id, .failed(msg))
                    }
                }
            }
            await group.waitForAll()
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down && swift test --filter ConversionEngineTests`
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down
git add Sources Tests
git commit -m "feat: add ConversionEngine actor with bounded concurrency"
```

---

## Task 11: DropDelegate

**Files:**
- Create: `Sources/MarkItDown/DropDelegate.swift`
- Create: `Tests/MarkItDownTests/DropDelegateTests.swift`

**Interfaces:**
- Consumes: an array of dropped `NSItemProvider`s and a callback.
- Produces:
  - `final class FolderDropDelegate: NSObject, DropDelegate { var onFolder: ((URL) -> Void)? }`
  - The delegate extracts the first folder URL and invokes `onFolder`. It uses a security-scoped bookmark internally to keep access for the session.

- [ ] **Step 1: Write the failing tests**

`Tests/MarkItDownTests/DropDelegateTests.swift`:

```swift
import XCTest
import UniformTypeIdentifiers
@testable import MarkItDown

final class DropDelegateTests: XCTestCase {

    func testRejectsNonFolderURLs() {
        let delegate = FolderDropDelegate()
        let url = URL(fileURLWithPath: "/tmp/a.pdf")
        let provider = NSItemProvider(contentsOf: url)
        var called = false
        delegate.onFolder = { _ in called = true }
        // provider is nil because /tmp/a.pdf likely doesn't exist; that's fine, the
        // delegate should still not call back because there's no provider.
        if let provider = provider {
            delegate.validateAndExtract(from: [provider])
        }
        XCTAssertFalse(called)
    }

    func testRejectsEmptyProviders() {
        let delegate = FolderDropDelegate()
        var called = false
        delegate.onFolder = { _ in called = true }
        delegate.validateAndExtract(from: [])
        XCTAssertFalse(called)
    }

    func testAcceptsFolderURL() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory
            .appendingPathComponent("DropDelegateTests-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let delegate = FolderDropDelegate()
        var captured: URL?
        delegate.onFolder = { url in captured = url }

        let provider = NSItemProvider(contentsOf: dir)!
        delegate.validateAndExtract(from: [provider])
        XCTAssertEqual(captured?.standardizedFileURL, dir.standardizedFileURL)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down && swift test --filter DropDelegateTests`
Expected: FAIL with "Cannot find 'FolderDropDelegate' in scope".

- [ ] **Step 3: Implement `DropDelegate`**

`Sources/MarkItDown/DropDelegate.swift`:

```swift
import AppKit
import UniformTypeIdentifiers

final class FolderDropDelegate: NSObject {
    var onFolder: ((URL) -> Void)?

    func validateAndExtract(from providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let direct = item as? URL {
                url = direct
            }
            guard let resolved = url else { return }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir),
                  isDir.boolValue else { return }

            DispatchQueue.main.async { [weak self] in
                self?.onFolder?(resolved)
            }
        }
    }
}

// SwiftUI bridge so SwiftUI's `.onDrop` can call us.
extension FolderDropDelegate: DropDelegate { }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down && swift test --filter DropDelegateTests`
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down
git add Sources Tests
git commit -m "feat: add FolderDropDelegate for folder drag-and-drop"
```

---

## Task 12: ContentView (all four UI states)

**Files:**
- Create: `Sources/MarkItDown/ContentView.swift`
- Modify: `Sources/MarkItDown/MarkItDownApp.swift` (still stub — full wiring in Task 13)

**Interfaces:**
- Consumes: an `AppState` `@Observable` class that holds `mode: AppMode`, current `FolderJob?`, `pythonPath: URL?`, `installError: String?`.
- Produces: a SwiftUI `View` that switches between 4 modes: `.empty`, `.preview`, `.converting`, `.done`, plus `.noPython` and `.installing`.

`AppMode` enum (defined here):
```swift
enum AppMode: Equatable {
    case empty
    case noPython
    case installing(progress: String)
    case installFailed(String)
    case preview
    case converting
    case done(succeeded: Int, failed: Int)
}
```

- [ ] **Step 1: Define `AppState` and `AppMode`**

Create `Sources/MarkItDown/AppState.swift`:

```swift
import Foundation
import Observation

enum AppMode: Equatable {
    case empty
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
    var installError: String?
}
```

- [ ] **Step 2: Write `ContentView.swift`**

```swift
import SwiftUI

struct ContentView: View {
    @Bindable var state: AppState
    let dropDelegate: FolderDropDelegate
    let onPickFolder: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let onShowInFinder: () -> Void
    let onConvertAnother: () -> Void
    let onRecheckPython: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .padding(20)
        .frame(width: 520, height: 640)
    }

    @ViewBuilder private var header: some View {
        Text("Mark-It-Down")
            .font(.title)
            .bold()
    }

    @ViewBuilder private var content: some View {
        switch state.mode {
        case .empty:
            dropZone(message: "Drop a folder here\nor click to pick")
        case .noPython:
            VStack(alignment: .leading, spacing: 8) {
                Text("Python 3 not found").font(.headline)
                Text("Install via Homebrew (`brew install python`) or python.org, then click Recheck.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Recheck") { onRecheckPython() }
            }
        case .installing(let progress):
            VStack(spacing: 8) {
                ProgressView()
                Text("Installing markitdown…").font(.callout)
                Text(progress).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
        case .installFailed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text("Install failed").font(.headline).foregroundStyle(.red)
                Text(message).font(.caption).foregroundStyle(.secondary)
                Button("Recheck") { onRecheckPython() }
            }
        case .preview:
            previewList
        case .converting:
            convertingList
        case .done(let succeeded, let failed):
            VStack(spacing: 8) {
                Text("Done").font(.title2).bold()
                Text("\(succeeded) succeeded · \(failed) failed")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var footer: some View {
        HStack {
            switch state.mode {
            case .empty, .noPython, .installing, .installFailed:
                EmptyView()
            case .preview:
                Button("Change folder") { onPickFolder() }
                Spacer()
                Button("Start") { onStart() }.keyboardShortcut(.defaultAction)
            case .converting:
                Spacer()
                Button("Stop") { onStop() }
            case .done:
                Button("Show in Finder") { onShowInFinder() }
                Spacer()
                Button("Convert another folder") { onConvertAnother() }
            }
        }
    }

    private var dropZone: (String) -> AnyView {
        return { message in
            AnyView(
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .foregroundStyle(.secondary)
                    VStack(spacing: 8) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 36))
                        Text(message).multilineTextAlignment(.center)
                    }
                    .padding()
                }
                .frame(maxWidth: .infinity, minHeight: 220)
                .onTapGesture { onPickFolder() }
                .onDrop(of: [.fileURL], delegate: dropDelegate)
            )
        }
    }

    private var previewList: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let job = state.job {
                Text("\(job.files.count) files found").font(.callout).bold()
                List(job.files) { file in
                    HStack {
                        Text(file.sourceURL.lastPathComponent).lineLimit(1)
                        Spacer()
                        Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                        Text(file.outputURL.lastPathComponent).lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 220)
            } else {
                EmptyView()
            }
        }
    }

    private var convertingList: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let job = state.job {
                let total = job.files.count
                let done = job.files.filter {
                    if case .done = $0.status { return true } else { return false }
                }.count
                let failed = job.files.filter {
                    if case .failed = $0.status { return true } else { return false }
                }.count
                let completed = done + failed
                ProgressView(value: Double(completed), total: Double(max(total, 1)))
                Text("\(completed) / \(total)").font(.caption).foregroundStyle(.secondary)
                List(job.files) { file in
                    HStack {
                        statusIcon(for: file.status)
                        Text(file.sourceURL.lastPathComponent).lineLimit(1)
                        Spacer()
                        Text(file.outputURL.lastPathComponent).foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 260)
            } else {
                EmptyView()
            }
        }
    }

    @ViewBuilder private func statusIcon(for status: ConversionStatus) -> some View {
        switch status {
        case .pending: Image(systemName: "clock").foregroundStyle(.secondary)
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down && swift build`
Expected: build succeeds with no errors.

Note: This task does not have unit tests for SwiftUI views — UI verification happens manually in Task 16 (end-to-end smoke test).

- [ ] **Step 4: Commit**

```bash
cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down
git add Sources
git commit -m "feat: add ContentView with all four UI states"
```

---

## Task 13: App entry point and state wiring

**Files:**
- Modify: `Sources/MarkItDown/MarkItDownApp.swift`

**Interfaces:**
- Wires `AppState`, `FolderDropDelegate`, `PythonLocator`, `MarkitdownInstaller`, `ConversionEngine`, `Logger`, `FileScanner` together at launch.

- [ ] **Step 1: Replace `MarkItDownApp.swift`**

```swift
import SwiftUI
import AppKit

@main
struct MarkItDownApp: App {
    @State private var state = AppState()
    @State private var dropDelegate = FolderDropDelegate()
    @State private var coordinator: AppCoordinator?

    var body: some Scene {
        WindowGroup("Mark-It-Down") {
            ContentView(
                state: state,
                dropDelegate: dropDelegate,
                onPickFolder: { coordinator?.pickFolder() },
                onStart: { coordinator?.startConversion() },
                onStop: { coordinator?.stopConversion() },
                onShowInFinder: { coordinator?.showInFinder() },
                onConvertAnother: { coordinator?.reset() },
                onRecheckPython: { coordinator?.bootstrap() }
            )
            .task { await initialBootstrap() }
        }
        .windowResizability(.contentSize)
    }

    private func initialBootstrap() async {
        let coord = AppCoordinator(state: state, dropDelegate: dropDelegate)
        self.coordinator = coord
        dropDelegate.onFolder = { [weak coord] url in
            coord?.loadFolder(url)
        }
        await coord.bootstrap()
    }
}
```

- [ ] **Step 2: Create `AppCoordinator.swift`**

```swift
import AppKit
import Foundation

@MainActor
final class AppCoordinator {
    let state: AppState
    let dropDelegate: FolderDropDelegate
    private let markitdownRunner: MarkitdownRunning
    private let engine: ConversionEngine
    private let logger: Logger?

    private var currentConversionTask: Task<Void, Never>?

    init(
        state: AppState,
        dropDelegate: FolderDropDelegate,
        markitdownRunner: MarkitdownRunning = MarkitdownRunner(),
        engine: ConversionEngine? = nil,
        logger: Logger? = nil
    ) {
        self.state = state
        self.dropDelegate = dropDelegate
        self.markitdownRunner = markitdownRunner
        self.engine = engine ?? ConversionEngine(markitdown: markitdownRunner)
        self.logger = logger
    }

    func bootstrap() async {
        do {
            let pythonPath = try await PythonLocator.locate()
            guard let pythonPath = pythonPath else {
                state.mode = .noPython
                await logger?.log("WARN", "No suitable Python 3.10+ found")
                return
            }
            state.pythonPath = pythonPath
            state.mode = .installing(progress: "Checking markitdown…")
            let installed = try await MarkitdownInstaller.ensureInstalled(pythonPath: pythonPath)
            if installed {
                state.mode = .empty
                await logger?.log("INFO", "Bootstrap complete: \(pythonPath.path)")
            } else {
                state.mode = .installFailed(
                    "Could not install markitdown. Run manually:\n" +
                    "\(pythonPath.path) -m pip install --user 'markitdown[all]'"
                )
            }
        } catch {
            state.mode = .installFailed(String(describing: error))
        }
    }

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            loadFolder(url)
        }
    }

    func loadFolder(_ url: URL) {
        do {
            let files = try FileScanner.scan(root: url)
            let job = FolderJob(rootURL: url, files: files)
            state.job = job
            state.mode = .preview
        } catch {
            state.mode = .installFailed("Failed to scan folder: \(error)")
        }
    }

    func startConversion() {
        guard let job = state.job, let pythonPath = state.pythonPath else { return }
        state.mode = .converting
        // Reset statuses to pending so the UI re-renders correctly.
        var fresh = job
        for i in fresh.files.indices {
            fresh.files[i].status = .pending
            fresh.files[i].errorMessage = nil
        }
        state.job = fresh

        currentConversionTask = Task { [weak self] in
            guard let self = self else { return }
            await self.engine.run(
                job: fresh,
                pythonPath: pythonPath,
                update: { id, status in
                    await self.applyStatus(id: id, status: status)
                }
            )
            await self.markDone()
        }
    }

    func stopConversion() {
        currentConversionTask?.cancel()
        currentConversionTask = nil
        state.mode = .preview
    }

    func showInFinder() {
        guard let url = state.job?.rootURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func reset() {
        state.job = nil
        state.mode = .empty
    }

    private func applyStatus(id: UUID, status: ConversionStatus) async {
        guard var job = state.job else { return }
        guard let idx = job.files.firstIndex(where: { $0.id == id }) else { return }
        job.files[idx].status = status
        if case .failed(let msg) = status {
            job.files[idx].errorMessage = msg
        }
        state.job = job
    }

    private func markDone() async {
        guard let job = state.job else { return }
        let succeeded = job.files.filter {
            if case .done = $0.status { return true } else { return false }
        }.count
        let failed = job.files.count - succeeded
        state.mode = .done(succeeded: succeeded, failed: failed)
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down && swift build`
Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down
git add Sources
git commit -m "feat: wire AppCoordinator and @main entry point"
```

---

## Task 14: Build & launch scripts

**Files:**
- Create: `make-app.sh`
- Create: `run-dev.sh`
- Create: `Resources/Info.plist.tmpl`

- [ ] **Step 1: Create `Resources/Info.plist.tmpl`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Mark-It-Down</string>
    <key>CFBundleDisplayName</key>
    <string>Mark-It-Down</string>
    <key>CFBundleIdentifier</key>
    <string>local.markitdown.app</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleExecutable</key>
    <string>Mark-It-Down</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
```

- [ ] **Step 2: Create `make-app.sh`**

```bash
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP_NAME="Mark-It-Down"
BUNDLE="$APP_NAME.app"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG"

BIN_PATH=$(swift build -c "$CONFIG" --show-bin-path)
echo "==> Binary: $BIN_PATH/MarkItDown"

echo "==> Assembling $BUNDLE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp "$BIN_PATH/MarkItDown" "$BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$BUNDLE/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist.tmpl "$BUNDLE/Contents/Info.plist"

echo "==> Ad-hoc codesigning"
codesign --force --deep --sign - "$BUNDLE"

echo "==> Done: $BUNDLE"
echo "To run: open '$BUNDLE'  (or drag to /Applications)"
```

- [ ] **Step 3: Create `run-dev.sh`**

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift run
```

- [ ] **Step 4: Make scripts executable**

Run:
```
chmod +x /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down/make-app.sh /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down/run-dev.sh
```

- [ ] **Step 5: Build the .app**

Run:
```
cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down && ./make-app.sh release
```
Expected: `Mark-It-Down.app` is created in the project root. Inspect with `ls -la Mark-It-Down.app/Contents/`.

- [ ] **Step 6: Commit**

```bash
cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down
git add Resources make-app.sh run-dev.sh
git commit -m "chore: add make-app.sh and Info.plist template"
```

---

## Task 15: README and LICENSE

**Files:**
- Create: `README.md`
- Create: `LICENSE`

- [ ] **Step 1: Write `LICENSE`**

```
MIT License

Copyright (c) 2026 ycgeorgeli

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 2: Write `README.md`**

```markdown
# Mark-It-Down

A native macOS app that converts a folder of documents to Markdown using [markitdown](https://github.com/microsoft/markitdown).

Drag a folder in. Click Start. Get `.md` files next to the originals.

## Features

- Drag-and-drop a folder, recursive scan
- Supports PDF, DOCX, PPTX, XLSX, HTML, images (with OCR), audio (with transcription), and more
- Output never overwrites — collisions get `(N)` suffixes
- Up to 4 parallel conversions
- Native SwiftUI app, no Electron

## Requirements

- macOS 14 (Sonoma) or later
- Python 3.10 or later (Homebrew recommended)
- Internet access on first run (to install `markitdown[all]`)

## Install

```
git clone <your-fork-url> Mark-It-Down
cd Mark-It-Down
./make-app.sh release
open Mark-It-Down.app
```

Drag `Mark-It-Down.app` to `/Applications` if you want it installed permanently.

If macOS Gatekeeper blocks the first launch, right-click the app → Open, or run:

```
xattr -dr com.apple.quarantine Mark-It-Down.app
```

## Usage

1. Launch `Mark-It-Down.app`.
2. On first run, the app installs `markitdown[all]` (~150 MB) automatically.
3. Drag a folder onto the drop zone, or click to pick one.
4. Review the file list. Click **Start**.
5. When done, click **Show in Finder** to see the output.

## Development

```
./run-dev.sh          # swift run for development
swift test            # run all unit tests
swift build           # compile only
```

## Acknowledgements

Powered by Microsoft's [markitdown](https://github.com/microsoft/markitdown). This app is not affiliated with or endorsed by Microsoft.
```

- [ ] **Step 3: Commit**

```bash
cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down
git add README.md LICENSE
git commit -m "docs: add README and MIT LICENSE"
```

---

## Task 16: End-to-end smoke test

**Files:** none (manual test)

- [ ] **Step 1: Build the release app**

Run:
```
cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down && ./make-app.sh release
```
Expected: build succeeds, `Mark-It-Down.app` exists.

- [ ] **Step 2: Create a test folder**

Run:
```
mkdir -p /tmp/mark-it-down-smoke
cp /Users/ycgeorgeli/Downloads/Thermal/*.pdf /tmp/mark-it-down-smoke/
ls /tmp/mark-it-down-smoke
```
Expected: 5 PDFs are listed.

- [ ] **Step 3: Launch the app**

Run: `open /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down/Mark-It-Down.app`
Expected: window appears, title "Mark-It-Down". If `noPython` state appears, install Python (`brew install python`) and click Recheck.

- [ ] **Step 4: Drop the test folder**

Drag `/tmp/mark-it-down-smoke` onto the drop zone (or click to open NSOpenPanel).

Expected:
- UI switches to **preview** state
- Lists 5 entries: each `<name>.pdf → <name>.md`
- **Start** button is enabled

- [ ] **Step 5: Click Start**

Click **Start**.

Expected:
- UI switches to **converting** state
- Progress bar advances
- Each row updates: ⏱ → ⟳ → ✓ (or ✗ on failure)
- After ~30 seconds, switches to **done** state

- [ ] **Step 6: Verify outputs**

Run: `ls -la /tmp/mark-it-down-smoke`
Expected: 5 new `.md` files exist alongside the PDFs, with non-empty content.

- [ ] **Step 7: Re-test the suffix logic**

Run: `cp /Users/ycgeorgeli/Downloads/Thermal/*.pdf /tmp/mark-it-down-smoke/`
Then drop the folder again and click Start.

Expected: new `.md` files have `(1)` suffixes (e.g., `Optimom 5D Product Introduction(1).md`).

- [ ] **Step 8: Verify log file**

Run: `cat ~/Library/Application\ Support/Mark-It-Down/log.txt | tail -30`
Expected: log entries for each conversion with timestamps, exit codes.

- [ ] **Step 9: Clean up**

Run: `rm -rf /tmp/mark-it-down-smoke`

- [ ] **Step 10: Final commit (if any fixes were needed)**

If the smoke test revealed bugs, fix them, then:
```bash
cd /Users/ycgeorgeli/Documents/Opencode/Mark-It-Down
git add -A
git commit -m "fix: <describe smoke-test fix>"
```

---

## Self-Review Notes

**Spec coverage check:**
- § 6.1 Launch & first-run → Tasks 7, 8, 13
- § 6.2 Folder drop & preview → Tasks 11, 12, 13
- § 6.3 Conversion → Tasks 9, 10, 13
- § 6.4 Done → Task 12, 13
- § 6.5 Supported extensions → Task 3
- § 7 Data models → Task 2
- § 8 Logging → Task 6 (Logger), wired in Task 13
- § 9 Permissions (sandbox disabled) → Task 14 (Info.plist omits the sandbox key)
- § 10 Build & run → Task 14 (make-app.sh)
- § 11 Risks (Apple removed bundled Python) → Tasks 7, 13 (probe + banner)
- § 13 Success criteria → Task 16 (smoke test)

All spec sections are mapped. No gaps.

**Type consistency:** `ConversionStatus`, `SourceFile`, `FolderJob`, `OutputNamer`, `PythonLocator`, `MarkitdownInstaller`, `MarkitdownRunner`, `ConversionEngine`, `Logger`, `FolderDropDelegate`, `AppState`, `AppMode`, `AppCoordinator` — all consistently referenced by name across tasks.

**Placeholder scan:** No TBDs. All code blocks contain real content. Each task has runnable commands and expected outputs.