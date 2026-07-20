# TeknoParrot Manager -- Release Safety Checklist

This checklist must be completed before every version tag, ZIP build, and GitHub release.
It is intentionally redundant: each gate catches a different failure class.

---

## 0. The Jumpstile Release Standard

Adopted as the permanent release process for this repository during the
v1.0 RC2.1 cycle (see `docs/RELEASE-RETROSPECTIVE-v1.0-RC2.1.md` for the
full retrospective this was drawn from). Recommended as the standard
release order for every Jumpstile project, per `CONSTITUTION.md`'s
"Release governance" section -- this document is the concrete TPM
implementation of that portfolio-wide principle, not a competing policy.

### Release order

1. **Code Complete** -- the change set is finished, not "mostly done."
2. **Automated Tests** -- targeted tests for the touched area at minimum
   (see Section 1 below); full suite once before believed complete.
3. **Manual Testing** -- a human exercises the actual behavior, not just
   the test suite, for anything UX/visual/behavioral.
4. **Independent Review** -- Independent Review Required
   (`CONSTITUTION.md`'s "Independent Review Required"): a second,
   independent pass (human or a second AI agent) that did not write the
   fix reviews it before it's treated as settled. Convergent independent
   diagnosis of the same root cause from two separate reviewers is strong
   evidence a fix targets the real defect. When the finding under review
   traces to a governing specification, see Section 10 below -- work is
   not submitted for this step until it meets
   `SPECIFICATION_DRIVEN_REVIEW_STANDARD.md`'s Definition of Review
   Ready. For this repository specifically (currently single-maintainer),
   this step is satisfied by the documented external review workflow
   (Regular Codex) per `CONSTITUTION.md`'s "Single-Maintainer
   Governance" -- not by a GitHub approving review, which the repository
   owner cannot submit on their own pull request. When a review returns
   findings, follow `INDEPENDENT_REVIEW_WORKFLOW_STANDARD.md` -- fix in
   focused commits, then a delta review scoped to those commits (its
   "Delta review principle"), not a full re-review, closes the loop unless
   the delta review itself determines the scope has materially expanded.
5. **Real-Hardware Certification** (where applicable) -- the TPM
   Certification Suite run on an actual arcade machine against an actual
   TeknoParrot install, not simulated or run only in a dev environment.
6. **Full Documentation Sweep** -- Section 3 below, and Section 3 of this
   document's "Documentation Sweep Policy" -- mandatory every release, not
   optional and not something a version bump can skip.
7. **Release Retrospective** -- a permanent, dated document (see Section 3
   policy below) capturing what shipped, why, root causes of significant
   bugs, and lessons learned, written once per release cycle and never
   rewritten to match a later release.
8. **Package Build** -- Section 4 below.
9. **Package Validation** -- `Tests\Test-ReleasePackage.ps1` against the
   built ZIP, Section 4 below.
10. **SHA256 Generation** -- computed on the validated local package before
    upload, recorded in the release notes and/or retrospective.
11. **Git Tag** -- created only after every prior step passes. Never reused,
    never force-moved once it backs a published release (immutable, see
    Section 7).
12. **GitHub Release** -- created as a **draft** first, always -- a
    non-draft release immediately and permanently locks the tag name and
    any uploaded assets, even after the release is later deleted.
13. **Asset Verification** -- the published asset is downloaded back and
    SHA256-compared against the local validated package before the release
    is left in its final published state. Trusting that an upload
    "succeeded" without this comparison is not sufficient.
14. **Post-Release Audit** -- Section 6/7 below: working tree clean,
    `origin/main` matches local, tag correct, no lingering release
    blockers, remaining open issues reclassified as post-release
    enhancements where appropriate.

### Governance audit (mandatory, every release)

Every release includes the following, per `ENGINEERING_GOVERNANCE.md` and
issue #138 ("Engineering Governance and Project Health," the permanent
tracking meta-issue reviewed at every release):

- [ ] **Issue audit** -- every issue touched or discovered this cycle has
      at least one Type, one Priority, and one Component label.
- [ ] **Label audit** -- no duplicate or obsolete labels in active use;
      the label set in the repository matches `ENGINEERING_GOVERNANCE.md`
      Section B exactly.
- [ ] **Milestone audit** -- milestones reflect current planning; a
      milestone is only closed when the release it represents actually
      ships, never merely because its issues are all closed.
