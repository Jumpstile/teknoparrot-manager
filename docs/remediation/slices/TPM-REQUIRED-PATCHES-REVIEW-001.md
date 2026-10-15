# Required patch integration review contract

## 1. Scope

- Contract ID: `TPM-REQUIRED-PATCHES-REVIEW-001`.
- Owner issue: #351; integration is stacked on PR #321 head `9a9ac19` for
  review. This contract authorizes local source and test preparation only;
  GitHub handoff follows the required checks and independent review.
- Candidate scope: the independently source-verified 13-entry recipe catalog across 12 exact game builds. Preserve every recipe's exact profile/build/executable/source/target binding. Do not expand the catalog in this slice.
- Preserve all required ReShade and other RC8 fixes present in source HEAD `18e82a7`; do not carry private commit history or unrelated files merely to preserve code.

## 2. Expected behavior

- Existing catalog entries retain exact profile and executable bindings, source-member identity, hardware predicates, exclusive variants, prerequisites, target-state rules, verified backup, read-back, receipt-bound undo, and truthful non-readiness wording.
- Absent-only restorations create a target only when absent; exact after-state is a no-op; every unknown or conflicting existing state refuses without replacement.
- BBCP's driver replacement is included only with its independently verified exact before/after bytes, executable binding, and source-member pins. The engine remains strict about source and target identity; no generic cross-game association is permitted.
- Keep schema compatibility and all unrelated established RC8 behavior unchanged. No live game, collection, DAT, profile, service, database, driver, or codec mutation.

## 3. Tests and evidence

- Before transplant: inspect all ten commits from PR #321 head to source HEAD, classify each commit, and verify the exact current source/test inputs.
- After transplant: run the required focused catalog tests under PowerShell 5.1 and PowerShell 7 with Pester 5.7.1; run the complete Main and Support suites, ASCII/parse, configured PSScriptAnalyzer, canonical InjectionHunter with reviewed dispositions, and `scripts/Run-TpmQualityGate.ps1` against the current remediation report.
- Record commands, exact input SHA-256 values, UTC intervals, engine/module versions, exit status, and immutable receipts. Do not relabel historical receipts or the earlier five-entry full-folder failure.
- Synthetic local fixtures are the only runtime mutation proof in this phase. Owner-visible GUI interaction, owner installation state, gameplay, full Procedure A/B, Arcade, PostgreSQL mutation, and release acceptance remain separate and unclaimed.

## 4. Hunk mapping and documentation

- Source/runtime, catalog, package allowlist, tests, and user/engineering documentation hunks map to Issue #351, this contract, and `TPM-TRACE-001`, `TPM-EVIDENCE-001`, `TPM-UX-001`, and `TPM-TRUTH-001` as applicable.
- PR #321 owner-report statuses remain unchanged. The reconciliation report and control board receive a separate sanitized #351 addendum; no private owner-session identifiers, personal paths, private NAS names, credentials, or private conversation IDs are added.
- Keep exact source hashes and test counts synchronized in the review report. Do not include binary owner-test ZIPs or private raw transcripts in the branch.

## 5. Stop condition

Stop at a clean, reviewable local branch based on the verified PR #321 head,
after the required checks pass and the exact outgoing file list, privacy scan,
commit-by-commit disposition, and runtime/source hash comparison are recorded.
Independent review and GitHub handoff follow the required checks. Owner smoke
and release authorization remain pending.
