# Native required-patch recipe expansion -- slice contract

## 1. Slice name

- Name: evidence-backed native executable, graphics, timing, and audio recipes for Issue #351
- Contract ID: `TPM-REQUIRED-PATCHES-NATIVE-001`
- Issue: #351; parent integration owner controls final integration and publication.
- Base: public commit `9a9ac19e87bb2da10c33d1d387665f9b87b412bc`; branch `feature/rc8-recipes-native-20261015`.
- Starting catalog: 13 entries; do not duplicate those identities. This slice adds five entries across Sonic Dash Extreme, Cross Raid 1.05 Ver A, and VF5R 1.001; resulting candidate catalog has 18 entries across 15 builds.

## 2. Owner request and source evidence

- Owner request: explicit Issue #351 request to continue source-backed native remediation beyond the curated guide register and safely support exact self-executable before/after states when proven. No numbered PR #321 owner row is assigned.
- Sonic Dash Extreme self-executable timing-patch bytes: exact Main member `exe/SonicDash_R_Ring.exe`, 5,947,392 bytes; before SHA-256 `47B6F1186C734DD795D1AFC95D070494436502A2B2419ADE9F19A78D7B431A38`; after SHA-256 `BCA788A62FD32681D049F7AFDE456F6AD12F9030CED4E1C3CFD81C3A925EDD9E`. Trusted receipts: `Sonic-Exact-Original-Patched-Main-Identity-20261015.jsonl` and `Mars-Sonic-Python-Source-Verification-20261015.jsonl`. The separate author ZIP `SonicDashExtremPatch60fps-60Hz.zip` uses unsupported Zstandard method 93; the exact patched Main member uses method 8 and is the recipe source.
- Shining Force: Cross Raid profile `ShiningForceCrossRaid`, official profile revision 12, Main build `Shining Force - Cross Raid (1.05 Ver A)(2011-08-03)(JPN)[Sega RingEdge][TP]`; exact `project_f-ringedge-release.exe` SHA-256 `82E66635A9A91CEC59721DB7BD9258464F70C44377BA707FFCB51EA2D3DB9317`. Main `rom/shader.farc` is 9,173,328 bytes / SHA-256 `66E0CC00E84C01F6E77E6B446A019212EBD27610FDD81CA866648C5E97E80933`. Exact AMD/NVIDIA source members are each 8,987,472 bytes, SHA-256 `B245426428543B89A7A074EDEFD7E72CC437EBED9462F287E646FD8CD4A5A8BB` / `DA517CD064CB8B17C8B62DF1783F4D641195B0EB1E90FDD07B8BA72E47511912`, and SHA-1 `7520194AB599DB8FF68C0D7277DA9DEE0EEC57C8` / `FF7DE8DB19ABE7695BCE5617894E41667CBF05E7`. Their ReadMes identify Cross Raid `1.05` and `rom/shader.farc`; they do not explicitly name the `Ver A` subrevision. This is matching numeric-version source evidence, not an author statement or runtime compatibility proof. AMD's documented NPC/missing-object rendering limitations remain.
- Virtua Fighter 5 R profile `VF5R`, exact Main build `Virtua Fighter 5 R (1.001)(2008-06-18)[Sega Lindbergh Yellow][TP]`, executable `vf5` SHA-256 `01198DA768945395C4AACF4CE9460B76F2A8EAEA850E39F52EAEC33D7EECA310`. Main `rom/shader.farc` SHA-256 is `B0C66A2AF1130E100C0EF72A808362C8D8CF0623D3F8FBD3C82B837EEEA9C247`. Author ReadMes identify VF5R 1.001 and say to extract the `rom` folder beside `vf5` and overwrite. AMD/NVIDIA exact payloads are 11,672,624 / 11,418,160 bytes, SHA-256 `403E9281A1BB73F9CDC73395E3CC614B6AADDA4AEB8D19BA96E17B55F2062419` / `B32F56FEC6F5FB99DB06C7173BE241AD8DD532444426655015AC1C4B92FC8FA3`, and SHA-1 `84E396DF3240AD565E77BF0BCAD6EDD9310535CF` / `457E4C4B0938EE88FD05583F88ECD0138F213866`.
- The bounded source receipts are `Native-CrossRaid-Exact-Source-Probe-20261015.json` and `Native-Shader-Families-Exact-Source-Probe-20261015.json`. Main and patch ZIP bytes were read without extraction or execution.
- Cross Raid black-texture member is byte-identical to Main `rom/shader.farc`; no separate replacement is enabled, and patch-versus-absent-restoration classification has not been adjudicated. Cross Raid 1.00 AMD remains held because its exact Main build and target before-state are unverified.
## 3. Explicit exclusions

- Other owner lanes: iDmac/JVS/NESiCA drivers and loaders; BepInEx-managed plugin payloads (including Mars Sortie plugin).
- Cross Raid exact Main/profile executable, shader before-state, and AMD/NVIDIA replacement-member identities are verified. Source ReadMes say 1.05, not Ver A; the 1.05 Ver A selection is a matching-version candidate, not an author statement or runtime compatibility proof. The AMD ReadMe retains NPC/missing-object rendering limitations. IC-card files share root filenames with Cross Elysion and require owner progress/runtime state; no automated IC-card mutation is in this contract.
- No guessed DAT-only recipe, raw patch application, payload hosting/download, broad optional DAT feature, game launch, `game.bat`, live install/profile/target mutation, NAS/DAT/DB/system/credentials/service mutation, package, commit, push, merge, tag, release, or GitHub/wiki write.
- The first implementation batch adds Sonic Dash Extreme, Cross Raid 1.05 Ver A AMD/NVIDIA, and VF5R 1.001 AMD/NVIDIA. Remaining checked candidates stay research-held: Cross Raid 1.00 AMD lacks an exact matching Main target; Primeval Hunt has source after-state bytes matching Main but no exact before-state evidence (research hold, not an owner blocker); Ghost Squad Evolution ELF2 has a singular-versus-plural shader layout discrepancy, multi-file staging, and an unproven AMD `EnableAmdFix` prerequisite; WMMT3 has 38 candidate members needing exact path/deduplication and multi-file staging; Hummer/Hummer Extreme source groups need full operation mapping and multi-file staging. Cross Raid black-texture bytes equal Main; no separate replacement is enabled and patch-versus-absent-restoration classification remains unadjudicated. Full guide-family reconciliation is in progress; these are not blanket holds for all remaining source families.