- [ ] **Cross-reference audit** -- release-gate issues list every issue
      they're actually still waiting on; that list is current, not stale.
- [ ] **Documentation audit** -- Section 3 below (the mandatory
      documentation sweep).
- [ ] **Certification audit** -- Section 5 below (Release Integrity
      Audit) plus real-hardware certification evidence where applicable.
- [ ] **Release retrospective** -- a permanent, dated
      `docs/RELEASE-RETROSPECTIVE-<version>.md` written once per release
      cycle (see `docs/RELEASE-RETROSPECTIVE-v1.0-RC2.1.md` for the
      template this established).

### AI workflow

The roles below are the concrete assignment of `CONSTITUTION.md`'s existing
Roles taxonomy (Lead Engineer / Independent Reviewer / Chief Architect /
Release Manager) to specific tools, as actually used during the RC2.1
cycle. This is a recommended pattern for other Jumpstile projects, not a
requirement that every project use every one of these tools -- the
underlying roles (implementation, independent verification, architecture
and governance, and the human Release Manager decision) are what matter;
which specific AI tool fills which role is a project choice.

- **Claude** -- Lead Engineer role. Primary implementation, documentation,
  and release preparation. Writes the code, writes the docs, prepares (but
  does not unilaterally authorize) the release.
- **Codex** -- Independent Reviewer role. Independent verification, real-
  hardware validation, regression verification, and certification
  confirmation. Critically, works from a separate environment (the real
  arcade machine) and does not simply re-read the same diff -- it re-derives
  findings independently, which is what makes convergent findings between
  Claude and Codex meaningful evidence rather than an echo of the same
  analysis.
- **ChatGPT** -- Chief Architect / Technical Program Manager role.
  Architecture, governance, release review, and engineering standards --
  reconciling findings from independent reviews into a release-readiness
  recommendation, without itself authorizing publication.
- **Release Manager (human, the repository owner)** -- unchanged from
  `CONSTITUTION.md`: the sole authority to approve a version change,
  create the tag, publish the release, and change any release-identity
  marker. No AI role in this workflow substitutes for this decision.

This multi-role structure is also what makes safe parallel work possible
under `ENGINEERING_VELOCITY_AND_TIME_STEWARDSHIP_STANDARD.md`: the Lead
Engineer role continuing implementation on genuinely independent work
while the Independent Reviewer role audits an already-submitted,
unrelated piece of work is the standard's "parallelize independent work
whenever safe" principle in practice, not a deviation from this workflow
-- provided the work streams are actually independent and the review in
progress is never itself modified by the parallel work.

### Documentation Sweep Policy (permanent, every release)

Documentation is part of the product, not an afterthought to it. Every
release requires review of:

- every `*.md` file in the repository
- every `*.txt` file in the repository
- `docs/`
- the GitHub wiki
- `README.md` / `TeknoParrot-Manager-README.txt`
- `TeknoParrot-Manager-CHANGELOG.txt`
- `TeknoParrot-Manager-QuickStart.txt` / `QUICKSTART.md`
- user guides
- engineering docs (`ARCHITECTURE.md`, `LESSONS_LEARNED.md`, etc.)
- release docs (this file)
- certification docs (`docs/TPM-CERTIFICATION-SUITE.md`)

