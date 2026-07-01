# TeknoParrot Manager -- Release Safety Checklist

This checklist must be completed before every version tag, ZIP build, and GitHub release.
It is intentionally redundant: each gate catches a different failure class.

---

## 1. Pre-commit checks (every commit, not just releases)

- [ ] ASCII check -- zero non-ASCII bytes in the production script:
  ```powershell
  ($bytes=[System.IO.File]::ReadAllBytes('TeknoParrot-Manager.ps1'); ($bytes | Where-Object { $_ -gt 127 }).Count)
  ```
  Expected: 0. Any non-zero value is a parse-error risk under PS 5.1 / Windows-1252.

- [ ] Parse check -- zero errors:
  ```powershell
  $errs=$null; [System.Management.Automation.Language.Parser]::ParseFile('TeknoParrot-Manager.ps1',[ref]$null,[ref]$errs) | Out-Null; $errs.Count
  ```

- [ ] PSScriptAnalyzer (Severity Error,Warning) -- use the project settings file:
  ```powershell
  Invoke-ScriptAnalyzer -Path TeknoParrot-Manager.ps1 -Severity Error,Warning -Settings PSScriptAnalyzerSettings.psd1
  ```
  `PSScriptAnalyzerSettings.psd1` codifies all approved exclusions with rationale.
  Any finding that survives the settings file must be fixed or the settings file
  updated with a documented rationale before committing. This is the same rule set
  enforced by the CI workflow (`.github\workflows\ci.yml`).

- [ ] InjectionHunter (custom rule path):
  ```powershell
  Invoke-ScriptAnalyzer -Path TeknoParrot-Manager.ps1 -CustomRulePath "<path>\InjectionHunter.psm1"
  ```
  Every flagged variable must be traced to confirm it is either sanitized or
  not actually attacker-controlled. A finding is never dismissed by label alone.

- [ ] Pester regression suite -- must be 100% green:
  ```powershell
  Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1
  ```
  A red test means this round's changes broke an existing pure helper's behavior.
  Fix the regression before proceeding; do NOT adjust the test to match wrong behavior
  unless the behavior change was explicitly intended this round.

---

## 2. Upstream compatibility safety review (issue #47)

For each upstream TeknoParrot change that affects how this script reads or
writes profiles, verify the following properties are still intact.

### File write safety
- [ ] Every new path built from live-fetched or user-supplied input is
  sanitized with `[System.IO.Path]::GetFileName()` and/or verified with
  `Test-PathInside` before any write or copy.
- [ ] Backup-before-write is executed (and its failure aborts the operation)
  wherever a destructive write touches user data.
- [ ] No write is attempted on an `Unsupported` or `Unknown` platform/field
  outcome from `Get-FFBBlasterSupport` or any analogous gate.

### Profile/schema drift
- [ ] If upstream GameProfiles added or renamed top-level elements, run
  `Get-GameProfileSchemaDrift` against a representative sample and confirm
  every new element is classified (known-and-handled, or intentionally
  unknown/informational).
- [ ] A new FieldType in any GameProfile FieldInformation is reported by
  the drift detector before any setup flow touches that field.
- [ ] Unknown fields are never acted on -- `WouldWrite = $false` on every
  Unknown/Unsupported outcome is enforced by the tests in
  `Describe "Get-GameProfileSchemaDrift"` and `Describe "Get-FFBBlasterSupport"`.

### Platform support
- [ ] Any newly confirmed unsupported platform for FFB Blaster is added to
  `$script:FFBBlasterUnsupportedPlatforms` with a comment citing the source
  (GitHub issue, forum post, or direct test result).
- [ ] Conversely, a platform is NEVER removed from the deny-list based on
  inference alone -- only on a positive confirmation that FFB Blaster works
  there (preferably a tester report tied to a GitHub issue).

### Rollback / restore
- [ ] The Restore Backup flow (mode 9) covers every new file type this
  release touches.
- [ ] A LaunchBox or Postgres backup taken under the previous release can
  still be restored by this release without error.

---

## 3. Documentation sweep (mandatory every version bump)

**No code or release commit is complete until related documentation has
been updated and verified.** Documentation updates land in the same PR/
commit as the code change that requires them, not as a follow-up -- this
is a hard gate, the same tier as a failing Pester run. A menu change is
never considered done until every place the menu is documented (README
table of contents and body, both `.txt` docs, the script's own menu
`Write-Host` strings, and the wiki) has been checked for drift, not just
the file that happened to be open.

- [ ] `$ScriptVersion` and the header comment in the script updated.
- [ ] CHANGELOG entry written (script behavior changes only -- no debugging
  tooling, sweep process, or internal iteration noise).
