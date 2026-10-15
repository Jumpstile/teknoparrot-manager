# KOF Maximum Impact Regulation A Main-component restoration slice contract

## 1. Slice name

- Name: four independent absent-only WineD3D Main-file restorations for KOF Maximum Impact Regulation A
- Contract ID: `TPM-REQUIRED-PATCH-KOF-MAIN-COMPONENTS-001`
- Issue/PR: Issue #351; related PR #321 remediation control board, no numbered PR #321 owner-report row assigned.
- Staging base: commit `54a32afad1d070f1744b0081c84abc83d8c5edca`; branch `feature/rc8-kof-main-restorations-20261015`.

## 2. Owner report IDs included

- IDs: Issue #351 authorized recipe follow-up, scoped here to four exact KOF Main-file restorations.
- Exact failure: the current 64-entry catalog has no absent-only recipe for these four documented game-folder DLL targets. This does not establish that any target is absent in an installed game.

## 3. Explicit exclusions

- No graphics-driver/system installation, Windows directory or PATH writes, external WineD3D download, executable patch, hardware predicate, configuration edit, game launch, payload execution, runtime installation, or owner/ARCADE test.
- No atomic four-file set, inferred per-API prerequisite, launch readiness, compatibility, complete setup, graphical behavior, or gameplay result is claimed.
- No full Main archive hash is claimed; recipes select only the exact named local Main ZIP members.
- No engine-body or `TeknoParrot-Manager.ps1` change. The engine catalog SHA-256 constant may change only to pin the resulting catalog bytes.

## 4. Behavior contract

- Expected behavior: add four independent schema-3 `CreateFile` recipes for profile `KingofFightersMaximumImpactRegulationA`, build `King of Fighters Maximum Impact Regulation A (2007)[Taito Type X2][TP]`, executable `game.exe` SHA-256 `CC40C926E19F17DD373C87A3D83120CB6C22C2F3CA9B492E28A6178813F6256F`, and the four exact root Main members `d3d8.dll`, `d3d9.dll`, `ddraw.dll`, and `wined3d.dll`.
- Each recipe binds one Main ZIP member, source length/SHA-1/SHA-256, and one matching game-root target. The guide spells one item `dddraw.dll`; exact official and Main sources identify `ddraw.dll`, so the catalog uses `ddraw.dll` explicitly.
- Each target is created only from an absent state. Exact after-state is a no-op; every other present state is refused. Undo is receipt-bound to the created file identity. The four entries have no shared exclusive group, hardware predicate, prerequisite, or all-or-nothing claim.
- Forbidden regressions: replacing existing files, widening source selection, adding unverified prerequisites, changing engine policy, or claiming the installed game matches the source proof.

## 5. Source/function ownership

- Files: `tools/required-patches/fragments/kof-main-wined3d-components-20261015.json`, `scripts/TpmRequiredPatchRecipes.json`, the catalog SHA-256 pin line in `scripts/TpmRequiredPatchEngine.ps1`, central count assertions, `Tests/TpmRequiredPatchKofMainComponents.Tests.ps1`, its explicit CI path, the paired inventory, control board, and reconciliation report.
- Private source evidence: `KOF-WineD3D-10.16-Official-Source-Proof-Root-20261015.json` SHA-256 `BD4A7FCA7A4659EDA2EB1BD8E054D5658C67EE3B755E0A4645AB3ED5C0BE433D`; `KOF-Exact-Main-Root-Member-Proof-v2-20261015.json` SHA-256 `FF5991A81A2176F8BF0614DBCA8DE68D2F5851845308DD7871EC4AAED75B6BE1`.
- The four Main member bytes match the official WineD3D 10.16 x86 members; all four PE machine values are `014C`. The Main ZIP is the only runtime source selected by these recipes.
- Engine boundary: existing schema-3 `CreateFile` / `BeforeState=Absent` behavior; no engine policy changes.

## 6. Tests required before implementation

- The approved private source proofs above bind the exact `game.exe` identity and all four unique root members, lengths, SHA-1/SHA-256 pins, and official 10.16 x86 byte matches.
- Preserve the exact 64-entry base catalog (SHA-256 `214415946FBD9C64EE37A673119A43DE9334F54F42E4B7910DF3784F6908D250`) and all existing entry order/content before append. Baseline census: 64 entries, 23 profiles, 56 `CreateFile`, eight `ReplaceFile`.

