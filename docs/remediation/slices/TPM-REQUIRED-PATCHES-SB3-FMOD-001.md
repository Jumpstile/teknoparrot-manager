# SB3 FMOD Main-component restoration slice contract

## 1. Slice name

- Name: exact Main-source SB3 x64 FMOD component restorations
- Contract ID: `TPM-REQUIRED-PATCHES-SB3-FMOD-001`
- Issue/PR: Issue #351; no numbered PR #321 owner row is assigned.
- Staging base: `3c93d383f0a8091bf5d6890acb176c285816a82f`; staging branch `review/rc8-expanded54-20261015`.
- At this slice's integration checkpoint: 56 entries / 21 exact identities; this slice contributes two `CreateFile` entries. Current staging after the separate Infinity slice: 58 entries / 22 identities, 50 `CreateFile` / eight `ReplaceFile`; catalog SHA-256 `F86F09A8BD2749DC9C4531CD1D00A69BF07D85B14A8D281D33767732ED5B720A`, engine SHA-256 `7AFAE497F5EFED0BE5F94497D4A7A5C25C073743485B700A7498B1A34681F6E4` (catalog pin only).

## 2. Owner report IDs included

- IDs: Issue #351 root-authorized request to integrate the two exact Main-source SB3 FMOD component restorations. No numbered PR #321 owner report ID is assigned.
- Exact failure: the catalog has no absent-only restoration for the two guide-required x64 FMOD member paths present in the exact Main build. This does not claim a reproduced launch or audio failure.

## 3. Explicit exclusions

- Owner IDs not included: no numbered PR #321 rows are changed.
- No other plugin-lane catalog/fragment/test/history, no SB3 plugin or BepInEx installation, no source package acquisition, no FMOD version metadata probe, no audio/gameplay run, and no complete setup claim.
- FMOD pair compatibility, pair completeness, and atomic installation remain unverified. Each DLL is a separate transaction; the sibling is not a prerequisite and is left untouched.
- No other recipe family, Cross Raid base restoration, engine behavior change, release/package, or runtime mutation is included.

## 4. Behavior contract

- Current failure: a supported SB3 1.91 x64 installation may lack either exact Main component while the recipe catalog has no restoration for that absent target.
- Expected behavior: add exactly two independent one-file `CreateFile` recipes for `fnfmega_Data/Plugins/x86_64/fmod64.dll` and `fmodstudio64.dll`. Each binds profile `SB3`, exact executable hash, exact named Main ZIP member, size/SHA-1/SHA-256, and target. An absent target may be created; exact after-state is a no-op; other present bytes refuse. Existing target parents must already be safe directories. Undo uses each operation's own receipt and file identity.
- The fragment preserves the exact catalog `BuildName` `Super Bikes 3 (1.91 x64)(2021-10-01)[Raw Thrills][TP]` and the exact Main `SourceSet` `Super Bikes 3 (1.91 x64)(2021-10-01)[Raw Thrills PC][TP].zip`. The source ZIP's `PC` label is not normalized to the guide build label.
- Forbidden regressions: do not add sibling-file or version prerequisites that the evidence cannot prove; do not group the two operations into one atomic recipe; do not create parents, overwrite present bytes, infer hardware, or claim FMOD version/game compatibility.

## 5. Source/function ownership

- Files: `scripts/TpmRequiredPatchRecipes.json`, `scripts/TpmRequiredPatchEngine.ps1` (catalog SHA-256 pin only), central count/ID assertions, the accepted FMOD fragment/test/boundary, CI path list, user/architecture docs, and this slice/report/inventory.
- Frozen fragment SHA-256: `0CC045CB454D802804E46FC25F049687164F48E55ACACFC3D38BA63AB528E418`.
- Frozen portable suite SHA-256: `D288325EB8BAD7D13C80499EB3E45091E99BBB89AA0E09C825C1692B5611FA05`.
- Accepted boundary note SHA-256: `EA90F3C8E4EF90061D34E350E65275CCC1557CC49AF7DCF2450A825CDAA2E7A4`.
- Independent exact-Main member receipt: `SB3-Fmod-Main-Independent-Member-Proof-20261015T071758Z.json`, SHA-256 `553D52FB96ABB68DD610D21BE2FF0455C2162AA44762CC0A720F4F17F0FCFCE5`.
- Owning subsystem: Issue #351 required-patch catalog; no FMOD setup or plugin installer.

