# Mark-It-Down PDF OCR Plan

**Date:** 2026-08-20  
**Status:** Proposed  
**Scope:** Add local OCR capability for scanned, image-based, and mixed PDFs on macOS

---

## 1. Problem Statement

The current hybrid PDF engine correctly detects PDFs that need OCR (scanned, image-based, mixed) but **refuses to produce any output**. The user receives an error message and must externally run OCR before retrying. This is a dead-end for the common case of scanned documents.

**Current behavior:**
```
Scanned PDF → PDF Inspector classifies as image_based/scanned/mixed
            → HybridConversionError.ocrRequired(pages) thrown
            → No .md file created
            → User must use external tool, then re-import
```

**Desired behavior:**
```
Scanned PDF → PDF Inspector classifies as image_based/scanned/mixed
            → Vision OCR renders pages and extracts text locally
            → Markdown file created (with quality caveats)
```

---

## 2. Solution: Apple Vision Framework OCR (macOS)

### Why Vision?

| Criterion | Vision | Tesseract | PaddleOCR |
|-----------|--------|-----------|-----------|
| Dependencies | None (system framework) | ~50MB binary + pip pkg | ~100MB+ models |
| Speed (Apple Silicon) | Fast (Core ML) | Slow (CPU) | Very slow (CPU) |
| CJK quality | Good | Poor | Excellent |
| Offline/private | Yes | Yes | Yes |
| Bundle size impact | 0 bytes | ~50MB | ~100MB+ |
| Cross-platform | macOS only | Both | Both |

**Decision:** Vision for macOS (Phase B). Tesseract for Windows parity (Phase C, deferred).

---

## 3. Architecture

### 3.1 New Component: `VisionOCRBackend`

```
Sources/MarkItDown/
├── HybridConversion.swift      (existing — router)
├── MarkitdownRunner.swift      (existing — MarkItDown path)
├── VisionOCRBackend.swift      (NEW — OCR path)
└── ...
```

### 3.2 Updated Routing Logic

```text
Selected source
     |
     v
HybridConversionRouter
     |
     +-- non-PDF --> MarkitdownRunner (unchanged)
     |
     +-- .pdf --> PDF Inspector inspects
                    |
                    +-- text_based, no OCR needed --> PDF Inspector Markdown (existing)
                    |
                    +-- encoding suspect --> MarkItDown fallback (existing)
                    |
                    +-- parser/contract error --> MarkItDown fallback (existing)
                    |
                    +-- scanned / image_based / mixed with OCR pages
                           |
                           +-- Vision available (macOS) --> VisionOCRBackend
                           |                                  |
                           |                                  +-- all pages OCR'd --> Markdown output
                           |                                  +-- partial failure   --> error with page list
                           |
                           +-- Vision unavailable (Windows) --> existing OCR-required error
```

### 3.3 `VisionOCRBackend` Design

```swift
struct VisionOCRBackend: DocumentConverting {
    func convert(pythonPath: URL, source: URL, output: URL) async throws
    
    // Internal:
    private func renderPages(from pdfURL: URL, dpi: Int) throws -> [NSImage]
    private func recognizeText(in image: NSImage, languages: [String]) async throws -> String
    private func mergePages(_ texts: [String], totalPages: Int) -> String
}
```

**Key implementation details:**

1. **Page rendering:** Use `PDFKit` (`PDFDocument` → `PDFPage`) to render each page at 200 DPI as `CGImage`. 200 DPI balances quality vs. memory for typical documents.

2. **OCR request:** `VNRecognizeTextRequest` with:
   - `recognitionLevel = .accurate`
   - `usesLanguageCorrection = true`
   - `recognitionLanguages = ["en-US", "zh-Hans", "zh-Hant", "ja-JP", "ko-KR"]` (top 5 by user locale, configurable)
   - `revision = .currentRevision`

3. **Page processing:** Sequential (not parallel) to bound memory. Each page: render → OCR → release image before next page.

4. **Output format:** Plain text per page with page-break markers:
   ```markdown
   <!-- Page 1 -->
   (OCR text for page 1)
   
   <!-- Page 2 -->
   (OCR text for page 2)
   ```

5. **Mixed PDF handling:** For `mixed` classification, the router already knows which pages need OCR. Only those pages go through Vision; text-based pages use PDF Inspector's extracted text.

### 3.4 Memory Management

- Render one page at a time (not all pages into an array)
- Use `CGImage` directly from PDFKit's `draw(to:mediabox:)` into a bitmap context
- Release the `CGImage` reference after each OCR call completes
- For very large PDFs (>100 pages), consider a page-size limit with user warning

---

## 4. UI Changes

### 4.1 Progress Reporting

OCR is 100x slower than PDF Inspector extraction (seconds per page vs. milliseconds). The current UI shows file-level progress only. For OCR:

- Add **page-level sub-progress** within a file's status
- Example: `report.pdf — OCR page 3/14`
- This requires extending `ConversionStatus` or adding a progress callback

**Option A (minimal):** Keep file-level status, but update the running label:
```swift
case .running(progress: Double?, detail: String?)
```