See Section 3 below for the mechanical checklist this policy implements.

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
- [ ] Non-obvious implementation constraints introduced or touched this
  round are documented twice (see `CONSTITUTION.md`, "Documenting
  non-obvious implementation constraints"): once in the relevant
  architecture/design document as the current rule, and once in
  `LESSONS_LEARNED.md` explaining what failed, how it was diagnosed, and
  how to safely validate future changes. This only applies when the
  constraint is non-obvious, easy for a future maintainer to "simplify"
  incorrectly, and proven by a real incident, regression, certification
  failure, or investigation -- not to routine implementation details or
  ordinary design decisions.

---

## 4. Release mechanics

- [ ] `git tag -a vX.YY.ZZ -m "vX.YY.ZZ"` -- tag created AFTER all docs pass.
- [ ] `git push origin vX.YY.ZZ` -- push the tag before creating the release.
- [ ] Release ZIP built from Scripts\ (not a temp folder), following this
  include/exclude list (ZIP name: "TeknoParrot Manager vX.Y RCn.zip",
  always versioned):
  - Include: `TeknoParrot-Manager.ps1`, `TeknoParrot-Manager.bat`,
    `TeknoParrot-Manager-README.txt`, `TeknoParrot-Manager-QuickStart.txt`,
    `TeknoParrot-Manager-CHANGELOG.txt`, `LICENSE`, `Crosshairs\` (all 321 PNGs),
    `tools\` (the standalone `Invoke-TpmAutoUpdate.ps1` / `TpmAutoUpdate.Core.psm1`
    helper documented in `docs/AUTO_UPDATE.md` -- omitting this folder was a
    real pre-1.0 packaging gap; the menu-integrated "Check for Updates" option
    does not itself depend on it, but the documented standalone helper does),
    and `scripts\Debug-TPM-MenuLayout.ps1` (RC2 menu-layout verification helper).
  - Exclude: `ReShade\` (DLLs not redistributable; user obtains from
    reshade.me), `dgVoodoo2\` (user provides), `FFBPlugin\` and
    `BepInExCache\` (auto-downloaded live from GitHub each run, never
    bundled), `README.md`, `QUICKSTART.md`, `SECURITY.md`,
    `LESSONS_LEARNED.md`, `ARCHITECTURE.md`, `RELEASE-SAFETY-CHECKLIST.md`,
    `CLAUDE.md`, `AGENTS.md`, `CONSTITUTION.md`, `ENGINEERING_GOVERNANCE.md`,
    `CONTRIBUTING.md`, `SPECIFICATION_DRIVEN_REVIEW_STANDARD.md`,
    `INVENTORY_STANDARDS.md`,
    `ENGINEERING_VELOCITY_AND_TIME_STEWARDSHIP_STANDARD.md`,
    `PSScriptAnalyzerSettings.psd1`, `.github\`,
    `*.zip`, `*.log`, `*.config.json`.
    This list must match `AGENTS.md`'s "Release ZIP contents" exclude
    list exactly. This section is the authoritative source; if the two
    are ever found to disagree, update `AGENTS.md` to match this section,
    not the other way around -- a governance-doc list that omits a
    tracked repository-root `.md` file (as this section previously did
    for `AGENTS.md`, `CONSTITUTION.md`, `ENGINEERING_GOVERNANCE.md`,
    `CONTRIBUTING.md`, and the three Engineering Standards documents) is
    a real packaging-correctness gap, not a formatting nitpick.
- [ ] Validate the local ZIP structure before creating a release:
  ```powershell
  .\Tests\Test-ReleasePackage.ps1 -ZipPath "TeknoParrot Manager vX.Y RCn.zip"
  ```
  Expected: `CrosshairPngCount = 321`, `RootCrosshairPngs = 0`, and
  `ForbiddenEntryCount = 0`. A release ZIP with root-level `000.png`--`320.png`
  is invalid even if all files are present, because the runtime expects the
  `Crosshairs\` folder next to `TeknoParrot-Manager.ps1`.
- [ ] GitHub release created as a DRAFT with the ZIP attached in one step:
  ```
  gh release create vX.YY.ZZ "TeknoParrot Manager vX.Y RCn.zip" --title "..." --notes "..." --draft
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

## 5. Release Integrity Audit (mandatory before every public release)

Certification proves the software behavior is correct. Release Integrity proves
the product delivered to users identifies and describes itself correctly. Every
public release (RC, Beta, Final, Hotfix) must pass this audit in addition to
Certification.

### Phase 1 -- Runtime Identity Audit

- [ ] TPM banner, startup banner, `$ScriptVersion`, and release-candidate label
  identify the release being published.
- [ ] Update dialogs and updater comparisons identify current/latest versions
  correctly, including release-candidate tags.
- [ ] Generated reports, certification scorecards, logs, release metadata, ZIP
  filename, GitHub Release title, release tag, and asset name describe the same
  release identity.
- [ ] The packaged runtime identifies itself as the release being published
  when extracted and launched.

### Phase 2 -- Documentation Audit

- [ ] Review every user-facing document, not only version strings: README,
  Quick Start, CHANGELOG, release notes, this checklist, CONTRIBUTING if
  present, PROJECT_OVERVIEW if present, CONSTITUTION, CLAUDE.md, AGENTS.md,
  LESSONS_LEARNED, TPM-CERTIFICATION-SUITE, Compatibility, every file under
  `docs\`, and any release-facing text files.
- [ ] Verify menu options, workflow descriptions, certification process,
  updater behavior, DAT workflow, behavioral certification, scorecards, backup
  behavior, current capabilities, current limitations, test counts, links, and
  terminology against the current product.

### Phase 3 -- Wiki Audit

- [ ] Review every wiki page for current screenshots, workflows, menu
  structure, capabilities, certification process, updater documentation, DAT
  documentation, troubleshooting, FAQ, installation, and release guidance.
- [ ] Remove stale content, repair broken links, and update screenshots where
  appropriate.

### Phase 4 -- Release Artifact Audit

- [ ] Verify the built and downloaded release ZIP match the repository,
  runtime banner, packaged script, ZIP contents, release notes, changelog,
  documentation, GitHub Release, and README.

### Phase 5 -- Release Metadata Audit

- [ ] Verify tag, commit, release title, asset name, asset size, published
  asset, downloaded asset, and final tag target all match the intended release.

### Phase 6 -- Regression Protection

- [ ] Add automated validation where practical: packaged version matches the
  release, runtime banner matches the release, script identity matches docs,
  README latest tag matches the release, release ZIP identity validation
  passes, and release metadata can be checked before publication.

### Phase 7 -- Report

- [ ] Produce a Release Integrity Report listing every file reviewed, every
  document reviewed, every wiki page reviewed, every correction made, every
  stale item found, and any remaining intentional discrepancies.

---

## 6. Post-release verification

- [ ] Before publishing the draft, download or inspect the uploaded ZIP asset
  and run the same `Tests\Test-ReleasePackage.ps1` validation against it.
- [ ] After publishing, copy the exact release ZIP into `Scripts\` as the
  local current-release mirror. This is not optional: `Scripts\` must always
  contain a ZIP identical to the published GitHub release asset.
- [ ] Prune local distribution ZIPs so `Scripts\` contains exactly one
  `TeknoParrot Manager*.zip` file: the current published release only.
- [ ] Verify the `Scripts\` mirror using the dedicated guard:
  ```powershell
  .\Tests\Test-ScriptsReleaseZip.ps1 `
    -ScriptsPath .\Scripts `
    -ExpectedZipPath "TeknoParrot Manager vX.Y RCn.zip"
  ```
  Expected: `ZipCount = 1`, `NameMatchesExpected = True`, and
  `HashMatchesExpected = True`. A mismatch, missing ZIP, or extra stale ZIP
  fails the release.
  **Filename caveat:** GitHub replaces spaces with dots in uploaded release
  asset names (e.g. `TeknoParrot Manager v0.99.44 BETA.zip` is stored as
  `TeknoParrot.Manager.v0.99.44.BETA.zip`) -- this is consistent platform
  behavior, confirmed across every past release, not an upload error. Never
  pass the raw downloaded GitHub asset as `-ExpectedZipPath` directly; its
  filename will always fail the exact-name check even when content is
  identical. Instead, keep or create a canonically-named local reference
  copy (matching the `TeknoParrot Manager vX.Y RCn.zip` convention) and
  pass that -- the script compares filenames exactly, so the reference
  copy's name must already match the convention before the check can pass.
- [ ] After the release is published, spot-check the ZIP: confirm the
  Crosshairs\ folder is present and the excluded folders
  (ReShade\, dgVoodoo2\, FFBPlugin\, BepInExCache\) are absent.
- [ ] GitHub issue tracker: close any issue whose fix shipped in this release
  and was tester-confirmed working (do not ask first -- see memory entry).
- [ ] Post a fix/analysis comment to any open issue this release addresses,
  immediately after tagging (not deferred to next session).

## 7. Post-Release Housekeeping (mandatory, every release)

A release is not complete until this phase runs. It is local-workspace
cleanup only -- it never touches GitHub releases/tags and never changes
production code.

- [ ] Verify the GitHub release: published (not draft), correct tag, correct
  target commit.
- [ ] Verify the release asset: exists, correct file, matches
  `Tests\Test-ReleasePackage.ps1` validation (re-run against the actual
  downloaded asset, not just the local build, to rule out upload corruption).
- [ ] Confirm `Scripts\` holds exactly one release ZIP -- the current
  published release, identical by SHA256 to the GitHub release asset -- via
  `Tests\Test-ScriptsReleaseZip.ps1` (see section 5). This mirror ZIP is a
  required, current file, not clutter: do not archive or remove it while it
  is still the current release.
- [ ] Archive every *other* local release ZIP (prior versions, or a stale
  build copy that predates the current mirror) into a timestamped folder
  under `_archive\` (e.g. `_archive\<YYYYMMDD-HHMMSS>-post-release-housekeeping\`).
  Never delete permanently -- move only. Archived copies are kept for
  traceability, comparison, or rollback investigation, not discarded.
- [ ] Confirm the Scripts\ folder contains only files needed to operate or
  develop TPM, except: log files, JSON files from previous runs, and the one
  current-release ZIP mirror above (all three are legitimate and must be
  left in place, not archived).
- [ ] Confirm the local git working tree is clean (`git status`) after
  packaging, publication, mirror validation, and issue updates, and that the
  housekeeping pass itself made no unintended tracked-file changes or commits.
- [ ] Report a concise release summary: tag, release ZIP name, published
  asset SHA256, `Scripts\` mirror SHA256, validation commands and results,
  files moved, archive path, issue updates, working tree status, and any
  remaining tester follow-up.

## 8. AI attribution sweep (every GitHub post)

Before any GitHub issue, issue comment, PR description, PR review, release
note, or wiki update is posted, it must be checked for AI attribution
footers. This applies every time, not just during release rounds -- it is
part of the standing GitHub publishing checklist, the same tier as the
pre-commit gates in section 1.

**Forbidden examples:**
- "Generated by Claude Code"
- "Generated by ChatGPT"
- "Co-authored-by" crediting AI tooling, unless intentionally part of git
  commit metadata and explicitly approved
- Any similar AI-generated footer or branding line

- [ ] Remove attribution/footer text before posting.
- [ ] Do not remove technical content while doing so.
- [ ] Do not silently edit technical meaning while cleaning attribution --
  if a correction to technical content is also needed, that is a separate,
  explicit edit, not bundled into an attribution cleanup pass.
- [ ] If attribution is found after posting, edit only the attribution/
  footer and leave all technical content unchanged.
- [ ] After cleanup, perform a quick sweep of the specific issue/PR just
  touched (body, comments, reviews) to confirm nothing else was missed --
  in addition to, not instead of, the full repo-wide sweep already required
  by CLAUDE.md after any GitHub-touching round.

## 9. Release governance exceptions

Normal PR review remains the standing rule for release-critical changes. Admin
override merges are exceptions, not precedent; when one is used, record the
affected PRs, why review was bypassed, what automated evidence was green at
merge time, and what later certification evidence closed the release risk.

The instances logged below predate `CONSTITUTION.md`'s "Single-Maintainer
Governance" section and were driven by the same underlying platform
restriction that section now formally addresses (GitHub reporting "review
required" that this repository's sole maintainer structurally cannot
satisfy via GitHub's own approval mechanism). They remain here as
historical record per `CONSTITUTION.md`'s "Historical evidence in
investigations" principle, not as ongoing precedent -- going forward, this
condition is handled by the documented policy (Independent Review
Required satisfied via the external review workflow, required-approving-
review branch protection set to zero) rather than by an ad hoc admin
override each time.

### 2026-07-03 -- v0.99.45 release-candidate exception

PR #87 (`Issue #79 pcsx2x6 fix, in-script auto-update hardening, TPM
Certification Suite fixes`) and PR #89 (`Fix ScriptVersion/header version
mismatch (0.99.44 vs 0.99.45)`) were merged by admin override while GitHub
still reported review required. The override was used to unblock a
release-candidate fix chain after the code was already constrained by green CI
and the remaining risk had narrowed to final real-machine certification.

CI was green for both PRs at merge time. After merge, the outstanding
arcade-machine certification was rerun against exact merged `main` commit
`a85aa26942b46132bba252dcf24edc42c214f6e6` and passed 8/8 (100%): repository
clean, Pester 321/321, static analysis 0 findings, real install health,
backups, smoke file safety, artifacts, and the issue #79 pcsx2x6 gate all
passed; the BAT launcher was also confirmed working and opened the report
folder.

Treat this as governance debt / exception-log material only, not a technical
release blocker for the certified commit. Future release-critical PRs should
return to normal review approval before merge unless an explicit release-manager
exception is recorded with equivalent evidence.

### 2026-07-03 -- PR #91 (Issue #88 phase 1) exception, third instance

PR #91 (`Issue #88 phase 1: Virtual Beta Tester -- real executable coverage`)
was also merged by admin override, the third instance in this same session.
The repository owner was explicitly asked whether to review it directly or
repeat the override, and chose the override with the tradeoff stated plainly
(see `LESSONS_LEARNED.md` for the full record).

CI was green at merge time. Real-arcade-machine certification was rerun
afterward against exact merged `main` commit
`aa99b9459058ce0a62b7b5ff1a8dfc787f233bfa` and passed 9/9 (100%), including
the new Virtual Beta Tester coverage gate (`total=14 passed=14 failed=0`); the
BAT launcher was confirmed working and the report folder opened automatically.

Three instances in one session is the point at which this stops being a
reasonable one-off exception. A genuine second reviewer (human or a separate
AI reviewer account distinct from the PR author) should be configured before
a fourth instance occurs.

## 10. Specification-Driven Review Standard (specification-governed findings)

Applies whenever a review finding, or the area of work under review,
traces to a governing specification -- a file format, a protocol, a
language grammar, an API contract, a regulatory rule -- rather than to a
single isolated case. Full standard: `SPECIFICATION_DRIVEN_REVIEW_STANDARD.md`.
Companion artifact standard (Specification Inventory / System Invariant
Inventory): `INVENTORY_STANDARDS.md`.

- [ ] The finding has been generalized to its problem class, not treated
  as a single isolated case.
- [ ] The governing specification's relevant sections were read (or
  re-read) for this round before implementing.
