# Mark-It-Down — Design Spec

**Date:** 2026-07-13
**Status:** Draft (awaiting user review)
**Target:** macOS 14+ (Sonoma) on Apple Silicon and Intel

## 1. Purpose

A native macOS app that converts an entire folder of documents into Markdown using Microsoft's [markitdown](https://github.com/microsoft/markitdown) library. The user drops a folder onto the app; the app walks it recursively, shows a preview of every supported file and its target `.md` name, then converts them in parallel when the user clicks **Start**. Output files are written next to each source. Pre-existing `.md` files are never overwritten — the app picks the next free `(N)` suffix instead.

## 2. Goals & non-goals

**Goals**
- Drag-and-drop a folder, click Start, get Markdown files alongside the originals.
- No command-line knowledge required to use it after install.
- Works on any Mac that has Python 3.10+ available; auto-installs `markitdown[all]` on first run if missing.
- Recursive: subfolders are walked; each output is written next to its source (subfolder structure preserved by default).
- Output is non-destructive — never overwrites, never prompts.

**Non-goals (v1)**
- Windows / Linux support. Deferred; will be revisited after the macOS app is stable.
- Mac App Store distribution. App Sandbox is disabled; the app is intended for personal use, installed by drag-to-Applications or `swift run`.
- Editing or previewing Markdown inside the app.
- Cloud / sync / multi-folder queueing.
- Branding alignment with Microsoft's `MarkItDown` repo. The display name is **Mark-It-Down** (hyphenated) to avoid implying an official relationship. Repo link is acknowledged in an About pane.

## 3. Project location

```
/Users/ycgeorgeli/Documents/Opencode/Mark-It-Down/
```

## 4. Tech stack

| Layer | Choice | Why |
|---|---|---|
| UI | SwiftUI (macOS 14+) | Native drag-and-drop, smallest binary, best Mac feel |
| Build | Swift Package Manager (`Package.swift` executable target) | No Xcode project file to commit; `swift build` from CLI |
| App bundling | Custom `make-app.sh` script | Wraps the SwiftPM binary into `Mark-It-Down.app` with an Info.plist and ad-hoc codesign |
| Conversion engine | `Process` shell-out to `markitdown` | Don't reinvent; the existing CLI handles every format and edge case |
| Python management | System Python 3.10+ (Homebrew preferred), auto-install `markitdown[all]` to `--user` on first run | Keeps app small; works offline once installed |

## 5. Project structure

```
Mark-It-Down/
├── Package.swift                          # SwiftPM manifest, macOS .executableTarget
├── Sources/MarkItDown/
│   ├── MarkItDownApp.swift                # @main, WindowGroup
│   ├── ContentView.swift                  # state machine: empty / preview / converting / done
│   ├── DropDelegate.swift                 # NSItemProvider → folder URL
│   ├── ConversionEngine.swift             # actor: parallel orchestration (max 4)
│   ├── MarkitdownRunner.swift             # Process wrapper for one file
│   ├── FileScanner.swift                  # recursive walker
│   ├── OutputNamer.swift                  # next-free-suffix logic
│   ├── SupportedExtensions.swift          # extension whitelist
│   ├── PythonLocator.swift                # locate Python 3.10+
│   ├── MarkitdownInstaller.swift          # first-run pip install
│   ├── Logger.swift                       # append-only log file
│   └── Models/
│       ├── SourceFile.swift               # source path + computed output path + status
│       ├── ConversionStatus.swift         # enum: pending, running, done, failed
│       └── FolderJob.swift                # root URL + list of SourceFile
├── make-app.sh                            # build → wrap → codesign
├── run-dev.sh                             # swift run for development
├── .gitignore
├── LICENSE                                # MIT (or user's choice)
├── README.md
└── docs/
    └── superpowers/
        └── specs/
            └── 2026-07-13-mark-it-down-design.md   # this file
```

## 6. Behavior

### 6.1 Launch & first-run

1. `PythonLocator.find()` runs synchronously on `@main`. It probes, in order:
   - `/opt/homebrew/bin/python3`
   - `/usr/local/bin/python3`
   - `/Library/Frameworks/Python.framework/Versions/Current/bin/python3`
   - `/usr/bin/python3`
   - Result of `which python3`
2. For each candidate, parse `python3 --version`; accept the first that is ≥ 3.10. Cache the path in `UserDefaults` for next launch.
3. If **no** Python 3.10+ is found: window enters a *no-python* state — drop zone disabled, banner: *"Python 3 not found. Install via [Homebrew](https://brew.sh) (`brew install python`) or [python.org](https://python.org), then click Recheck."* with a **Recheck** button.
4. If Python is found, `MarkitdownInstaller.ensureInstalled()` runs:
   - Run `<pythonPath> -m pip show markitdown`.
   - Exit 0 → already installed, done.
   - Else: run `<pythonPath> -m pip install --user "markitdown[all]"`; stream output to a setup UI. If install fails, show the manual command with a Copy button. The user can still use the app afterwards — conversion errors will surface per-file.

### 6.2 Folder drop & preview