## 6. Tests required before implementation

- Root-accepted frozen24 results: the standalone FMOD suite passed 2/2 under Pester 5.7.1 on PowerShell 7 and Windows PowerShell 5.1.
- Preserve the exact accepted fragment and test bytes; only its two `Entries` are appended to the central catalog.

## 7. Tests required after implementation

- Run the standalone 2-case suite under explicit Pester 5.7.1 on PowerShell 7 and 5.1 against the integrated 56-entry catalog.
- Run the central 56-entry count/pin test and verify both FMOD IDs are present exactly once.
- Run bounded catalog import, parse/ASCII/privacy, and catalog-pin checks. Root owns the later full canonical gate.

## 8. Documentation/report updates required

- Control board: separate Issue #351 SB3 FMOD addendum; keep the plugin lane's other files and the historical 24-entry snapshot unchanged.
- Reconciliation: record the two exact Main entries and the remaining pair/version/runtime limits.
- User/architecture wording: these entries restore a missing component from Main; they do not validate FMOD version, pair compatibility, SB3 plugin/BepInEx setup, or gameplay.
- Hunk mapping: two catalog rows, central count/ID assertions, CI inclusion, docs, slice, and inventory -> Issue #351 / `TPM-REQUIRED-PATCHES-SB3-FMOD-001` / `TPM-TRACE-001`, `TPM-EVIDENCE-001`, `TPM-TRUTH-001`, `TPM-OWNER-001`, `TPM-OWNER-002`, `TPM-OWNER-003`; user wording -> `TPM-UX-001` and `TPM-UX-002`.
- Changelog describes the current RC8 candidate only; no release version, tag, or publication is authorized.

## 9. Permanent procedure IDs affected

- `TPM-TRACE-001`: map each recipe/test/doc hunk to Issue #351 and this contract.
- `TPM-EVIDENCE-001`: exact source pins and absent/no-op/refusal/undo behavior.
- `TPM-TRUTH-001`, `TPM-OWNER-001`, `TPM-OWNER-002`, `TPM-OWNER-003`: source/test proof is not installed-version, setup, or owner-runtime proof.
- `TPM-UX-001`, `TPM-UX-002`: describe the limited restoration truthfully.
- `TPM-AUTH-001`: this staging lane did not commit, push, package, tag, release, update the live wiki, or run owner runtime. Root owns final gates and may commit/push a scoped review PR after gates; this does not authorize release, tag, main merge, or runtime activity.

## 10. Runtime smoke checklist

- Exact packaged behavior: owner verifies the exact SB3 1.91 x64 build and installed component state.
- Required source/package identity: exact executable, named Main ZIP, and each member's size/SHA-1/SHA-256.
- Evidence artifacts: owner-run receipt, target readback, separate DLL version/compatibility evidence, and audio/gameplay observation if claimed.
- Owner/runtime authorization: pending; this staging work executes no game or DLL.

## 11. Stop condition

Stop after the two accepted entries are integrated, both portable tests pass on the integrated catalog, exact metadata and mappings are recorded, and the staging diff is reviewable. Do not infer pair compatibility or full setup.

## 12. Forbidden actions

This staging lane does not run the full canonical suite or commit, push, merge, package, tag, release, live wiki update, or owner-runtime test. Root owns final quality gates and may commit/push a scoped review PR after gates. Release/tag/main-merge and owner-runtime authorization remain separate.

## 13. Commit/package authorization status

- This staging lane may not commit or publish; root may authorize source commit/push/scoped review PR after final gates.
- Package authorized: No.
- Release/certification authorized: No.
