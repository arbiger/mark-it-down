# Mark-It-Down hybrid PDF engine design

**Date:** 2026-08-04  
**Status:** Implemented macOS pilot — automated and local GUI acceptance passed; separate clean-account gate remains  
**Decision:** Approved as a gated macOS pilot

## 1. Summary

Keep Microsoft MarkItDown as the general document converter and route PDF files through Firecrawl PDF Inspector first. PDF Inspector is a local Rust parser with Python bindings; it is not an OCR engine. Its useful role is fast, structured extraction for native-text PDFs and early identification of scanned, image-only, mixed, or broken-encoding PDFs.

The first implementation should use the published `pdf-inspector==0.2.6` Python wheel, not a Swift/Rust FFI layer. This is the smallest change to the current process-based architecture, has prebuilt Apple Silicon and Intel macOS wheels, and leaves a straightforward path for the Windows portable runtime. The dependency must be pinned and installed in an app-private environment.

The existing Microsoft MarkItDown path remains responsible for DOCX, PPTX, XLSX, HTML, images, audio, archives, and every other supported non-PDF format. It also remains available as a narrow PDF fallback when PDF Inspector itself cannot parse a native-text PDF.

## 2. Evidence

### Current application

- The macOS app is a native SwiftUI shell.
- `ConversionEngine` runs up to four files concurrently.
- Each file starts a fresh Python process running `python -m markitdown`.
- Before this implementation, bootstrap accepted any importable MarkItDown version and this Mac selected `markitdown 0.0.2`.
- The implemented private environment verifies `markitdown 0.1.7` and `pdf-inspector 0.2.6` exactly.
- Empty or whitespace-only Markdown is already rejected, which must remain true.

### Local benchmark

The benchmark used three fresh-process runs per document, matching the app's current execution model. The four PDFs covered tagged content, a table/chart, two-column text, and a longer standards-style document.

| Engine | Median of per-document medians | Relative to PDF Inspector |
|---|---:|---:|
| App-installed MarkItDown 0.0.2 | 416.2 ms | 18.9x slower |
| Current MarkItDown 0.1.7 | 219.7 ms | 10.0x slower |
| PDF Inspector 0.2.6 | 22.0 ms | baseline |

Output byte counts were in the same broad range but were not identical. This timing sample proves the performance opportunity; it does not by itself prove semantic equivalence.

The existing 72 MB, 14-page outlined-text manual was also tested. PDF Inspector classified it as `image_based`, reported all 14 pages as needing OCR, and completed detection in about 32 ms. Full processing produced no Markdown, which is the correct behavior because the PDF contains no extractable text. MarkItDown also produced an empty file.

Local fixture SHA-256: `c974cb66d4f70491742dc22e2a7d027102f810866447e66004621d4f10fb974e`.

Firecrawl's published benchmark reports higher extraction quality and much lower elapsed time than MarkItDown on a 200-document direct-extraction corpus, with OCR disabled. Treat that as upstream evidence, not a substitute for this project's own regression corpus.

Sources:

- [Firecrawl PDF Inspector](https://github.com/firecrawl/pdf-inspector)
- [PDF Inspector Python API](https://github.com/firecrawl/pdf-inspector/blob/main/docs/python.md)
- [Microsoft MarkItDown](https://github.com/microsoft/markitdown)

Both dependencies are MIT-licensed.

## 3. Goals

- Make native-text PDF conversion materially faster.
- Improve headings, tables, multi-column reading order, and PDF-specific diagnostics.
- Detect pages that need OCR without sending documents to a service.
- Preserve exact file/folder selection, collision-safe naming, bounded concurrency, cancellation, and empty-output rejection.
- Preserve the current simple drop-review-start interface.
- Make dependency versions reproducible and upgrades deliberate.

## 4. Non-goals

- Implement OCR in this phase.
- Replace Microsoft MarkItDown for non-PDF formats.
- Add cloud conversion, accounts, or document upload.
- Add an engine selector or advanced settings to the main UI.
- Bind Rust directly into Swift or C# in the first implementation.
- Publish a release before corpus, UI, build, and packaging gates pass.

## 5. Proposed architecture

```text
Selected source
     |
     v
HybridConversionRouter
     |
     +-- .pdf --> PdfInspectorBackend
     |                |
     |                +-- native text, clean encoding --> atomic Markdown output
     |                +-- scanned/image/mixed ----------> needs-OCR failure with pages
     |                +-- parser/encoding failure ------> narrow MarkItDown PDF fallback
     |
     +-- other --> MarkItDownBackend --> atomic Markdown output
```

### Swift boundaries

Replace the PDF-specific name `MarkitdownRunning` at the orchestration boundary with a format-neutral protocol such as `DocumentConverting`. Add:

- `HybridConversionRouter`: chooses a backend strictly from the source extension.
- `PdfInspectorRunner`: runs a repo-owned Python entrypoint and decodes a small JSON result.
- `MarkitdownRunner`: retains the existing general conversion path.
- `ConversionResult`: carries engine, output state, classification, pages needing OCR, and a concise diagnostic.

`ConversionEngine` should continue to own concurrency only. It must not contain PDF classification policy.

### Python entrypoint contract

Use one repo-owned helper entrypoint rather than inline `python -c` strings. Input arguments are source and temporary output paths. Standard output is one JSON object:

```json
{
  "schemaVersion": 1,
  "classification": "text_based",
  "pagesNeedingOCR": [],
  "encodingSuspect": false,
  "markdownWritten": true
}
```

Diagnostics go to standard error. Paths remain arguments, not interpolated source code. The runner writes to a temporary sibling path and the app atomically moves it to the pre-reserved destination only after validation.

## 6. Routing and failure policy

1. Non-PDF files always use Microsoft MarkItDown.
2. PDFs use PDF Inspector first.
3. `text_based`, no pages needing OCR, no encoding issue, and non-whitespace Markdown is success.
4. `scanned`, `image_based`, or `mixed` with pages needing OCR is not silently reported as complete. No final `.md` is created. The error identifies the affected pages and explains that OCR or selectable text is required.
5. A PDF Inspector parser exception or encoding issue may try Microsoft MarkItDown once. The fallback must pass the same missing/empty/whitespace validation. The corpus gate will determine whether encoding-issue fallback is trustworthy enough to ship.
6. Cancellation removes temporary output and never replaces a reserved destination.
7. Existing output files are never overwritten.

This policy deliberately avoids pretending that partial text from a mixed PDF is a complete conversion. Per-page OCR and merging can be designed later.

## 7. Dependency and packaging policy

- Create an app-private Python virtual environment under `~/Library/Application Support/Mark-It-Down/runtime/` on macOS, mirroring the Windows app's private-runtime model.
- Pin the tested baseline: `markitdown[all]==0.1.7` and `pdf-inspector==0.2.6`.
- Keep the tested direct pins in `Resources/requirements-macos.txt`, used by bootstrap and copied into the app bundle. A complete transitive hash lock is not yet present and remains a release-hardening item.
- An import probe alone is insufficient. Bootstrap verifies the exact allowed version range and repairs drift inside the private environment.
- Do not modify or depend on unrelated user-level Python packages.
- Include MIT license text and dependency versions in third-party notices.
- Keep a documented rollback path that disables PDF routing and uses MarkItDown for all formats.

The upstream project is active and its PyPI, Rust crate, Node package, and Git tags do not share one version number. Pin the exact distribution being integrated rather than a repository tag with a similar-looking number.

## 8. User experience

The normal flow does not change. A PDF that needs OCR gets a more precise message, for example:

> No complete Markdown was created. Pages 1–14 contain no extractable text and need OCR, or the PDF must be exported with selectable text.

The Done view may show `PDF Inspector` or `Microsoft MarkItDown` in diagnostics/logs, but the primary UI should not require the user to choose an engine.

## 9. Verification gates

### Correctness corpus

Include or document fixtures for:

- ordinary native text;
- tagged headings;
- rectangle and alignment-based tables;
- two-column reading order;
- CJK/CID fonts;
- encrypted/corrupt inputs;
- scanned, image-only, mixed, and outlined-text PDFs;
- an encoding issue that exercises the fallback decision.

Large or non-redistributable manuals remain untracked under `Tests/ManualFixtures/` with checksums recorded locally; small redistributable fixtures may be committed with provenance.

### Acceptance thresholds

- At least 3x lower median fresh-process time than pinned MarkItDown on the local text-PDF corpus.
- No empty or whitespace-only output reported as success.
- No mixed/scanned document reported as a complete conversion when pages need OCR.
- Golden-output review shows no material regression in reading order, tables, headings, CJK, or links on the approved corpus.
- Stop terminates active child processes and leaves no final or temporary output.
- Existing 21 core tests remain green, with new router, JSON-contract, fallback, atomic-output, and classification tests.
- Debug/release build, app assembly, code signature, Info.plist validation, and manual drag/drop pass.

## 10. Rollout

1. Fix dependency isolation and record a latest-MarkItDown baseline without changing routing.
2. Add format-neutral converter boundaries with behavior-preserving tests.
3. Add the pinned PDF Inspector runner behind an internal feature flag.
4. Run the correctness/performance corpus and decide the encoding fallback from evidence.
5. Enable the hybrid router on macOS and complete manual UI/build verification.
6. After the macOS pilot is stable, apply the same JSON runner contract to the Windows source and rebuild its offline runtime.
7. Update README, third-party notices, versioning, and release artifacts only after all gates pass.

## 11. Approved decisions and remaining gates

- Approved: mixed PDFs requiring OCR fail rather than emit partial Markdown.
- Approved: macOS uses an app-private environment and does not modify user-global Python packages.
- Approved: Windows follows the macOS pilot.
- Passed locally: release assembly/signature, native-text conversion, page-specific OCR failure without output, Show in Finder, and mid-batch Stop behavior.
- Remaining: separate clean-account first run, full transitive license/hash inventory, Windows work, and publishing.