## 7. Tests required after implementation

- Prepare a five-case portable Pester suite, each case covering all four recipe entries where applicable: (1) exact metadata/catalog pins and absent-only contract; (2) exact-member staging from a synthetic local Main ZIP; (3) absent apply/read-back, exact-after idempotency, receipt undo, unknown-present refusal, and sibling preservation; (4) wrong-executable refusal before mutation; (5) same-byte foreign-file-object refusal on undo.
- Expected combined census after the separate MKDX entry: 69 unique entries, 25 ProfileIds, 61 `CreateFile`, eight `ReplaceFile`.
- Add the new standalone suite to the explicit CI Pester path list and update existing current-census assertions.
- Per Root instruction, do not run tests in this lane. Root owns the authorized final workers and combined gates.

## 8. Documentation/report updates required

- Update the PR #321 control board and reconciliation report with the mapped scope and current combined 64-to-69 census, preserving historical 64-entry and earlier snapshots.
- Update the paired specification/system-invariant inventory and this slice with exact Main member pins, typo resolution, safety boundary, and test plan.
- Update only current required-patch census references; do not rewrite historical snapshots. No release-version, release, package, runtime, or compatibility claim.
- Hunk mapping: four fragment/catalog entries, one engine pin line, exact census assertions, focused test/CI route, paired inventory, slice, board, and reconciliation -> Issue #351 / this contract / `TPM-TRACE-001`, `TPM-EVIDENCE-001`, `TPM-TRUTH-001`, `TPM-OWNER-001`, `TPM-OWNER-002`, `TPM-OWNER-003`, and `TPM-UX-001/002` for scope wording.

## 9. Permanent procedure IDs affected

- `TPM-TRACE-001`: map every changed hunk to Issue #351, this contract, and its test.
- `TPM-EVIDENCE-001`: preserve exact member/executable pins and test source staging and transactional boundaries.
- `TPM-TRUTH-001`, `TPM-OWNER-001`, `TPM-OWNER-002`, `TPM-OWNER-003`: keep source identity distinct from installed-target state, setup, compatibility, gameplay, and owner acceptance.
- `TPM-UX-001`, `TPM-UX-002`: keep any user-facing repair statement bounded to missing-file restoration only.

## 10. Runtime smoke checklist

- Exact packaged behavior: separately authorized owner must test the exact supported build and each optional absent-only restoration; no owner runtime is performed here.
- Required source identity: exact guide profile/build, `game.exe` SHA-256, local Main ZIP member and hashes.
- Evidence artifacts: owner-run receipt, target read-back, and separate graphics/setup/gameplay observations.
- Owner/runtime authorization: not included; this work does not execute a game or payload.

## 11. Stop condition

Stop after the four rows, five-case suite, current-census/CI/document mapping, and byte/pin freeze are reviewable. Root owns tests and final gates. Do not widen this slice.

## 12. Forbidden actions

No source downloads, binary/archive addition, system/driver writes, live game changes, payload execution, full test run, package, commit, push, merge, release, wiki publication, or ARCADE work.

## 13. Commit/package authorization status

- Commit/push: not authorized.
- Package: not authorized.
- Release/certification/owner runtime: not authorized.

### Root focused verification, 2026-10-15 UTC

The combined source has69entries/25profiles/61CreateFile/eightReplaceFile. All prior64 entries and order, the engine body and product Main are unchanged. Root's independent XML review at2026-10-15T18:14:26Z verified34 specified cases per engine: KOF5, MKDX5, TMNT5, catalog2 and existing required-patch integration17. Initial fixture failures remain preserved. KOF's corrected five cases passed within a batch whose three MKDX fixture failures were subsequently corrected; the final MKDX-only five-case and Main17 workers exited0 in both engines. The focused proof is1826663DB68DC6F63B9CBDB280F9EE5183D5751E7BF058C5D0F8EB0E15B2F03E. This does not claim a new full-suite, package, graphics compatibility or owner-runtime result. Root source commit/push and integration follow the existing authorized workflow; no lane performed publication. No build or ZIP copy is authorized by this source verification.