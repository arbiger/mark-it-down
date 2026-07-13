# Mark-It-Down macOS Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the macOS app collision-safe, cancellation-aware, responsive under subprocess and filesystem load, and covered by repeatable SwiftPM tests without redesigning its simple UI.

**Architecture:** Preserve the SwiftUI/AppKit surface and current value-model structure. Strengthen the existing focused core types and add only the seams needed for deterministic tests.

**Tech Stack:** Swift 5.9 package manifest, Swift 6.3 toolchain, SwiftUI, AppKit, Foundation `Process`, structured concurrency, a native framework-free test runner, macOS 14+.

> **Execution note:** The installed Command Line Tools could compile but not discover Swift Testing tests and did not expose XCTest. Execution therefore replaced the planned XCTest target with a framework-free `run-tests.sh` harness that compiles production sources and tests into one native executable. All behavioral test steps use that command.

## Global Constraints

- macOS 14+ only; add no cross-platform abstractions or third-party dependencies.
- Preserve the drag-drop-start workflow, current window, typography, spacing, and primary actions.
- Keep `microsoft/markitdown` and the default limit of four conversions.
- Never intentionally overwrite existing files.
- Follow red-green-refactor for every behavior change.

## File Map

- `Package.swift`: add the test target.
- `Sources/MarkItDown/OutputNamer.swift`: reserve paths against disk and the active batch.
- `Sources/MarkItDown/FileScanner.swift`: deterministic, metadata-efficient scanning.
- `Sources/MarkItDown/MarkitdownInstaller.swift`: safe process I/O, cancellation, and resilient probing.
- `Sources/MarkItDown/MarkitdownRunner.swift`: useful localized conversion errors.
- `Sources/MarkItDown/ConversionEngine.swift`: bounded scheduling and cancellation.
- `Sources/MarkItDown/Models/ConversionStatus.swift`: cancelled status.
- `Sources/MarkItDown/Models/FolderJob.swift`: one-pass progress counts.
- `Sources/MarkItDown/AppCoordinator.swift`: background scanning and stale-callback protection.
- `Sources/MarkItDown/AppState.swift`: explicit scanning state.
- `Sources/MarkItDown/ContentView.swift`: minimal accurate status presentation.
- `Sources/MarkItDown/DropDelegate.swift`: remove dead synchronization state.
- `Tests/MarkItDownTests/`: deterministic core tests.

---

### Task 1: Test harness and collision-safe deterministic scanning

**Files:**
- Modify: `Package.swift`
- Modify: `Sources/MarkItDown/OutputNamer.swift`
- Modify: `Sources/MarkItDown/FileScanner.swift`
- Create: `Tests/MarkItDownTests/TestSupport.swift`
- Create: `Tests/MarkItDownTests/OutputAndScannerTests.swift`

**Interfaces:**
- Consumes: `SourceFile.init(sourceURL:outputURL:)` and `SupportedExtensions.isSupported(_:)`.
- Produces: `OutputNamer.nextAvailable(for:fileManager:reserving:)` and sorted `FileScanner.scan(root:fileManager:)` results.

- [ ] **Step 1: Add the XCTest target and temporary-directory helper**

Add `.testTarget(name: "MarkItDownTests", dependencies: ["MarkItDown"])`. Create `TemporaryDirectoryTestCase`, which creates a unique directory in `setUpWithError` and removes it in `tearDownWithError`.

```swift
class TemporaryDirectoryTestCase: XCTestCase {
    var temporaryDirectory: URL!
    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }
}
```

- [ ] **Step 2: Write failing scanner tests**

Create `report.docx` and `report.pdf`; assert sorted sources and `report.md`, `report(1).md` outputs. Add an existing `report.md`; assert non-Markdown inputs receive `report(1).md`, `report(2).md`. Add hidden, unsupported, directory-package, and nested supported fixtures; assert only visible supported regular files appear.

```swift
func testScanSortsAndReservesOutputsWithinBatch() throws {
    try Data().write(to: temporaryDirectory.appendingPathComponent("report.pdf"))
    try Data().write(to: temporaryDirectory.appendingPathComponent("report.docx"))
    let files = try FileScanner.scan(root: temporaryDirectory)
    XCTAssertEqual(files.map(\.sourceURL.lastPathComponent), ["report.docx", "report.pdf"])
    XCTAssertEqual(files.map(\.outputURL.lastPathComponent), ["report.md", "report(1).md"])
}
```