- [ ] README.md updated: version line, and a full `##` section for any new
  user-facing feature (not just a mode-table row).
- [ ] TeknoParrot-Manager-README.txt updated equivalently.
- [ ] TeknoParrot-Manager-QuickStart.txt updated.
- [ ] Mode numbers grep across ALL docs AND the script's own `Write-Host` strings:
  ```powershell
  Select-String -Path "*.md","*.txt","TeknoParrot-Manager.ps1" -Pattern 'mode\s+\d+|option\s+\d+' -CaseSensitive:$false
  ```
  Every hit must match the live menu.  Stale mode references inside the
  production script's own prompt text are just as wrong as stale docs --
  see v0.99.25/v0.99.28 for examples of both.
- [ ] forum-post-beta-testing.txt updated.
- [ ] Wiki Changelog.md entry added; any changed user-facing pages updated.

---

## 4. Release mechanics

- [ ] `git tag -a vX.YY.ZZ -m "vX.YY.ZZ"` -- tag created AFTER all docs pass.
- [ ] `git push origin vX.YY.ZZ` -- push the tag before creating the release.
- [ ] Release ZIP built from Scripts\ (not a temp folder), following this
  include/exclude list (ZIP name: "TeknoParrot Manager vX.YY BETA.zip",
  always versioned):
  - Include: `TeknoParrot-Manager.ps1`, `TeknoParrot-Manager.bat`,
    `TeknoParrot-Manager-README.txt`, `TeknoParrot-Manager-QuickStart.txt`,
    `TeknoParrot-Manager-CHANGELOG.txt`, `LICENSE`, `Crosshairs\` (all 321 PNGs),
    `tools\` (the standalone `Invoke-TpmAutoUpdate.ps1` / `TpmAutoUpdate.Core.psm1`
    helper documented in `docs/AUTO_UPDATE.md` -- omitting this folder was a
    real pre-1.0 packaging gap; the menu-integrated "Check for Updates" option
    does not itself depend on it, but the documented standalone helper does).
  - Exclude: `ReShade\` (DLLs not redistributable; user obtains from
    reshade.me), `dgVoodoo2\` (user provides), `FFBPlugin\` and
    `BepInExCache\` (auto-downloaded live from GitHub each run, never
    bundled), `README.md`, `QUICKSTART.md`, `SECURITY.md`,
    `LESSONS_LEARNED.md`, `ARCHITECTURE.md`, `RELEASE-SAFETY-CHECKLIST.md`,
    `CLAUDE.md`, `PSScriptAnalyzerSettings.psd1`, `.github\`,
    `*.zip`, `*.log`, `*.config.json`.
- [ ] Validate the local ZIP structure before creating a release:
  ```powershell
  .\Tests\Test-ReleasePackage.ps1 -ZipPath "TeknoParrot Manager vX.YY BETA.zip"
  ```
  Expected: `CrosshairPngCount = 321`, `RootCrosshairPngs = 0`, and
  `ForbiddenEntryCount = 0`. A release ZIP with root-level `000.png`--`320.png`
  is invalid even if all files are present, because the runtime expects the
  `Crosshairs\` folder next to `TeknoParrot-Manager.ps1`.
- [ ] GitHub release created as a DRAFT with the ZIP attached in one step:
  ```
  gh release create vX.YY.ZZ "TeknoParrot Manager vX.YY BETA.zip" --title "..." --notes "..." --draft
  ```
  Creating without `--draft` marks the release immutable immediately, which
  blocks asset uploads and permanently tombstones the tag name even after the
  release is deleted -- a version bump is then required to recover.
- [ ] Verify the ZIP is attached and notes are correct, then publish:
  ```
  gh release edit vX.YY.ZZ --draft=false
  ```
- [ ] Releases pruned to the most recent 5 (delete oldest if count exceeds 5).
- [ ] Tag is permanent once it backs a release -- never force-push or retag.

---

## 5. Post-release verification

- [ ] Before publishing the draft, download or inspect the uploaded ZIP asset
  and run the same `Tests\Test-ReleasePackage.ps1` validation against it.
- [ ] After the release is published, spot-check the ZIP: confirm the
  Crosshairs\ folder is present and the excluded folders
  (ReShade\, dgVoodoo2\, FFBPlugin\, BepInExCache\) are absent.
- [ ] GitHub issue tracker: close any issue whose fix shipped in this release
  and was tester-confirmed working (do not ask first -- see memory entry).
- [ ] Post a fix/analysis comment to any open issue this release addresses,
  immediately after tagging (not deferred to next session).

---

_For the engineering rationale behind each item, see SECURITY.md, LESSONS_LEARNED.md, and ARCHITECTURE.md._