1. User drops a folder (or clicks the drop zone to open `NSOpenPanel`). The drop delegate extracts a single folder URL (security-scoped bookmark stored for the session).
2. `FileScanner.scan(rootURL)` walks subfolders and returns `[SourceFile]` for every file whose extension is in `SupportedExtensions`. Non-matching files are ignored.
3. For each `SourceFile`, `OutputNamer.nextAvailable(for: sourceURL, in: sourceURL.deletingLastPathComponent())` computes the target output path:
   - Replace extension with `.md`.
   - If that path does not exist → use it.
   - Else, while `<stem>(N).md` exists for N=1,2,…, pick the next free N.
4. UI renders a preview table: source filename → target output filename, source size. **Start** button is enabled.

### 6.3 Conversion

1. User clicks **Start**. `ConversionEngine.run(job)` is invoked.
2. The engine fans out up to **4 concurrent** conversions using a Swift `TaskGroup`.
3. Each task:
   - Sets `SourceFile.status = .running`
   - Calls `MarkitdownRunner.convert(source:to:)` which spawns:
     `<pythonPath> -m markitdown <source> -o <target>`
     via `Process`, captures stdout/stderr, awaits exit.
   - Sets status to `.done` or `.failed(<stderrTail>)`.
4. Progress is reported back to the UI via `@Observable` state on `ContentView`.
5. **Stop** button: cancels the `TaskGroup`, terminates any in-flight `Process`.

### 6.4 Done

- Progress bar reaches 100%.
- Counts: total, succeeded, failed.
- Buttons: **Show in Finder** (reveals the root folder), **Convert another folder** (returns to empty state).

### 6.5 Supported extensions

Whitelist (mirrors markitdown's documented support):

```
.pdf .docx .pptx .xlsx .xls .html .htm .txt .md .rtf
.epub .csv .json .xml .png .jpg .jpeg .gif .webp
.mp3 .wav .m4a .zip
```

Note: image and audio conversions require OCR / speech recognition extras installed via `markitdown[all]`. If those extras fail to install, image/audio files will fail per-file with a clear error message and the user can still convert documents.

## 7. Supported file table — UI representation

```swift
struct SourceFile: Identifiable, Hashable {
    let id = UUID()
    let sourceURL: URL
    let outputURL: URL       // pre-computed via OutputNamer
    var status: ConversionStatus = .pending
    var errorMessage: String? = nil
}

enum ConversionStatus {
    case pending
    case running
    case done
    case failed(String)
}
```

## 8. Logging

- Path: `~/Library/Application Support/Mark-It-Down/log.txt`
- Format: `[ISO8601 timestamp] [level] message`
- Contents: app launches, Python detection result, install attempts, every conversion (source, output, exit code, stderr tail), errors.

## 9. Permissions & entitlements

- App Sandbox: **disabled** (set in Info.plist via `com.apple.security.app-sandbox = false`). The app needs unrestricted filesystem access to walk arbitrary folders and write `.md` files anywhere.
- This means: **not for Mac App Store distribution**. Personal use only.
- File access is granted via standard NSOpenPanel / drag-and-drop, which is sufficient for user-initiated access.

## 10. Build & run

```
swift build -c release        # produces .build/release/markitdown
./make-app.sh release         # wraps into Mark-It-Down.app, ad-hoc codesigns
open Mark-It-Down.app         # or drag to /Applications
```

`make-app.sh` steps:
1. `swift build -c <debug|release>`
2. Create `Mark-It-Down.app/Contents/{MacOS,Resources}/`
3. Copy binary to `Contents/MacOS/Mark-It-Down`
4. Write `Contents/Info.plist` with `CFBundleName=Mark-It-Down`, `CFBundleIdentifier=local.markitdown.app`, `LSMinimumSystemVersion=14.0`, `NSHighResolutionCapable=true`, `CFBundleIconFile=AppIcon`
5. `codesign --force --deep --sign - Mark-It-Down.app` (ad-hoc)
6. Print install hint

## 11. Risks & open questions

- **Apple's removal of bundled Python** — handled by PythonLocator probing multiple locations. If all fail, the user gets a clear banner (not a crash).
- **markitdown[all] install size** — ~150 MB in user site-packages. Accepted by user during requirement gathering.
- **Ad-hoc codesign** — first launch will require right-click → Open, or one-time `xattr -dr com.apple.quarantine`. Documented in README.
- **Concurrency model** — using `Process` shell-out means a separate Python interpreter boots per file. For 4-concurrent cap this is acceptable; if profiling shows it's too slow, future revision can keep a long-lived markitdown Python subprocess using JSON-RPC.

## 12. Out of scope (deferred)

- Windows / Linux port (post-v1)
- Code signing with a developer ID
- Notarization
- Custom icon design (placeholder only for v1)
- Localization (English only for v1)
- Settings panel (no user-tunable knobs in v1; all defaults)

## 13. Success criteria

- A user with a folder of mixed PDFs, DOCX, and PPTX can produce a parallel set of `.md` files by drag-and-drop in under 30 seconds (excluding conversion time).
- Conversion time is dominated by markitdown, not the app shell.
- The app never silently overwrites an existing `.md`.
- The app never crashes due to a missing Python — it shows a clear banner with recovery instructions.
- All conversions are logged to `~/Library/Application Support/Mark-It-Down/log.txt`.