- [ ] **Step 3: Verify RED**

Run: `swift test --filter OutputAndScannerTests`

Expected: FAIL because both inputs currently receive `report.md` and enumeration order is not guaranteed.

- [ ] **Step 4: Implement reservation-aware naming and sorted scanning**

Use one `Set<URL>` for a whole scan. Standardize every candidate, reject both existing and reserved paths, insert the selected path, and continue the existing `(N)` sequence. Collect supported regular URLs using cached `.isRegularFileKey`, `.skipsHiddenFiles`, and `.skipsPackageDescendants`; sort by `path` before assigning outputs.

```swift
static func nextAvailable(
    for desiredURL: URL,
    fileManager: FileManager = .default,
    reserving reserved: inout Set<URL>
) -> URL {
    let directory = desiredURL.deletingLastPathComponent()
    let stem = desiredURL.deletingPathExtension().lastPathComponent
    let ext = desiredURL.pathExtension
    var suffix = 0
    while true {
        let name = suffix == 0 ? desiredURL.lastPathComponent
            : (ext.isEmpty ? "\(stem)(\(suffix))" : "\(stem)(\(suffix)).\(ext)")
        let candidate = directory.appendingPathComponent(name).standardizedFileURL
        if !fileManager.fileExists(atPath: candidate.path), !reserved.contains(candidate) {
            reserved.insert(candidate)
            return candidate
        }
        suffix += 1
    }
}
```

- [ ] **Step 5: Verify GREEN and commit**

Run: `swift test --filter OutputAndScannerTests && swift test && swift build -c debug`

```bash
git add Package.swift Sources/MarkItDown/OutputNamer.swift Sources/MarkItDown/FileScanner.swift Tests/MarkItDownTests
git commit -m "fix: reserve unique batch output paths"
```

---

### Task 2: Deadlock-free cancellation-aware subprocesses

**Files:**
- Modify: `Sources/MarkItDown/MarkitdownInstaller.swift`
- Create: `Tests/MarkItDownTests/SystemCommandRunnerTests.swift`

**Interfaces:**
- Consumes and preserves: `CommandRunner.run(executable:arguments:)`.
- Produces: concurrent stdout/stderr draining and `CancellationError` propagation.

- [ ] **Step 1: Write real process tests**

Use `/bin/sh` to assert separate stream capture plus exit code 7. Generate exactly 1,048,576 bytes on both streams. Start `sleep 30`, cancel immediately, and assert `CancellationError`.

```swift
func testCapturesBothStreamsAndExitCode() async throws {
    let result = try await SystemCommandRunner().run(
        executable: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", "printf out; printf err >&2; exit 7"]
    )
    XCTAssertEqual(result.exitCode, 7)
    XCTAssertEqual(result.stdout, "out")
    XCTAssertEqual(result.stderr, "err")
}
```

- [ ] **Step 2: Verify RED**

Run with an external guard: `perl -e 'alarm 10; exec @ARGV' swift test --filter SystemCommandRunnerTests`

Expected: timeout on large output or cancellation fails because the current handler only reads pipes after termination.

- [ ] **Step 3: Implement safe draining and cancellation**

After `process.run()`, immediately start detached `readToEnd` tasks for both pipes and a detached `waitUntilExit` task. Wrap the wait in `withTaskCancellationHandler`; terminate only if running. Await readers and call `Task.checkCancellation()` before returning.

```swift
let stdoutTask = Task.detached { (try? outPipe.fileHandleForReading.readToEnd()) ?? Data() }
let stderrTask = Task.detached { (try? errPipe.fileHandleForReading.readToEnd()) ?? Data() }
let status = await withTaskCancellationHandler {
    await Task.detached {
        process.waitUntilExit()
        return process.terminationStatus
    }.value
} onCancel: {
    if process.isRunning { process.terminate() }
}
let outData = await stdoutTask.value
let errData = await stderrTask.value
try Task.checkCancellation()
return CommandRunnerResult(
    exitCode: status,
    stdout: String(decoding: outData, as: UTF8.self),
    stderr: String(decoding: errData, as: UTF8.self)
)
```

- [ ] **Step 4: Verify GREEN and commit**

Run: `swift test --filter SystemCommandRunnerTests && swift test && swift build -c debug`

