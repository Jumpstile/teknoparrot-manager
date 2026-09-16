# TPM Support Posture Corpus and CHD/Layout Slice Contract

## 1. Slice name

- Name: Full TeknoParrot support posture corpus, classification, and CHD/layout implementation infrastructure
- Contract ID: TPM-SUPPORT-POSTURE-001
- Issue/PR: PR #321 remediation control board
- Authorized branch: `fix/rc8-release-blockers`
- Authorized starting HEAD: `1599707f38b509c7a2036c06ea6ed92c43626981`

## 2. Owner report IDs included

- IDs: SUPPORT-POSTURE-001; skylinekiller CHD/layout owner finding
- Exact owner-visible failure: newer TeknoParrot games containing CHD media and ordinary game files were not pointed at the correct directory by TPM; the user had to select the CHD manually in TeknoParrotUI.
- Current source evidence: `Get-GameFiles` recognizes `.exe`, `.elf`, `.iso`, `.gcm`, `.gcz`, `.bin`, `.e4`, `.zip`, `.xbe`, and `.dll`, but not `.chd`.

## 3. Explicit exclusions

- Owner IDs not included: all unrelated PR #321 owner rows.
- Product behavior is not changed by this infrastructure slice.
- Registration and path-repair discovery behavior remain unchanged.
- No `.chd` addition to `Get-GameFiles`.
- No `Register-GamesLegacy` change.
- No `Repair-GamePathsLegacy` change.
- No owner-runtime or TeknoParrotUI-owned field writes.
- No package, runtime, owner-smoke, Arcade, wiki, commit, push, merge, tag, publish, certification, or release action.

## 4. Behavior contract

- Current failure: CHD files are omitted from the existing game-file discovery path used by registration and path repair. The current source cannot prove the correct relationship between a CHD, a launcher, an executable, and a content directory.
- Implemented scope: offline corpus snapshot tooling and deterministic support-posture classification/report generation. The tooling reads supplied sources and writes only to an explicitly supplied output root.
- The generated corpus classifies each profile as `AUTOMATED_SAFE`, `REVIEW_MANUAL`, `BLOCKED_UNSUPPORTED`, or `UNCLASSIFIED`.
- `AUTOMATED_SAFE` requires exact profile identity, one unambiguous target, approved-root containment, non-reparse/inaccessible/protected checks, no conflicting candidate, and no silent write to a TeknoParrotUI-owned field.
- `REVIEW_MANUAL` preserves source state and records beginner-safe TeknoParrotUI instructions when the target or media relationship is ambiguous, missing, or vendor-owned.
- `BLOCKED_UNSUPPORTED` fails closed with a stable reason when profile metadata, path safety, ownership, or evidence is insufficient.
- `UNCLASSIFIED` is retained for incomplete development inputs and is a release-gate failure.
- CHD presence alone never proves that a CHD is the TeknoParrot launch target. Profile metadata, pinned evidence, and layout observations must establish that relationship.

## 5. Source/function ownership

- Implemented source file: `scripts/New-TpmSupportPostureCorpus.ps1`.
- Current source boundaries retained for characterization: `Get-GameFiles`, `Register-GamesLegacy`, `Repair-GamePathsLegacy`, `Build-ProfileIndex`, `Get-PrimaryExecutableName`, `Get-ExeAlternatives`, `Build-DatIndexFromStream`, `Get-TeknoParrotProfileSet`, and `Get-GameProfileSchemaDrift`.
- Implemented tooling functions cover installed/upstream profile ingestion, UserProfiles observations, optional DAT summaries, fixture layout observations, classification, and JSON/Markdown generation.
- Owning subsystem: library support evidence, corpus reporting, and release posture classification.

## 6. Tests required

- Characterization coverage for the current `.chd` omission from `Get-GameFiles`.
- Corpus-tool coverage for deterministic ordering, duplicate profile stems, malformed XML records, raw XML hashes, source identity, and generated-output reproducibility.
- Classification coverage for exactly one posture per profile and the zero-`UNCLASSIFIED` release calculation.
- CHD/layout fixture coverage for all taxonomy classes in the implementation requirements.
- Path-safety coverage for out-of-root, inaccessible, protected, and reparse-backed candidates where the host permits a real reparse fixture.

## 7. Tests required after implementation

- Focused behavior tests: `Tests/SupportPostureCorpus.Tests.ps1`.
- Focused corpus/CHD fixtures and deterministic JSON/Markdown assertions.
- Registration and repair source regression checks prove this slice does not alter existing discovery callers.
- Full main Pester suite and `SupportPackage.Tests.ps1` remain required because remediation documentation and support evidence are touched.
- Static/procedure gates: parser, PSScriptAnalyzer, ASCII, InjectionHunter disposition-backed inventory, `git diff --check`, generated-artifact scan, and the permanent TPM quality gate.

## 8. Documentation/report updates required

- Control board: record owner requirement `SUPPORT-POSTURE-001`, this implementation contract, source/test evidence, and remaining runtime gate.
- Remediation report: record exact script/test boundaries, generated matrix evidence, fixture totals, and runtime proof status.
- Architecture: add the support-posture corpus precedence, classification, CHD/media inference, ownership, and fail-closed path contract.
- Changelog/user docs: unchanged unless this later slice changes user-facing registration behavior; no universal-support claim is authorized.
- Generated artifacts: support corpus JSON, raw XML hash manifest, fixture coverage JSON, and Markdown matrix are produced from one pinned snapshot and are not hand-edited.

## 9. Permanent procedure IDs affected

- TPM-TRACE-001: every future source hunk must map to SUPPORT-POSTURE-001, this contract, the control board, and the reconciliation report.
- TPM-OWNER-001: owner-runtime evidence remains mandatory for representative CHD/media layouts.
- PR #321 fail-closed remediation gate: no release closure while the matrix is incomplete, stale, or unverified.

## 10. Runtime smoke checklist

- Exact future packaged behavior: representative CHD-only, same-folder mixed, content-subfolder, nested, multiple-CHD, missing-CHD, and wrong-directory cases produce the planned safe or review result.
- TeknoParrotUI-owned fields remain untouched by TPM; manual selection instructions identify the exact user action.
- Required source/package identity: a rebuilt package from the authorized implementation SHA, with the corpus snapshot and generated matrix tied to that evidence set.
- Evidence artifacts: profile snapshot, raw XML hash manifest, generated JSON, generated Markdown, fixture results, owner runtime logs/screenshots, and final gate report.
- Owner/runtime authorization: not authorized in this implementation slice.

## 11. Stop condition

Stop when the script, focused tests, generated artifact checks, source-hunk mapping, and required local gates are complete. Do not add `.chd` to registration or repair discovery, write TeknoParrotUI-owned state, or widen this slice into runtime behavior.

## 12. Forbidden actions

No `.chd` registration/repair behavior change, no TeknoParrotUI-owned writes, no package creation, owner smoke, Arcade work, wiki update, commit, push, hosted CI, merge, tag, publish, certification, or release-ready decision. Do not treat the historical 541-profile schema comment, the dynamic ProfileSet filename list, or the Eggman DAT as a complete authoritative support matrix.

## 13. Commit/package authorization status

- Commit authorized: No
- Package authorized: No
- Release/certification authorized: No
- Hosted CI authorized: No for this implementation slice; a later run requires local gates, an exact-head checkpoint, and explicit ChatGPT authorization.
