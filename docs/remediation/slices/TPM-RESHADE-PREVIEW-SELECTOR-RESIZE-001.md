# ReShade preview selector and terminal resize slice

## 1. Slice name

- Name: Grouped readable ReShade preview selection and terminal resize recovery
- Contract ID: `TPM-RESHADE-PREVIEW-SELECTOR-RESIZE-001`
- Issue/PR: owner request in issue #300 comment 6234278849; related preview behavior in issue #347
- Source snapshot: `local/rc8-integrated-20261021` HEAD `15576abc708b6bb9964e68a417a8e4804f26aade`, with the supplied working tree copied into local snapshot commit `2004b250517bc5ceda0f415e98c314d760c535ed`.
- Supplied manager SHA-256: `80D614C716DE011E6DE9EA15CA25E434E7BE77EE7398B7C1C267AC4CA047A4F7`.
- Follow-up independent review P2: a short terminal viewport can scroll while a rebuilt menu and prompt are printed; treating that draw-induced `WindowTop` change as another resize appends the menu repeatedly.

## 2. Owner report IDs included

- IDs: 9 and 10, ReShade preview synchronization and selector visibility.
- Exact failures in this slice: the preview drop-down is flat while the terminal list is grouped; preview text and fixed-height controls can be hard to read or clip; the waiting terminal prompt does not rebuild for height-only or window-origin changes.

## 3. Explicit exclusions

- No changes to PostgreSQL, footer, GPU, BepInEx, shaders, profile membership, graphics protections, selection numbering, install paths, runtime game/profile files, or cleanup ownership.
- No shader removal, ownership-policy change, weaker HDR gate, package, installation, commit, push, merge, tag, release, GitHub mutation, live game, or security-setting change.
- Slider behavior, canonical `ProfileId` synchronization, and gallery cleanup remain in scope as invariants to preserve.

## 4. Behavior contract

- Preview choices use the same visible group labels and order as the terminal. A heading is not a profile and cannot become the selected profile. The HDR heading appears only when HDR choices are present in the gated profile list.
- Preview text is larger, and the gallery toolbar and instruction area remeasure or wrap with window width and DPI. The existing comparison slider and image alignment are preserved.
- Selection synchronization always uses the canonical `ProfileId`, independent of inserted heading rows.
- While terminal input is waiting, changes to window width, left/top origin, height, buffer width, or buffer height trigger a safe menu rebuild. The typed input buffer is preserved. In-place redraws never write the final visible column and are refused after any geometry change.
- A rebuilt menu records the viewport after output. Scrolling caused by that draw becomes the new observed top; later window or buffer geometry changes still trigger a rebuild. If width, horizontal origin, height, or buffer dimensions change during rendering, the earlier snapshot remains so the next poll can rebuild for that real change.
- If a rebuild cannot be completed, the prompt remains available and reports the fallback.
- Forbidden regressions: shader catalog changes, weakened graphics/HDR protections, loss of typed input, a selectable heading, an index-based selection mismatch, slider regression, leaked selector handler/font, or gallery resources left open after cleanup.

## 5. Source/function ownership

- Files: `TeknoParrot-Manager.ps1`; `Tests/TeknoParrot-Manager.Tests.ps1`; `TeknoParrot-Manager-README.txt`; `TeknoParrot-Manager-QuickStart.txt`; this contract; `docs/remediation/PR-321-control-board.md`; `docs/remediation/PR-321-reconciliation.md`.
- Functions/regions: `Get-TpmReShadeProfileSelectorRows`, `Get-TpmReShadeProfileSelectorIndex`, `Get-TpmReShadeProfileSelectorNextIndex`, `Show-TpmReShadeProfileGalleryWindow`, `Sync-TpmReShadeGallerySelection`, `New-TpmReShadeGalleryEventHandlers`, `Close-TpmReShadeProfileGallerySession`, `Read-TpmReShadeTerminalInput`, `Get-TpmConsoleMetrics`, `New-TpmReShadeTerminalLayout`, `Update-TpmReShadeTerminalSelectionInPlace`, `Update-TpmReShadeTerminalLayoutAfterResize`, `Read-TpmReShadeTerminalProfile`.
- Owning subsystem: ReShade preview selector and interactive terminal chooser.

