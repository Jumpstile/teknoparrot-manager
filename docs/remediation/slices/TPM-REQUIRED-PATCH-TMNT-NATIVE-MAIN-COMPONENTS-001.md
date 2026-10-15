# TMNT 1.59 Main-component restoration slice contract

## 1. Slice name

- Name: two exact Main-source native component restorations for Teenage Mutant Ninja Turtles 1.59
- Contract ID: `TPM-REQUIRED-PATCH-TMNT-NATIVE-MAIN-COMPONENTS-001`
- Issue/PR: Issue #351; no numbered PR #321 owner row is assigned.
- Staging base: commit `4ee514820e6f4445a592602e2ec992677bf9cef1`, branch `fix/rc8-recipe-followup-20261015`.

## 2. Owner report IDs included

- IDs: Issue #351 owner-authorized request for the two exact missing Main components. No numbered PR #321 owner report ID is assigned.
- Exact failure: the catalog has no exact Main `CreateFile` recipe for `TMNT_Data/Plugins/x86_64/OrenVid.dll` or `TMNT_Data/Plugins/x86_64/PK-UnityPlugin.dll` under the pinned TMNT 1.59 executable identity. This does not establish that either file is absent from an installed game.

## 3. Explicit exclusions

- Owner IDs not included: no numbered PR #321 row is changed.
- No BepInEx installation/configuration, managed-plugin changes, automatic configuration, hardware predicate, DLL replacement, source download, runtime install, game launch, payload execution, package, release, or publication.
- No claim that the pair is atomic, required together, compatible, a graphics fix, or sufficient for complete setup or gameplay.
- Existing BepInEx/plugin/config sibling files remain outside the recipes and must be preserved.

## 4. Behavior contract

- Current failure: the 62-entry catalog does not provide absent-only restoration for the two source-pinned native Main components in this exact build.
- Expected behavior: append two independent schema-3 `CreateFile` recipes to the existing catalog. Each binds `TMNT`, build `Teenage Mutant Ninja Turtles (1.59)(2021-07-26)(USA)[Raw Thrills PC][TP]`, `TMNT.exe` SHA-256 `11AEDEEE2136DA3BF69392B5FE76818707BDD8E413AE99F829F394F8B80B295F`, the exact Main ZIP member, source size/SHA-1/SHA-256, and one matching target. `BeforeState` is `Absent`; exact after-state is a no-op; unknown present bytes are refused; undo is bound to the transaction receipt and created file identity.
- Forbidden regressions: no target replacement, no automatic parent-directory creation, no inferred prerequisites or hardware, no weakening of catalog/source/path/hash/backup/receipt guards, no changes to `TeknoParrot-Manager.ps1`, and no required-patch engine body change. The engine catalog SHA-256 header pin may change only to bind the resulting catalog bytes.
- Design boundary: these are two independently applicable missing-Main-component repairs, not an atomic pair, plugin installation, configuration repair, or setup/game-readiness result.

## 5. Source/function ownership

- Files: `tools/required-patches/fragments/tmnt-native-main-components-20261015.json`, `scripts/TpmRequiredPatchRecipes.json`, the required-patch catalog SHA-256 header pin, the focused TMNT portable test, affected integrated census assertions, and this slice/inventory/board/reconciliation mapping.
- Exact source evidence: the owner-reviewed private proof binds both unique Deflate/8 Main members and the unique `TMNT.exe` member; the executable SHA-256 matches the existing `tmnt-bepinex-plugin-restore` catalog anchor. Private source paths remain outside the repository.
- Engine boundary: existing schema-3 `CreateFile`/`BeforeState=Absent` behavior only; no engine policy change.
- Owning subsystem: Issue #351 required-patch catalog; no installer framework.

## 6. Tests required before implementation

- Exact source-member and executable pins are independently verified in the owner-reviewed source proof.
- Preserve the 62-entry base catalog and all existing entries before append; verify the catalog anchor and operation census.

