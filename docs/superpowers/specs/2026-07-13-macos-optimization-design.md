# Mark-It-Down macOS Optimization Design

## Goal

Optimize the existing macOS SwiftUI app for correctness, responsiveness, reliability, and maintainability while preserving its simple drag-drop-start workflow and current visual design.

## Scope

This pass is macOS-only. It will improve the conversion engine, subprocess lifecycle, file scanning, output naming, coordinator state management, automated coverage, and user-facing status accuracy. It will not redesign the interface, add Windows support, change the external `microsoft/markitdown` dependency, or introduce unrelated features.

## Architecture

Keep SwiftUI and AppKit integration in the application target. Extract only the logic that benefits from deterministic tests:

- `FileScanner` discovers supported regular files and assigns output paths.
- `OutputNamer` reserves unique paths against both the filesystem and the current batch.
- `CommandRunner` owns subprocess execution, output collection, termination, and task cancellation.
- `PythonLocator` and `MarkitdownInstaller` use `CommandRunner` for probing and installation.
- `ConversionEngine` schedules bounded work and reports terminal outcomes.
- `AppCoordinator` owns the active job generation and maps engine events into UI state.

The types remain small and purpose-specific. No generic framework or cross-platform abstraction will be added.

## File Scanning and Output Naming

Directory enumeration will request the regular-file metadata it consumes and skip hidden files and package descendants where appropriate. Results will be sorted deterministically so the preview and test output do not depend on filesystem enumeration order.

Output naming must account for paths already present on disk and paths assigned earlier in the same scan. For example, `report.pdf` and `report.docx` in one directory must receive different Markdown destinations even when neither destination exists yet. Existing files remain untouched; suffixes continue to use the current `name(N).md` convention.

## Subprocess Execution

`SystemCommandRunner` will consume stdout and stderr while the process is running so a verbose `pip` install or conversion cannot fill a pipe buffer and deadlock. The runner will provide exactly one completion result and preserve both output streams for diagnostics.

Swift task cancellation will terminate the child process and surface `CancellationError`. Process startup failures, non-zero exit codes, and cancellation remain distinct outcomes. Conversion failures will display concise actionable messages; installation failures will include the command the user can run manually.

## Conversion Scheduling and Cancellation

Bounded concurrency remains configurable and defaults to four conversions. The engine will not schedule new work after cancellation. Active runner calls will receive cancellation through `CommandRunner`, and files that never start will remain pending rather than being counted as failures.

The coordinator will associate callbacks with the active conversion generation. Events from an older stopped or replaced job will be ignored. Stopping returns the current job to preview after cancellation has been requested, and a cancelled run will not later switch the UI to a misleading completed state.

Terminal counts will distinguish success, failure, and cancellation/pending work. The current minimal UI remains intact; wording changes are limited to making actual state clear.

## State and Performance

Status updates will avoid repeated whole-list filtering for every rendered frame. Counts will be computed in one pass or maintained alongside job updates. Coordinator mutations remain on `MainActor`, while scanning, command execution, and conversions stay off the main actor.

Array copying will be kept proportional to the small value-model architecture. A larger reference-model rewrite is excluded unless measurement shows it is needed.

## Error Handling

- Empty scans produce a clear preview state with Start disabled.
- A failed source records its own error without stopping unrelated conversions.
- Cancellation is not reported as conversion failure.
- Python discovery skips unusable candidates and continues probing.
- Installer diagnostics retain stderr from failed commands.
- Output files are never intentionally overwritten.

## Testing

Add a SwiftPM test target and use XCTest supplied by the current Swift toolchain. Tests will cover:

- supported-extension matching;
- unique output naming against disk and within a batch;
- deterministic recursive scanning and filtering;
- Python version parsing and candidate selection;
- installer probe/fallback behavior using a controlled runner;
- real subprocess stdout/stderr collection, non-zero exit status, large output, and cancellation;
- conversion concurrency limits, isolated failures, and cancellation;
- coordinator protection against stale completion events where practical without UI automation.

Production changes follow red-green-refactor: each behavior gets a failing test first, the smallest implementation that passes, and a full-suite rerun.

## Verification

Completion requires fresh evidence from:

1. `swift test`
2. `swift build -c debug`
3. `swift build -c release`
4. `./make-app.sh release`
5. package/bundle inspection, including executable and code signature
6. a clean Git diff review with no generated build artifacts tracked

Manual GUI interaction is recommended for drag-and-drop and Finder presentation, but automated core coverage and build verification are mandatory.

## Success Criteria

- No batch can assign the same output path to two sources.
- Verbose subprocesses complete without pipe-buffer stalls.
- Stop terminates active work and cannot be followed by stale completion UI.
- Concurrency never exceeds the configured limit.
- Existing files are not overwritten.
- The simple current UI and primary workflow remain recognizable.
- Tests, debug/release builds, and app assembly all pass on the current Mac toolchain.
