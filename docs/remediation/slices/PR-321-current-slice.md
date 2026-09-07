# PR-321 Current Slice: TPM Organization and Governance Reset

- Slice ID: TPM-RESET-001
- Slice name: TPM organization/governance/architecture reset
- Included owner-report IDs: all 1-32 for tracking; direct truth reset for 3, 11, 12, 24, 26, 30, 32.
- Explicit exclusions: product bug fixes, broad module extraction, owner smoke, package rebuild, commit, push, release, certification, wiki, ARCADE/#323.

## Contract

Create durable contract, control-board, provenance, subsystem ownership, UX contract, and gate infrastructure. Preserve conservative status language and separate source/package/runtime proof. Do not claim any NOT FIXED report fixed.

## Files allowed to change

Governance docs, control-board/report docs, slice-contract docs, architecture roadmap/map, permanent procedure gate, and tests needed to enforce these artifacts. No unrelated product source changes.

## Tests required

Main Pester, SupportPackage.Tests, focused gate/source-contract tests, parse, ASCII, PSScriptAnalyzer, diff check, permanent procedure gate, and combined quality gate when feasible.

## Runtime proof required

None authorized for this organization slice. Future product slices must name a fresh exact-SHA candidate and owner-visible smoke checklist.

## Stop condition

Stop after operating model, contract types, control board, slice system, ownership map, roadmap, governance rules, gate checks, and reconciliation truth are present and validated.

## Forbidden actions

No commit, push, package, release, certification, wiki, ARCADE/#323, owner smoke, stale ZIP validation, or broad product rewrite.

## Gate expectations

The gate must pass new infrastructure checks and still fail closed for unresolved owner IDs, stale candidate identity, and missing owner-runtime evidence.