- [ ] A Specification Inventory (and, where the component has internal
  guarantees beyond the external spec, a System Invariant Inventory) was
  built or updated and used to drive implementation, rather than the
  applicable rule family being recalled from memory.
- [ ] Every rule in the identified applicable family is implemented, not
  only the originally reported one.
- [ ] A deliberate self-adversarial review was performed against the
  specification before submission, and everything it found was fixed in
  the same round.
- [ ] New regression tests exercise the defect class, including
  boundary/table coverage where the specification defines one -- not only
  the exact reported case.
- [ ] Anything from the governing specification deliberately left
  unimplemented is documented with its rationale (in the code, in the
  Specification Inventory's "Deliberately out of scope" section, or both).
- [ ] Prior layered defenses and behavior outside the current finding's
  scope are confirmed unchanged.
- [ ] Verification evidence (commands run, results) is reported alongside
  the submission.

Work against a specification-governed finding is not submitted for
Independent Review (release order step 4, Section 0 above) until every
box above is honestly checked. This is the Section 1 pre-commit gates'
sibling for specification-governed correctness, not a replacement for
them -- both apply.

## 11. Engineering Velocity and Time Stewardship

Full standard: `ENGINEERING_VELOCITY_AND_TIME_STEWARDSHIP_STANDARD.md`.
Applies continuously, not just at release time -- referenced here because
release engineering (this document) is one of the areas most likely to
accumulate exactly the kind of repeated manual work that standard exists
to reduce.

- [ ] Any release-checklist step performed identically, by hand, across
  multiple recent releases is flagged as an automation candidate (see
  `Tests\Test-ReleasePackage.ps1` for an existing instance of this
  already done).
- [ ] Independent work streams (e.g. governance/documentation work and an
  in-flight, unrelated code review) proceeded in parallel where safe to
  do so, rather than being serialized without a dependency reason.
- [ ] No quality gate in this document (Sections 0-10 above) was skipped,
  weakened, or deferred in the name of finishing faster -- per that
  standard's "preserve all quality gates" and "never trade engineering
  quality for short-term speed" principles, a proposed velocity gain that
  requires this is not a velocity improvement under that standard and
  does not apply here.

Any item above may be marked N/A only under
`ENGINEERING_VELOCITY_AND_TIME_STEWARDSHIP_STANDARD.md`'s "Checklist N/A
handling" rule -- a one-line reason recorded inline, proposed by the Lead
Engineer role and subject to Independent Reviewer challenge, never a
silently unchecked box.

---

_For the engineering rationale behind each item, see SECURITY.md, LESSONS_LEARNED.md, and ARCHITECTURE.md._