## 4. Behavior contract

- Current failure: the shared patch engine refuses a recipe that replaces its own executable and several executable guards assume the original executable remains present during apply/undo.
- Expected behavior: only an explicitly flagged, schema-3 single `ReplaceFile` operation may target that recipe's own declared executable. It must bind one exact ProfileId/build/executable, exact before and after hashes, one local source set/member with bounded size/SHA-1/SHA-256 pins, and refuse every unknown state. Exact after-state is a no-op. Apply backs up and verifies exact pre-state, uses the existing handle-bound race-resistant transaction and independent target readback, and receipt-bound undo restores only the exact after-state to the exact before-state. All other self-executable and multi-file self-patch operations remain refused.
- Sonic source evidence is byte identity only; no gameplay/60-fps outcome is asserted. The separate author ZIP `SonicDashExtremPatch60fps-60Hz.zip` uses unsupported Zstandard method 93 and is not needed: the exact patched executable is independently present in Main ZIP using compression method 8.
- Forbidden regressions: remove the normal self-patch refusal; accept wrong executable/build or unknown target; treat after-state as before-state; overwrite externally substituted bytes; weaken existing non-self patch and schema 1/2/3 behavior; infer game closure; claim patch success is readiness or gameplay proof.

## 5. Source/function ownership

- Files: `scripts/TpmRequiredPatchRecipes.json`, `scripts/TpmRequiredPatchEngine.ps1`, `Tests/TeknoParrot-Manager.Tests.ps1`, the current remediation control board/report, this contract and inventory, and synchronized user/architecture docs only where confirmed behavior changes.
- Engine boundary: catalog validation, `Get-TpmMultiPatchPlan`, `Invoke-TpmPatchFileBatch`, receipt verification, and `Undo-TpmCatalogPatch`; preserve existing native handle identity, no-replace promotion, and rollback rules.
- Owning subsystem: Issue #351 required-patch recipes. No per-game installer framework.

## 6. Tests required before implementation

- Characterize the current engine refusal for self-executable replacement using the existing synthetic refusal test.
- Map the actual before/after executable state handling, batch replacement race boundaries, active receipts, historical undo and schema compatibility before changing code.
- Confirm owner source receipts; verify missing recipe-required hash fields from read-only exact archive streams only when not already present in retained trusted evidence.

## 7. Tests required after implementation

- Focused Pester 5.7.1 results: Windows PowerShell 5.1 and PowerShell 7 each selected and passed 16 required-patch tests, with 0 failures and 0 skips (1,487 discovered; 1,471 not run by the filter). The synthetic self-executable tests cover exact before/apply/backup/readback/after, exact after no-op, receipt-bound undo/reapply, missing executable and payload refusal, missing-backup refusal while preserving after-bytes, undo using retained backup with source payload absent, wrong profile, unknown state, malformed multi-operation refusal, receipt tamper, and third-party publication-race preservation. Expected negative-case missing-file diagnostics were emitted; no zero-stderr claim is made.

## 8. Documentation/report updates required

- Control board: separate Issue #351 native-lane addendum; do not alter PR #321 numbered owner rows.
- Remediation report: exact new and held native entries, hashes and public-safe receipt basenames; classify each hunk to the Issue #351 owner request, this contract, and actual procedures without copying private authorization identifiers or private source paths.

## 9. Permanent procedure IDs affected

- `TPM-TRACE-001`: exact owner/issue/contract/procedure mapping for every hunk.
- `TPM-EVIDENCE-001`: focused behavioral tests including race/wrong-state/undo transitions.
- `TPM-OWNER-001`, `TPM-OWNER-002`, `TPM-OWNER-003`: runtime proof and truthful status remain separate.
- `TPM-UX-001`, `TPM-UX-002`, `TPM-PROMPT-003`, `TPM-PROMPT-005`: only if changed UX/prompt or mutation path requires it.
- `TPM-AUTH-001`: no package/commit/push/release/runtime action without explicit authorization.

## 10. Runtime smoke checklist

- Exact packaged source behavior for Sonic's supported before/after executable states, game-closed check, local Main-member verification, verified backup, receipt undo, and unknown-state refusal.
- Record exact source/package identity separately from owner install/profile/target state, launch, frame-rate outcome, and gameplay. Those owner/runtime observations remain NOT RUN.

## 11. Stop condition

Stop each candidate unless exact build/profile/executable, exact local source member, required operation hashes/absent state, prerequisites, and transaction behavior have evidence. Publish an exact checked/held list; never call the whole guide complete based on the 95 curated rows.

## 12. Forbidden actions

No game payload execution or batch launch, no live installation or shared source/DAT mutation, no unrelated edits, no test weakening, no commit, push, merge, tag, package, release, certification, GitHub comment, wiki update, or other-tree edit.

## 13. Commit/package authorization status

- Commit authorized: No.
- Package authorized: No.
- Release/certification authorized: No.
