# Project documentation

## Current implementation

- [Hybrid PDF engine design](superpowers/specs/2026-08-04-hybrid-pdf-engine-design.md) — implemented macOS pilot; automated and local GUI acceptance passed, with a separate clean-account gate remaining.
- [Hybrid PDF engine implementation plan](superpowers/plans/2026-08-04-hybrid-pdf-engine-plan.md) — execution status and remaining release gates.
- [Hybrid PDF benchmark](benchmarks/2026-08-04-hybrid-pdf-baseline.md) — reproducible metadata-only timing and classification evidence.

## Existing design history

- [Original macOS design](superpowers/specs/2026-07-13-mark-it-down-design.md)
- [macOS optimization design](superpowers/specs/2026-07-13-macos-optimization-design.md)
- [Original implementation plan](superpowers/plans/2026-07-13-mark-it-down.md)
- [macOS optimization plan](superpowers/plans/2026-07-13-macos-optimization.md)

Generated applications and portable release bundles belong under `dist/` and are intentionally excluded from Git. Large manual-only documents belong under `Tests/ManualFixtures/`; automated, redistributable fixtures should remain small and tracked with their provenance documented.
