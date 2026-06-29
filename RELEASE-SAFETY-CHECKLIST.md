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

- [ ] PSScriptAnalyzer (Severity Error,Warning):
  ```powershell
  Invoke-ScriptAnalyzer -Path TeknoParrot-Manager.ps1 -Severity Error,Warning
  ```
  PSAvoidUsingWriteHost is expected and ignorable (interactive CLI). All other
  findings must be reviewed and either fixed or explicitly noted as false positives.

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
- [ ] Release ZIP built from Scripts\ (not a temp folder), following the
  include/exclude list in CLAUDE.md.
- [ ] GitHub release created against the new tag; ZIP uploaded as the asset.
- [ ] Releases pruned to the most recent 5 (delete oldest if count exceeds 5).
- [ ] Tag is permanent once it backs a release -- never force-push or retag.

---

## 5. Post-release verification

- [ ] After the release is published, spot-check the ZIP: confirm the
  Crosshairs\ folder is present and the excluded folders
  (ReShade\, dgVoodoo2\, FFBPlugin\, BepInExCache\) are absent.
- [ ] GitHub issue tracker: close any issue whose fix shipped in this release
  and was tester-confirmed working (do not ask first -- see memory entry).
- [ ] Post a fix/analysis comment to any open issue this release addresses,
  immediately after tagging (not deferred to next session).

---

_For the engineering rationale behind each item, see CLAUDE.md and LESSONS_LEARNED.md._
