# Hybrid PDF engine benchmark

**Date:** 2026-08-04  
**Environment:** macOS 26.6, Apple Silicon  
**Runs:** Three fresh processes per engine and document  
**Versions:** MarkItDown 0.1.7; PDF Inspector 0.2.6

## Method

`scripts/benchmark_hybrid_pdf.py` ran the pinned MarkItDown CLI and the repo-owned PDF Inspector helper using the same isolated virtual environment. Each run wrote to a temporary directory. The JSON evidence records source/output hashes, sizes, elapsed time, exit status, and PDF classification metadata; it does not contain source or Markdown content.

The raw JSON remains an untracked task artifact at `work/hybrid-benchmark-2026-08-04.json` in the associated Codex workspace. Private source documents and generated Markdown are not committed.

## Results

| Document | MarkItDown median | PDF Inspector median | PDF classification | Inspector output |
|---|---:|---:|---|---:|
| `firecrawl_docs_tagged.pdf` | 293.641 ms | 23.145 ms | `text_based` | 11,118 bytes |
| `forecast_table_chart.pdf` | 185.587 ms | 19.496 ms | `text_based` | 906 bytes |
| `wireless_two_col_no_rects.pdf` | 201.670 ms | 20.290 ms | `text_based` | 2,131 bytes |
| `greencomp_competence.pdf` | 235.409 ms | 21.591 ms | `text_based` | 2,483 bytes |
| 72 MB outlined manual | 2,482.827 ms | 49.905 ms | `image_based`; pages 1–14 need OCR | no output |

Across the four native-text fixtures, the median of per-document medians was 218.540 ms for MarkItDown and 20.941 ms for PDF Inspector, approximately a 10.4x speedup. Output sizes differ because the engines apply different structural heuristics; timing alone is not a semantic-quality judgment.

## Integrity references

| Document | SHA-256 |
|---|---|
| `firecrawl_docs_tagged.pdf` | `9cf8b251ade155b16a934f21613da51198d8b59fb13baf1e6c19c11b43f4077a` |
| `forecast_table_chart.pdf` | `a0edae1fa147c7bb78ebc493743a68ba4372b5ead31f2a2b146c35119462379e` |
| `wireless_two_col_no_rects.pdf` | `603d71e12f52d9801a9d82995babf69681d923f493b8d49abfbab8662a88b376` |
| `greencomp_competence.pdf` | `ba0e025d53c091e8d4bb87499ff69ed3428dcee325c8895ecdb40e973b4c835c` |
| 72 MB outlined manual | `c974cb66d4f70491742dc22e2a7d027102f810866447e66004621d4f10fb974e` |

## Acceptance interpretation

- The local performance threshold of at least 3x was met on all four native-text fixtures.
- The helper produced structured Markdown for each native-text fixture.
- The outlined manual was correctly rejected as `image_based`, with all 14 pages identified for OCR and no Markdown written.
- Manual semantic review of a broader representative corpus and clean-account first-run validation remain release gates.