**Option B (richer):** Add a per-file progress bar in the converting list view.

**Recommendation:** Option A for v1. The `update` closure in `ConversionEngine.run` already supports per-file status updates; extend the status enum.

### 4.2 OCR Quality Disclaimer

When a file is converted via OCR, the done view should note:
> "Converted with OCR. Layout structure (tables, columns) may not be preserved."

This can be a per-file annotation in the done list or a footnote.

### 4.3 No New User Controls

Per the design principle: no engine selector, no OCR toggle. Detection is automatic. The user drops a PDF; the app figures out what to do.

---

## 5. Concurrency and Performance

### 5.1 Concurrency Adjustment

Current: `ConversionEngine` runs up to 4 files concurrently.

Problem: OCR is CPU/GPU intensive (Vision uses ANE on Apple Silicon). Running 4 OCR jobs simultaneously will:
- Saturate the Neural Engine
- Cause thermal throttling on sustained load
- Increase per-page latency

**Solution:** Add a `maxConcurrentOCR` parameter (default: 1) to `ConversionEngine`. The router signals whether a file will use OCR based on the inspection result. Non-OCR conversions keep the 4-file limit.

```swift
actor ConversionEngine {
    private let maxConcurrent: Int        // existing, default 4
    private let maxConcurrentOCR: Int     // new, default 1
    
    func run(
        job: FolderJob,
        pythonPath: URL,
        isOCR: @Sendable (SourceFile) -> Bool,  // new: router pre-classifies
        update: @MainActor @Sendable @escaping (UUID, ConversionStatus) async -> Void
    ) async
}
```

Alternatively (simpler): keep concurrency at 4 but let Vision's internal queue handle throttling. Test both approaches.

### 5.2 Expected Performance

| Document type | Pages | Estimated time (M2) |
|---------------|-------|---------------------|
| Scanned letter (1 page) | 1 | 2-4s |
| Scanned report (10 pages) | 10 | 20-40s |
| Scanned manual (50 pages) | 50 | 2-4 min |
| Mixed PDF (10 text + 5 image) | 15 | ~15-25s (5 pages OCR) |

Compare to PDF Inspector: ~20ms per page for text extraction.

---

## 6. Error Handling

| Failure | Behavior |
|---------|----------|
| PDFKit can't open file | Fail with "Could not render PDF pages" |
| Vision returns empty for a page | Mark page as `<!-- Page N: no text detected -->`, continue |
| Vision returns empty for ALL pages | Fail with "OCR could not detect any text. The scan quality may be too low." |
| Cancellation during OCR | Clean up temp files, mark as cancelled (existing behavior) |
| Memory pressure (very large PDF) | Fail gracefully with "PDF too large for OCR" if >200 pages or >500MB rendered |

**Partial success policy (changed from current):**
- If ≥1 page produces text and <50% of pages are empty → write output with placeholders for empty pages
- If >50% of pages are empty → fail (likely not a real document or too low quality)

This is a policy decision that should be confirmed before implementation.

---

## 7. Testing Strategy

### 7.1 Unit Tests (Swift)

- `VisionOCRBackend` with a mock PDF (rendered pages → expected text)
- Router integration: scanned PDF routes to Vision, not MarkItDown
- Mixed PDF: correct page split between Inspector and Vision
- Cancellation mid-OCR: no temp files, correct status
- Empty OCR result handling
- Page limit enforcement

### 7.2 Fixture PDFs

Create or document test fixtures:
- `scanned_single_page.pdf` — 1 page, clear text
- `scanned_multi_page.pdf` — 5+ pages, mixed density
- `mixed_text_image.pdf` — 3 text pages + 2 image pages
- `scanned_cjk.pdf` — Chinese/Japanese text
- `scanned_low_quality.pdf` — blurry, for failure testing

Store under `Tests/ManualFixtures/` with SHA-256 checksums (existing convention).

### 7.3 Acceptance Criteria

- [ ] Scanned PDF produces non-empty Markdown with readable text
- [ ] Mixed PDF combines Inspector text + OCR text in correct page order
- [ ] Cancellation during OCR leaves no temp files
- [ ] 10-page scanned PDF completes in <60s on M2
- [ ] No OCR output reported as success if all pages are empty
- [ ] Existing 41 tests remain green
- [ ] Non-PDF formats unaffected (regression check)

---

## 8. Implementation Phases

### Phase A — UX Improvements (1 day)

**Goal:** Better failure messaging + partial extraction for mixed PDFs. No OCR yet.

Tasks:
1. Improve `HybridConversionError.ocrRequired` message with specific tool recommendations:
   - macOS: "Use Preview → File → Export (re-exports with text layer on macOS 14+)"
   - Generic: "Use Adobe Acrobat 'Recognize Text' or ABBYY FineReader"
2. For `mixed` PDFs: extract available text pages, write partial Markdown with `<!-- Page N: OCR required -->` placeholders for image pages. Mark the file as done-with-warning (new status or annotation).
3. Add OCR quality disclaimer text to the done view for any file that had OCR-related issues.