```bash
git add Sources/MarkItDown/MarkitdownInstaller.swift Tests/MarkItDownTests/SystemCommandRunnerTests.swift
git commit -m "fix: make subprocess execution cancellation safe"
```

---

### Task 3: Bounded conversion lifecycle

**Files:**
- Modify: `Sources/MarkItDown/Models/ConversionStatus.swift`
- Modify: `Sources/MarkItDown/ConversionEngine.swift`
- Modify: `Sources/MarkItDown/MarkitdownRunner.swift`
- Create: `Tests/MarkItDownTests/ConversionEngineTests.swift`

**Interfaces:**
- Consumes: `MarkitdownRunning.convert(pythonPath:source:output:)`.
- Produces: `ConversionStatus.cancelled`; no new scheduling after cancellation; localized runner errors.

- [ ] **Step 1: Write controlled-runner tests**

Create an actor runner that records started names, current calls, peak calls, and optionally fails a named source after `Task.sleep`. For six inputs at limit two, assert peak is two. Assert one failure does not stop other work. Cancel a longer run and assert fewer than all files start and interrupted work reports `.cancelled`, never `.failed`.

```swift
actor ControlledMarkitdownRunner: MarkitdownRunning {
    private(set) var started: [String] = []
    private(set) var peak = 0
    private var active = 0
    func convert(pythonPath: URL, source: URL, output: URL) async throws {
        started.append(source.lastPathComponent)
        active += 1
        peak = max(peak, active)
        defer { active -= 1 }
        try await Task.sleep(for: .milliseconds(100))
    }
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter ConversionEngineTests`

Expected: compilation fails because `.cancelled` is absent; after introducing that expected symbol to the test branch, current cancellation behavior still fails.

- [ ] **Step 3: Implement cancellation-aware scheduling**

Add `.cancelled`. Check cancellation before every wait and add. On cancellation call `group.cancelAll()` and stop consuming the iterator. In children, catch `CancellationError` before the general catch and emit `.cancelled`; prefer `localizedDescription` for other failures.

```swift
do {
    try Task.checkCancellation()
    try await runner.convert(pythonPath: pythonPath, source: source, output: output)
    try Task.checkCancellation()
    await update(id, .done)
} catch is CancellationError {
    await update(id, .cancelled)
} catch {
    await update(id, .failed(error.localizedDescription))
}
```

- [ ] **Step 4: Localize runner failures**

Conform `MarkitdownRunnerError` to `LocalizedError`; trim stderr and return it when non-empty, otherwise return `markitdown exited with code N`.

- [ ] **Step 5: Verify GREEN and commit**

Run: `swift test --filter ConversionEngineTests && swift test && swift build -c debug`

```bash
git add Sources/MarkItDown/Models/ConversionStatus.swift Sources/MarkItDown/ConversionEngine.swift Sources/MarkItDown/MarkitdownRunner.swift Tests/MarkItDownTests/ConversionEngineTests.swift
git commit -m "fix: stop conversion work cleanly"
```

---

### Task 4: Responsive coordinator and efficient progress

**Files:**
- Modify: `Sources/MarkItDown/Models/FolderJob.swift`
- Modify: `Sources/MarkItDown/AppState.swift`
- Modify: `Sources/MarkItDown/AppCoordinator.swift`
- Modify: `Sources/MarkItDown/ContentView.swift`
- Create: `Tests/MarkItDownTests/FolderJobTests.swift`

**Interfaces:**
- Consumes: `.cancelled`, `FileScanner.scan`, and `ConversionEngine.run`.
- Produces: `FolderJob.counts`, `.scanning`, and generation-guarded updates.

- [ ] **Step 1: Write failing one-pass count tests**

Build one `FolderJob` containing all five statuses and assert exact pending, running, succeeded, failed, cancelled, and completed counts.

```swift
struct ConversionCounts: Equatable {
    var pending = 0
    var running = 0
    var succeeded = 0
    var failed = 0
    var cancelled = 0
    var completed: Int { succeeded + failed + cancelled }
}
```

Run: `swift test --filter FolderJobTests`

Expected: compilation fails because `FolderJob.counts` is absent.

- [ ] **Step 2: Implement counts and replace repeated filters**

Iterate once through `files`, switch on each status, and increment one field. Use `counts` in `ContentView` and `markDone`.

- [ ] **Step 3: Move scans off the main actor and reject stale callbacks**