## 6. Baseline evidence

- No pre-edit Pester run was made. The source audit and verified working-tree snapshot were the baseline; pre-edit behavior is not presented as test-certified.
- Source baseline branch/HEAD: `local/rc8-integrated-20261021` / `15576abc708b6bb9964e68a417a8e4804f26aade`, with the combined uncommitted fixes preserved in snapshot commit `2004b250517bc5ceda0f415e98c314d760c535ed`.
- The supplied pre-edit manager working-tree file hash was verified as SHA-256 `80D614C716DE011E6DE9EA15CA25E434E7BE77EE7398B7C1C267AC4CA047A4F7` (2,370,127 bytes). The donor clone uses `core.autocrlf=true`; the baseline snapshot commit's normalized manager blob is 2,333,132 bytes with SHA-256 `9C696AFE8FCC5F4AC924E1A033EF3364A7EEE657FC273CF70C82A8D8CE492C59`. The primary tree was read to make the snapshot and not edited; the protected WIP tree was not touched.

## 7. Focused results

- Final combined focused run: 31 selected ReShade tests passed (31 passed, 0 failed, 0 skipped) on Windows PowerShell 5.1.26100.9711 and PowerShell 7.6.5, with Pester 5.7.1. The selection includes all 29 previously defined focused cases (including the short-viewport regression) plus the two assertions that had failed in the broader filter. Of 1,498 discovered tests, 1,467 were intentionally not run; this was not a full-suite run.
- Exact `-FullNameFilter` patterns used for the combined selection:

  ```powershell
  @(
      '*TPM-RESHADE-TWENTY-EFFECTS-001 grouped preview selector and readable layout*',
      '*TPM-RESHADE-TWENTY-EFFECTS-001 live terminal and gallery selection sync*',
      '*TPM-RESHADE-TWENTY-EFFECTS-001 live selection display in the terminal (virtual console)*',
      '*draws the label through one centered routine and leaves the label wording unchanged*',
      '*changes the preview renderer version so cached pictures drawn with the old left-aligned label are not reused*',
      '*centers the top instruction and description text of the gallery window and keeps the measurement flags in step*',
      '*keeps the description wording and every warning exactly as before for all profiles*',
      '*disposes the gallery picture image idempotently*',
      '*updates slider state in memory without replacing the preview image*'
  )
  ```
- Short-viewport regression: the virtual-console test observes `WindowTop` move during a redraw, then verifies stable row counts and viewport position across three idle polls while the typed prompt text remains present.
- The two prior broad-filter failures were fixture setup problems, not reasons to drop either assertion. For cursor-failure recovery, the old test injected a cursor write failure on call 1, which now occurs during the initial menu draw; the corrected test arms the same failure on the first cursor write after the initial draw, at the preview-change callback. It still asserts one fallback announcement, preserved typed text, and a later successful in-place update. On the exact original manager baseline (`80D614C716DE011E6DE9EA15CA25E434E7BE77EE7398B7C1C267AC4CA047A4F7`), the existing cursor-fallback test passed 1/1 under Pester 5.7.1 on PS7.
- The final-column regression is new in this slice. Its earlier fixture directly wrote an old Current-row character into the reserved final visible column. The corrected setup seeds stale rows through `Write-TpmReShadeTerminalLines`, the production renderer that reserves the last column; the assertions still verify both rows clear and the final column is never written.
- Both test processes ran on host `TEST-PC` as `TEST-PC\Example`. Windows PowerShell was `C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe` (5.1.26100.9711); PowerShell 7 was `C:\Users\Example\PowerShell7\pwsh.exe` (7.6.5). This is separate from the primary route's reported 7.6.7. The session name was blank and process session ID was 1; `qwinsta` returned access denied, so local-console versus RDC session type could not be established. No environment was installed or changed.
- An earlier PS 5.1 diagnostic invocation included a process-scoped `-ExecutionPolicy Bypass` flag. No persistent policy setting was changed. The final 31-case PS 5.1 run used the existing policy with no override and passed 31/31.
- PowerShell parser: zero errors in `TeknoParrot-Manager.ps1` and `Tests/TeknoParrot-Manager.Tests.ps1` under both engines.
- PSScriptAnalyzer 1.25.0 on `TeknoParrot-Manager.ps1`: zero Error-severity findings. `git diff --check` passed. All added tracked diff lines are ASCII; the new slice contract, product script, tests, README, and Quick Start also contain zero non-ASCII characters. Existing historical control-board/report text has non-ASCII characters, while the added lines remain ASCII.
- These are source/fixture checks, not actual WinForms visual validation or owner-runtime certification.

