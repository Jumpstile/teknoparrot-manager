# Main-component restoration slice contract

## 1. Slice name

- Name: exact Main-source component restorations for Hummer, Hummer Extreme, and Primeval Hunt
- Contract ID: `TPM-REQUIRED-PATCHES-MAIN-COMPONENTS-001`
- Issue/PR: Issue #351; no numbered PR #321 owner row is assigned.
- Staging base: `3c93d383f0a8091bf5d6890acb176c285816a82f`; staging branch `review/rc8-expanded54-20261015`.
- At this slice's integration checkpoint: 56 entries / 21 exact identities; this slice contributes 30 `CreateFile` entries. Current staging after the separate Infinity slice: 58 entries / 22 identities, 50 `CreateFile` / eight `ReplaceFile`; catalog SHA-256 `F86F09A8BD2749DC9C4531CD1D00A69BF07D85B14A8D281D33767732ED5B720A`, engine SHA-256 `7AFAE497F5EFED0BE5F94497D4A7A5C25C073743485B700A7498B1A34681F6E4` (catalog pin only).

## 2. Owner report IDs included

- IDs: Issue #351 owner-authorized request for the remaining source-backed Main-component recipes. No numbered PR #321 owner report ID is assigned.
- Exact failure: the catalog lacks restoration recipes for 30 guide-required component paths whose exact bytes are present in the matching Main builds. This statement does not claim a reproduced gameplay failure.

## 3. Explicit exclusions

- Owner IDs not included: no numbered PR #321 rows are changed.
- No Cross Raid base-shader restoration, drivers/loaders, managed plugins, other guide families, source downloads, release/package work, runtime install, game launch, or game payload execution.
- Hummer Extreme frame-count requirements and Primeval Hunt's exact `ElfLdr2` library-copy identity remain held. Primeval's modern NVIDIA fog caveat remains applicable.
- No shader-set atomicity, visual compatibility, complete setup, or gameplay result is claimed.

## 4. Behavior contract

- Current failure: a supported exact game build may lack one of these required Main components, while the current recipe catalog has no exact absent-file restoration for that path.
- Expected behavior: add 14 Hummer 1.0, 14 Hummer Extreme 1.0, and two Primeval Hunt 1.0 single-file `CreateFile` recipes. Each binds one exact profile/build/executable, one named local Main ZIP member, exact size/SHA-1/SHA-256, and one target path. Creation is allowed only when the target is absent; exact after-state is a no-op; every other present state is refused. Undo remains bound to the recipe receipt and created file identity.
- Forbidden regressions: no target replacement, no automatic parent-directory creation, no broad or inferred hardware predicate, no executable self-patch opt-in, no weakening of path/hash/backup/receipt guards, no claim of game readiness.
- Design boundary: these entries restore known Main components; they do not install a separate graphics patch or certify the whole shader set.

## 5. Source/function ownership

- Files: `scripts/TpmRequiredPatchRecipes.json`, `scripts/TpmRequiredPatchEngine.ps1` (catalog SHA-256 pin only), central required-patch assertions, the accepted native fragment/test, CI path list, user/architecture docs, and this slice/report/inventory.
- Frozen fragment SHA-256: `54AB378F9F13213F67C47A628DDEFE3AA0F4FEB8BE2E1BCE51B87818E247D38E`.
- Frozen portable suite SHA-256: `673D1C434033E1076CA4BE6174D535B5A1C0353651B9EA6D1B63EEF3340C88C7`.
- Engine boundary: `Read-TpmRequiredPatchCatalog`, `New-TpmRequiredPatchPayloadStage`, `Get-TpmPatchPlan`, `Invoke-TpmCatalogPatch`, and `Undo-TpmCatalogPatch`; no engine policy changes.
- Owning subsystem: Issue #351 required-patch catalog; no installer framework.

## 6. Tests required before implementation

- Root-accepted frozen-handoff evidence: the standalone 152-case suite passed 152/152 under Pester 5.7.1 on PowerShell 7.6.7 and Windows PowerShell 5.1.26100.9549 against the frozen24 staging engine/catalog.
- Preserve the accepted fragment/test bytes; do not regenerate or broaden their source facts.

## 7. Tests required after implementation

- Run the standalone 152-case suite under explicit Pester 5.7.1 on PowerShell 7 and 5.1 against the integrated catalog and staging engine.
- Run the central 56-entry count/pin test and verify 30 exact IDs, 21 identities, 48 CreateFile operations, and eight ReplaceFile operations.
- Run bounded JSON/catalog import, PowerShell parse/ASCII/privacy, and engine-pin-only checks. Root owns the later full canonical gate.

## 8. Documentation/report updates required

- Control board: separate Issue #351 Main-component restoration addendum; preserve the historical native-five slice and frozen24 snapshot.
- Reconciliation: record the 56-entry staging checkpoint and exact receipt hashes; retain the frozen24 checkpoint as historical.
- User and architecture docs: describe missing-component repair only, not new patch installation or complete setup.
- Hunk mapping: catalog rows, catalog count/ID assertions, CI inclusion, docs, slice, and inventory -> Issue #351 / `TPM-REQUIRED-PATCHES-MAIN-COMPONENTS-001` / `TPM-TRACE-001`, `TPM-EVIDENCE-001`, `TPM-TRUTH-001`, `TPM-OWNER-001`, `TPM-OWNER-002`, `TPM-OWNER-003`; user wording -> `TPM-UX-001` and `TPM-UX-002`.
- Changelog describes the current RC8 candidate only; no release version, tag, or publication is authorized.

## 9. Permanent procedure IDs affected

- `TPM-TRACE-001`: map every integration hunk to Issue #351, this contract, and the relevant procedure.
- `TPM-EVIDENCE-001`: verify exact metadata and lifecycle behavior with focused tests.
- `TPM-TRUTH-001`, `TPM-OWNER-001`, `TPM-OWNER-002`, `TPM-OWNER-003`: keep source/test evidence distinct from owner runtime and readiness.
- `TPM-UX-001`, `TPM-UX-002`: keep user-facing repair and limitation wording accurate.
- `TPM-AUTH-001`: this staging lane did not commit, push, package, tag, release, update the live wiki, or run owner runtime. Root owns final gates and may commit/push a scoped review PR after gates; this does not authorize release, tag, main merge, or runtime activity.

## 10. Runtime smoke checklist

- Exact packaged behavior: owner must test the exact supported game build after optional absent-only restoration.
- Required source/package identity: exact executable, local Main ZIP name, and recipe member hashes.
- Evidence artifacts: owner-run receipt, installed target readback, visual/gameplay observations, and separate setup-state record.
- Owner/runtime authorization: pending; this staging work executes no game or payload.

## 11. Stop condition

Stop after the 30 entries are integrated into the authorized staging tree, their exact bytes/counts and focused behavior tests pass, documentation and mappings are synchronized, and the staging diff is reviewable. Owner runtime, release, and merge gates remain separate.

## 12. Forbidden actions

This staging lane does not run the full canonical suite or commit, push, merge, package, tag, release, live wiki update, or owner-runtime test. Root owns final quality gates and may commit/push a scoped review PR after gates. Release/tag/main-merge and owner-runtime authorization remain separate.

## 13. Commit/package authorization status

- This staging lane may not commit or publish; root may authorize source commit/push/scoped review PR after final gates.
- Package authorized: No.
- Release/certification authorized: No.