## 7. Tests required after implementation

- Run only the focused TMNT portable suite with explicit Pester 5.7.1 on PowerShell 7 and Windows PowerShell 5.1, capturing actual child exits, separate stdout/stderr, and NUnit XML.
- The suite must cover independent synthetic ZIP staging, absent apply/read-back, exact-after no-op, unknown-present refusal, wrong-executable refusal before mutation, receipt-bound undo to absence, same-byte foreign-object undo refusal, and sibling configuration/plugin preservation.
- Update the affected integrated census to 64 entries / 64 unique IDs / 56 `CreateFile` / eight `ReplaceFile`; preserve 23 profile identities and the historical 58-entry fragment pins.
- Root owns the combined full-suite, static/security, permanent-procedure, exact-head CI, package, and owner-runtime gates; none are claimed by this slice.

## 8. Documentation/report updates required

- Control board and reconciliation: add this separate Issue #351 slice, source facts, test receipts, and explicit unverified owner/runtime status.
- Preserve the historical 58-, 61-, and 62-entry checkpoints and all existing fragment/source pins.
- Broad user-guide and release-document changes are outside this bounded staging slice; no current docs may claim setup, compatibility, or gameplay completion.
- Hunk mapping: two fragment/catalog rows, catalog-pin line, affected census assertions, focused test, and mapped status -> Issue #351 / this contract / `TPM-TRACE-001`, `TPM-EVIDENCE-001`, `TPM-TRUTH-001`, `TPM-OWNER-001`, `TPM-OWNER-002`, `TPM-OWNER-003`, and `TPM-AUTH-001`.

## 9. Permanent procedure IDs affected

- `TPM-TRACE-001`: map every changed hunk to Issue #351, this contract, and its test/procedure evidence.
- `TPM-EVIDENCE-001`: prove both exact metadata and absent-only transaction behavior.
- `TPM-TRUTH-001`, `TPM-OWNER-001`, `TPM-OWNER-002`, `TPM-OWNER-003`: keep source identity separate from installed-target state, setup, gameplay, and owner acceptance.
- `TPM-AUTH-001`: this lane does not commit, push, package, release, update the live wiki, or run owner runtime.

## 10. Runtime smoke checklist

- Exact packaged behavior: owner must test the exact supported build and each component independently after optional absent-only restoration.
- Required source/package identity: exact TMNT 1.59 executable and Main ZIP member identities.
- Evidence artifacts: owner-run receipt, installed target read-back, sibling-state record, and separate visual/gameplay observations.
- Owner/runtime authorization: pending; this work runs no game or payload.

## 11. Stop condition

Stop after the two recipe rows, focused dual-engine tests, mapped report updates, and local source/pin checks are complete and reviewable. Root owns combined gates and any later integration; owner runtime and release gates remain separate.

## 12. Forbidden actions

No unrelated cleanup, broad rewrite, commit, push, merge, package, tag, release, live wiki update, game launch, or owner-runtime test.

## 13. Commit/package authorization status

- This staging lane may not commit or publish.
- Package authorized: No.
- Release/certification authorized: No.

### Focused verification, 2026-10-15 UTC

Root reviewed five TMNT cases, seventeen existing required-patch cases, and two catalog cases per engine with Pester 5.7.1 on Windows PowerShell 5.1 and PowerShell 7. All selected cases passed. The filtered Main wrapper returned exit 1 solely because 1,471 intentionally excluded cases tripped its generic zero-NotRun condition; the independent XML review confirmed seventeen successes and zero failures in each engine. This is focused evidence, not a new full-suite or runtime result. Both TMNT focused workers exited 0. The original 62 recipe entries and order, engine body, and product Main remain unchanged. Catalog: 64 entries, 56 CreateFile, eight ReplaceFile, 23 profiles. Source integration, owner runtime, and release gates remain separate.
