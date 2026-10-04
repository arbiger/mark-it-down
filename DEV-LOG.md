# Development log

## 2026-08-04 — Hybrid PDF engine

### Goal

Combine Firecrawl PDF Inspector with the existing Microsoft MarkItDown macOS app so native-text PDFs convert faster while non-PDF formats retain the general converter.

### Decisions

- Route PDFs to PDF Inspector first; use MarkItDown for non-PDF formats.
- Treat scanned, image-only, and mixed PDFs that need OCR as incomplete and do not create a final Markdown file.
- Permit one MarkItDown PDF fallback for parser/contract or encoding failures, but not for OCR-required classifications.
- Install direct pins `markitdown[all]==0.1.7` and `pdf-inspector==0.2.6` only in `~/Library/Application Support/Mark-It-Down/runtime/venv`.
- Keep Windows integration and public release outside this pass.

### Agent Squad execution

- Sol High: planning, architecture, blue/red review, acceptance, and corrective test work.
- Luna Max: hybrid Swift core, private-runtime bootstrap, helper/resources, packaging changes, initial tests, and benchmark harness.
- Review type: coordinator red-blue review, not independent review.

### Changed areas

- Format-neutral `DocumentConverting` boundary and hybrid router.
- Versioned Python PDF helper and direct dependency pins.
- Private virtual-environment creation, repair, and exact-version verification.
- Atomic temporary output for both engines.
- Expanded bootstrap, routing, fallback, OCR, JSON-contract, cancellation, and cleanup tests.
- Metadata-only benchmark harness and evidence report.

### Verification

- Native core suite: 41/41 passed.
- Strict-concurrency debug and release Swift builds: passed.
- Release app assembly: passed; `Info.plist` is valid and the ad-hoc code signature verifies with deep/strict checks.
- Real helper: native-text fixture produced 11,118 bytes; outlined 14-page manual classified `image_based`, pages 1–14 needing OCR, with no output.
- Three-run local corpus: approximately 10.4x median speedup across four native-text fixtures.
- Live GUI: exact single-file selection converted successfully, Show in Finder selected the 11 KB Markdown output, and the outlined manual failed with page-specific OCR guidance without creating Markdown.
- Live Stop: cancellation was triggered during a 300-file batch, the UI returned from active progress to preview, active helper processes terminated, and no temporary files remained.
- First-run repair: a real launch exposed Python 3.14 incompatibility in the pinned MarkItDown dependency set. The locator now chooses Python 3.10–3.13 only, rebuilt the private environment with Python 3.11.15, and verified MarkItDown 0.1.7 plus PDF Inspector 0.2.6.
- Separate Luna Max verification pass: 41/41 tests, strict debug/release builds, app assembly, plist/signature/resource checks, diff hygiene, private-runtime versions, temporary-file scan, and inactive subprocess state all passed; Sol retained plan and final review ownership. This was same-worker verification, not independent testing.

### Remaining gates

- A separate clean macOS user-account first-run check. The local repair test covers private-environment creation and version verification, but is not evidence from a separate account.
- Full transitive dependency license/hash inventory before public distribution.
- Windows implementation and release/publishing decisions.