**Deliverable:** User gets *something* (partial text) instead of nothing for mixed PDFs. Clear guidance for fully-scanned PDFs.

### Phase B — Vision OCR Backend (2-3 days)

**Goal:** Full local OCR for scanned/image PDFs on macOS.

Tasks:
1. Create `VisionOCRBackend.swift`:
   - PDFKit page rendering at 200 DPI
   - `VNRecognizeTextRequest` with locale-appropriate languages
   - Sequential page processing with memory release
   - Page-break marker output format
2. Update `HybridConversionRouter`:
   - Route `scanned`/`image_based` to VisionOCRBackend (macOS only)
   - Route `mixed` with OCR pages: split between Inspector and Vision
   - Keep existing fallback logic for parser errors
3. Extend `ConversionStatus` with optional progress detail (page X/Y)
4. Update `ConversionEngine` for OCR-aware concurrency (limit to 1-2 OCR jobs)
5. Update `ContentView` converting list to show page-level progress
6. Add partial success policy (≥1 page text → write output)
7. Write unit tests with mock Vision results
8. Integration test with real scanned PDF fixture

**Deliverable:** Drop a scanned PDF → get Markdown output. No external tools needed.

### Phase C — Windows Parity (deferred, 3-5 days)

**Goal:** OCR on Windows via Tesseract in the Python runtime.

Tasks:
1. Bundle Tesseract binary (~50MB) in Windows portable runtime
2. Add `pytesseract` to Windows requirements
3. Create Python OCR helper script (same JSON contract as PDF Inspector)
4. Route Windows scanned PDFs to Tesseract backend
5. Windows integration testing

**Note:** This phase is explicitly deferred until the macOS Vision implementation is stable and released.

---

## 9. Files to Create/Modify

### New files
| File | Purpose |
|------|---------|
| `Sources/MarkItDown/VisionOCRBackend.swift` | Vision OCR implementation |
| `Tests/MarkItDownTests/VisionOCRBackendTests.swift` | Unit tests |
| `Tests/ManualFixtures/` (new PDFs) | Scanned test fixtures |

### Modified files
| File | Change |
|------|--------|
| `Sources/MarkItDown/HybridConversion.swift` | Route OCR-required PDFs to Vision; handle mixed split |
| `Sources/MarkItDown/ConversionEngine.swift` | OCR-aware concurrency limit |
| `Sources/MarkItDown/Models/ConversionStatus.swift` | Add progress detail for OCR |
| `Sources/MarkItDown/AppCoordinator.swift` | Pass VisionOCRBackend to router |
| `Sources/MarkItDown/ContentView.swift` | Show page-level progress; OCR disclaimer |
| `Sources/MarkItDown/Models/FolderJob.swift` | Possibly add per-file progress tracking |

### Unchanged
| File | Reason |
|------|--------|
| `MarkitdownRunner.swift` | Non-PDF and fallback path unchanged |
| `Resources/markitdown_pdf_inspector.py` | Inspection logic unchanged |
| `MarkitdownInstaller.swift` | No new pip dependencies for Vision path |
| `PythonLocator.swift` | No change |
| `FileScanner.swift` | No change |

---

## 10. Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Vision OCR quality poor for low-res scans | User frustration | Quality disclaimer; fail if >50% pages empty |
| Large PDFs cause memory pressure | Crash | Sequential processing; page limit (200); size check |
| ANE saturation with concurrent OCR | Thermal throttling | Limit OCR concurrency to 1-2 |
| CJK text quality inferior to PaddleOCR | Limited CJK support | Accept for v1; document limitation; Phase C can improve |
| PDFKit rendering fails on encrypted PDFs | Silent failure | Check `PDFDocument` password protection; fail with clear message |
| Vision API changes in future macOS | Breakage | Pin minimum macOS version; use stable API only |

---

## 11. Out of Scope

- Cloud OCR services (violates privacy design)
- User-facing engine selector or OCR toggle
- Table/layout structure recovery from OCR (research problem)
- Handwriting recognition
- Audio/speech-based extraction
- Windows implementation (Phase C, deferred)
- Changing the PDF Inspector dependency or its version

---

## 12. Open Questions (Resolve Before Phase B)

1. **Partial success threshold:** Is ≥1 page with text sufficient to write output? Or should we require >50% of pages?
2. **Language selection:** Auto-detect from system locale, or offer a small language picker in the preview view?
3. **DPI:** 200 DPI default — should this be configurable for high-quality scans?
4. **Page limit:** Hard cap at 200 pages? Or size-based (e.g., >500MB rendered)?
5. **Mixed PDF output format:** Interleave Inspector text and OCR text by page number, or separate sections?
6. **Progress granularity:** Page-level is sufficient, or do we need character-level for very long pages?

---

## 13. Success Metrics

- User drops a scanned PDF and gets readable Markdown without external tools
- 10-page scanned document converts in <60s on M2
- No regression in text-based PDF performance (still ~20ms/page via Inspector)
- All existing tests pass; new tests cover OCR paths
- No new pip dependencies (Vision is system framework)
- App bundle size unchanged (0 bytes added)