Add `scanTask` and `activeConversionID`. `loadFolder` cancels its prior scan, sets `.scanning`, performs `FileScanner.scan` in `Task.detached`, and applies only the current result. Each conversion captures a UUID; update/completion closures compare it with `activeConversionID`. Stop clears the UUID before cancelling.

```swift
let conversionID = UUID()
activeConversionID = conversionID
currentConversionTask = Task { @MainActor [weak self] in
    guard let self else { return }
    await engine.run(job: fresh, pythonPath: pythonPath) { [weak self] id, status in
        guard let self, self.activeConversionID == conversionID else { return }
        self.applyStatus(id: id, status: status)
    }
    guard self.activeConversionID == conversionID else { return }
    self.activeConversionID = nil
    self.currentConversionTask = nil
    self.markDone()
}
```

- [ ] **Step 4: Represent state without redesigning UI**

Add `.scanning` and reuse the centered progress view with `Scanning files…`. Add a cancelled status icon. Show `No supported files found` for an empty preview and disable Start. Do not change layout or styling.

- [ ] **Step 5: Verify GREEN and commit**

Run: `swift test --filter FolderJobTests && swift test && swift build -c debug`

```bash
git add Sources/MarkItDown/Models/FolderJob.swift Sources/MarkItDown/AppState.swift Sources/MarkItDown/AppCoordinator.swift Sources/MarkItDown/ContentView.swift Tests/MarkItDownTests/FolderJobTests.swift
git commit -m "perf: keep scanning and progress responsive"
```

---

### Task 5: Bootstrap resilience, cleanup, docs, and release verification

**Files:**
- Modify: `Sources/MarkItDown/MarkitdownInstaller.swift`
- Modify: `Sources/MarkItDown/DropDelegate.swift`
- Modify: `README.md`
- Create: `Tests/MarkItDownTests/BootstrapTests.swift`

**Interfaces:**
- Consumes: `CommandRunner`, `PythonLocator.isAcceptable`, existing pip argument order.
- Produces: candidate-probe failure isolation and simpler drop extraction.

- [ ] **Step 1: Write failing bootstrap tests**

Create an actor-backed queued runner. Assert correct Python version acceptance/rejection, a thrown probe for candidate one still allows candidate two to be selected, and install fallback argument arrays remain exact.

```swift
actor QueuedCommandRunner: CommandRunner {
    enum Response { case result(CommandRunnerResult), error(TestError) }
    enum TestError: Error { case failed }
    private var responses: [Response]
    init(_ responses: [Response]) { self.responses = responses }
    func run(executable: URL, arguments: [String]) async throws -> CommandRunnerResult {
        switch responses.removeFirst() {
        case .result(let value): return value
        case .error(let error): throw error
        }
    }
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter BootstrapTests`

Expected: the first thrown probe escapes instead of selecting candidate two.

- [ ] **Step 3: Isolate candidate probe failures**

Wrap each import probe in `do/catch` and continue to the next candidate. Keep the two documented pip attempts and their exact order. Surface the final trimmed stderr through the existing coordinator failure message without changing the primary UI.

- [ ] **Step 4: Remove dead drop synchronization**

Delete `group_lock` and `remaining`; `DispatchGroup.notify` already supplies completion. Keep the lock around `urls` and main-queue delivery.

- [ ] **Step 5: Update README**

Document `swift test`, the test target, batch output reservations, and Stop cancellation. Remove the obsolete claim that XCTest is unavailable.

- [ ] **Step 6: Run complete verification**

```bash
swift package clean
swift test
swift build -c debug
swift build -c release
./make-app.sh release
test -x Mark-It-Down.app/Contents/MacOS/Mark-It-Down
codesign --verify --deep --strict Mark-It-Down.app
plutil -lint Mark-It-Down.app/Contents/Info.plist
git diff --check
git status --short
```

Expected: all commands exit 0; tests, builds, bundle, signature, and plist pass; Git contains no `.build` artifacts.

- [ ] **Step 7: Review and commit**

Confirm the diff adds no UI redesign, dependency, placeholder, generated build cache, or cross-platform abstraction.

```bash
git add Sources/MarkItDown/MarkitdownInstaller.swift Sources/MarkItDown/DropDelegate.swift Tests/MarkItDownTests/BootstrapTests.swift README.md Mark-It-Down.app
git commit -m "chore: complete macOS optimization pass"
```
