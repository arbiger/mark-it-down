# Mark-It-Down hybrid PDF engine implementation plan

**Date:** 2026-08-04  
**Status:** Gates 0–6 implemented; Gate 7 locally accepted with separate clean-account check outstanding; Gates 8–9 deferred

This plan implements the approved design in small gates. Stop after any gate that fails; do not compensate for extraction-quality regressions with timing alone.

## Execution status

- Gates 0–5: implemented with private-runtime, routing, JSON-contract, atomic-output, and failure-path tests.
- Gate 6: local metadata-only benchmark passed the 3x threshold; see `docs/benchmarks/2026-08-04-hybrid-pdf-baseline.md`.
- Gate 7: 41/41 native tests, strict debug/release builds, app assembly/signature, and local GUI behavior passed. A separate clean macOS user-account first-run check remains before calling the release candidate fully approved.
- Gates 8–9: Windows and publishing were not authorized in this pass and remain deferred.

## Gate 0 — approve behavior

- Review the design spec.
- Confirm strict handling of mixed PDFs: fail with page-specific OCR guidance instead of silently writing incomplete Markdown.
- Confirm app-private Python environment and pinned dependencies.
- Confirm macOS-first versus simultaneous Windows scope.

Deliverable: approved spec with resolved approval points.

## Gate 1 — baseline and corpus

- Add a reproducible benchmark/quality harness that records engine version, source hash, elapsed time, exit state, and output hash/size.
- Assemble the approved PDF corpus with provenance. Keep large/private manuals under ignored `Tests/ManualFixtures/`.
- Run pinned MarkItDown alone to establish current quality, performance, cancellation, and failure behavior.
- Save a dated benchmark report under `docs/benchmarks/`; do not commit private documents or generated Markdown containing their content.

Deliverable: reviewed baseline report. No routing change.

## Gate 2 — dependency isolation

- Add a lock file for `markitdown[all]` and PDF Inspector with hashes.
- Replace macOS user-global installation with an app-private virtual environment.
- Verify exact versions, repair incomplete environments, and retain manual recovery instructions.
- Test missing Python, incompatible Python, interrupted installation, offline relaunch, and existing unrelated user packages.

Deliverable: MarkItDown-only app with reproducible dependencies and all existing behavior preserved.

## Gate 3 — format-neutral conversion boundary

- Introduce `DocumentConverting`, `ConversionResult`, and `HybridConversionRouter` names/types.
- Adapt the existing MarkItDown runner without changing format routing.
- Keep `ConversionEngine` focused on scheduling and cancellation.
- Add unit tests proving every supported extension still chooses MarkItDown at this gate.

Deliverable: internal refactor with identical user-visible behavior.

## Gate 4 — PDF Inspector runner

- Add the repo-owned Python runner with a versioned JSON output contract.
- Validate source/output arguments, classification enum values, page numbering, encoding flag, and nonempty Markdown.
- Write to a temporary sibling path, then atomically move on success.
- Add tests for malformed JSON, non-zero exit, timeout, cancellation, missing output, empty output, and temporary-file cleanup.

Deliverable: disabled PDF backend with complete contract tests.

## Gate 5 — hybrid routing and diagnostics

- Route `.pdf` to PDF Inspector behind an internal feature flag.
- Apply the approved scanned/image/mixed policy.
- Try MarkItDown only for the approved parser/encoding fallback cases.
- Add page-specific OCR errors and retain per-file failures without stopping the batch.
- Keep file selection, collision naming, four-file concurrency, Stop, and Finder behavior unchanged.

Deliverable: testable hybrid macOS build, not yet released.

## Gate 6 — corpus decision

- Run both engines on the full corpus using fresh processes and repeatable order.
- Compare timing plus reading order, tables, headings, links, CJK, and failure classifications.
- Manually review every output difference that the automated checks cannot classify.
- Require the thresholds in the design spec. If quality fails, adjust routing narrowly or keep the feature disabled.

Deliverable: dated go/no-go report with exact versions and source hashes.

## Gate 7 — macOS product verification

- Run the native core test suite.
- Run strict concurrency debug and release builds.
- Assemble the `.app`, validate Info.plist and code signature.
- Manually verify single-file, multi-file, mixed file/folder, Stop, failure details, and Show in Finder.
- Verify first run on a clean macOS user account or equivalent isolated environment.

Deliverable: approved macOS release candidate.

## Gate 8 — Windows follow-up

- Move the Windows source into a tracked platform source location before modifying it; keep portable binaries under ignored `dist/`.
- Reuse the same pinned Python dependencies and JSON runner schema.
- Rebuild the offline runtime and update third-party notices.
- Run Windows core tests and real WPF drag/drop, Stop, and Explorer checks on Windows 10/11.

Deliverable: approved Windows release candidate. Do not infer Windows success from macOS tests.

## Gate 9 — release

- Update README, credits, privacy/security notes, project layout, and release notes.
- Include dependency versions, licenses, checksums, and rollback instructions.
- Tag and publish only after both the requested platform gates are evidenced.

Deliverable: versioned release artifacts under `dist/` locally and the approved public release channel.