## 8. Documentation/report updates required

- User instructions: update the existing ReShade sections of the README and Quick Start with purpose, steps, expected result, group-heading explanation, and recovery guidance.
- Control board: record owner IDs 9/10, evidence boundary, and runtime proof still needed.
- Remediation report: record exact snapshot/result identity, focused test evidence, missing real screenshot, and remaining owner visual checks.
- Hunk mapping: product selector and console helpers; focused source/virtual-console regressions; user instructions; this source-evidence record.
- No changelog, package, or release note is added by this isolated source slice.

## 9. Permanent procedure IDs affected

- None. This UI-only source correction does not alter a permanent procedure contract.

## 10. Runtime smoke checklist

- Use the exact final source/package identity on Windows PowerShell 5.1 with the owner console and PowerShell 7.
- Capture real screenshots of the finished preview drop-down and terminal chooser, with no unrelated private content. Verify both selection directions, headings, slider, resize/reopen, and automatic gallery cleanup.
- Exercise height-only, width-only, horizontal/vertical origin, and buffer-size changes while input is partially typed; verify the input remains, no accidental scroll occurs, and final-column redraw is avoided.
- Check available DPI settings (100%, 125%, 150%, 200%) for clipping and off-screen controls.
- Owner runtime, screenshots, and visual acceptance are not established by this local source slice. Do not treat source or fixture tests as screenshots or GUI passes.

## 11. Stop condition

Stop after the focused dual-engine and static checks, documentation updates, exact source/result hashes, and control-board/report mappings are complete. Leave real visual, screenshot, and owner-runtime gates visible as outstanding.

## 12. Forbidden actions

No unrelated edits, source-tree edits to `<test-pc-repos>\tpm-rc8-integration-20261021`, protected WIP edits, primary-tree edits, commit, push, package, install, live game/profile modification, merge, tag, publication, or release action.

## 13. Commit/package authorization status

- Commit authorized: No.
- Package authorized: No.
- Release/certification authorized: No.

## 14. Local result and evidence boundary

- Final manager SHA-256: `7665CBBFBF852C21592B47DA30FC98B5A4BA525677FEDFECA50ABA9B86469739` (2,388,979 bytes). the TPM source is unchanged from the reviewed P2 candidate; this follow-up corrects only test setup and evidence documentation.
- Final test-file SHA-256: `218852CDEEC0363F1F13A6D14B8E9AE8F12C1A1EB0CED7C51950DF5CEFFC1D8B` (1,719,164 bytes).
- P2 patch SHA-256: `5FAC37158A42444E91D8918099A9669B3B5AF842987A2AB72AC46F0B07FCD603`. It remains preserved. This P3 patch supersedes it with corrected fixtures and updated test evidence.
- The README and Quick Start now explain the preview purpose, group headings, selection steps, comparison controls, expected synchronized selection, terminal resize/input behavior, and `B`/`R` recovery in plain language.
- CUA surface inventory showed `apps=[]` and only a Chrome tab labeled 'TeknoParrot Crosshairs'; no TeknoParrot Manager gallery or terminal window was available to capture. No screenshot was fabricated, and no GUI/visual pass is claimed.
- Remaining acceptance: owner should run the exact final source/package, verify the preview and terminal chooser visually at supported DPI/widths, exercise input retention across window/buffer geometry changes, confirm slider/selection synchronization, and provide real screenshots tied to the tested source/package identity.
