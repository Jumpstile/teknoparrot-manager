# TeknoParrot Manager v1.0 — Release Candidate Checklist

This is the one-time gate for tagging **v1.0**, tracked against the `Version 1.0`
milestone. It is distinct from `RELEASE-SAFETY-CHECKLIST.md`, which governs the
mechanics of every individual release (patch or feature) and remains in effect
for 1.0 and every release after it. This document exists once, is worked
through once, and can be archived (not deleted -- keep it as a historical
record of what "1.0" meant) once v1.0 ships.

No box here should be checked from memory. Each one should be checked because
the specific command, test, or review it names was actually run for this
release candidate.

---

## How to use this document

- Work top to bottom; later sections assume earlier ones are done.
- A box that can't honestly be checked yet is not a formality problem -- it's
  the checklist doing its job. Leave it unchecked and go fix the underlying
  gap.
- Every unchecked box at "final validation" time should trace back to a
  specific open issue or PR in the `Version 1.0` milestone, so there is always
  a single place that answers "what's left."

---

## 1. Engineering

- [ ] Auto-update menu integration (`Invoke-CheckForUpdates`, `Invoke-StartupUpdateCheck`,
      `Invoke-ManagerUpdateInstall`) is merged to `main`, not just open in a PR.
- [ ] Exactly one updater implementation exists per surface: the standalone
      CLI helper (`tools/TpmAutoUpdate.Core.psm1` + `tools/Invoke-TpmAutoUpdate.ps1`)
      and the menu-integrated functions in `TeknoParrot-Manager.ps1`. No second,
      competing module (e.g. a differently-named `tools/TpmAutoUpdate.psm1`)
      exists anywhere in the tree or in an open PR that could be merged over it.
- [ ] The standalone module and the menu-integrated functions still agree on:
      asset name pattern, content-validation checks, read-only pre-check
      behavior, and (once landed) checksum verification. Confirmed by reading
      both side by side, not by assumption.
- [ ] Issue #53 (FATF Drift duplicate wheel-axis propagation) has a merged fix
      **and** real tester confirmation against the actual game, not just a
      passing synthetic regression test.
- [ ] No other issue in the `Version 1.0` milestone remains open without an
      explicit, written decision (in this document or in the issue itself) that
      it is deliberately deferred past 1.0.
- [ ] `LESSONS_LEARNED.md` and `ARCHITECTURE.md` reflect every design decision
      made during 1.0 hardening (auto-update safety findings, control-propagation
      fix, any other change of substance).

## 2. Security

- [ ] SHA-256 checksum verification (or an explicitly accepted equivalent) is
      merged for the auto-updater, using GitHub's native release-asset digest.
- [ ] Read-only pre-check (`Assert-*WritableTarget` / equivalent) is present in
      **every** code path that replaces a file as part of self-update -- CLI
      tool, menu option, and startup check alike.
- [ ] Every module involved in self-update sets `$ErrorActionPreference = 'Stop'`
      explicitly at its own top level (not inherited from import history).
- [ ] `InjectionHunter` has actually been run against the current `main` and
      every finding has been triaged (confirmed false positive with reasoning,
      or fixed) -- not just documented as a requirement.
- [ ] `SECURITY.md`'s threat model section explicitly covers the auto-update
      attack surface (a feature that downloads and replaces the running script)
      and states plainly what it does and does not defend against.
- [ ] A GitHub secret-scanning / dependency-review pass has been considered for
      a public repo approaching a stable release (even if the conclusion is "not
      applicable, no dependencies/secrets exist," that conclusion should be
      written down somewhere, not assumed).

## 3. Testing

- [ ] Full Pester suite passes: `Tests\TeknoParrot-Manager.Tests.ps1`,
      `Tests\TpmAutoUpdate.Core.Tests.ps1`,
      `Tests\TpmAutoUpdate.DestructivePath.Tests.ps1`, `Tests\NoAIAttribution.Tests.ps1`.
- [ ] Destructive-path coverage for the auto-updater is complete for both the
      standalone tool and the menu-integrated version, or an explicit decision
      records why the menu version relies on the standalone tool's coverage
      instead of duplicating it.
- [ ] `Tests\Test-ReleasePackage.ps1` has been run against an actual built
      release ZIP for this candidate, not just reasoned about.
- [ ] `PSScriptAnalyzer -Severity Error,Warning` is clean (using
      `PSScriptAnalyzerSettings.psd1`) against `TeknoParrot-Manager.ps1` **and**
      every file under `tools\`.
- [ ] ASCII purity and parse checks pass against `TeknoParrot-Manager.ps1` and
      every file under `tools\`.
- [ ] At least one real, end-to-end manual test of the auto-updater has been
      performed against a live GitHub release by a human (not just mocked
      Pester runs) -- `-CheckOnly`, a full `-Apply`, and the menu path.
- [ ] Beta-testing discipline ("test one game after each run") has been
      followed for this candidate on a representative library, not just for
      the auto-update feature.

## 4. Documentation

- [ ] README.md, QUICKSTART.md, the `.txt` release docs, and the wiki all
      describe the "Check for Updates" menu option and the
      `CheckForUpdatesOnStartup` config setting consistently.
- [ ] The wiki has a page for the auto-update feature (currently missing --
      verified during the pre-1.0 audit).
- [ ] `docs/AUTO_UPDATE.md` reflects the actually-shipped behavior, including
      checksum verification if merged, and is not describing a design that was
      superseded during review.
- [ ] `docs/Compatibility.md` (if landed) matches implemented behavior and is
      linked from README/wiki.
- [ ] CHANGELOG has one clean, accurate entry for v1.0 summarizing everything
      user-facing that changed since the last BETA tag.
- [ ] Every doc-sweep grep from `CLAUDE.md` (`mode\s+\d+|option\s+\d+` across
      `*.md`, `*.txt`, and the script itself) has been re-run after all 1.0
      changes and returns no stale references.

## 5. Release Packaging

- [ ] `tools\` (or whatever the auto-update feature ultimately needs at
      runtime) is explicitly added to the release-ZIP include list in
      `CLAUDE.md` and `RELEASE-SAFETY-CHECKLIST.md`, and to
      `Tests\Test-ReleasePackage.ps1`'s required-entries list.
      **This is the single most concrete blocker found during the pre-1.0
      audit: as of that audit, a real downloaded release ZIP has no `tools\`
      folder, and "Check for Updates" fails for every real user.**
  - [ ] `Test-ReleasePackage.ps1` is updated to assert the auto-update files
        it now bundles, the same way it asserts `Crosshairs\` today.
- [ ] A release ZIP has actually been built end-to-end (tag → zip → validate)
      for this candidate, and `Test-ReleasePackage.ps1` was run against the
      real artifact, not a hypothetical one.
- [ ] Version drift check: `$ScriptVersion`, the header comment, and every doc
      version string match, and match the git tag about to be created.
- [ ] GitHub Wiki updated for this version bump (see Documentation section).

## 6. GitHub Governance

- [ ] A `v1.0` milestone exists (done) and, at the point of tagging, contains
      zero open issues that weren't explicitly deferred with written rationale.
- [ ] Branch protection on `main` requires the CI status check(s) to pass
      before merge (not just review approval) -- see the CI Expansion Plan.
- [ ] A decision has been made and recorded about `enforce_admins`: whether the
      repo owner should also be bound by branch protection for a 1.0+ repo.
- [ ] CODEOWNERS, PR template, and issue templates exist (see Repository
      Governance recommendations) or an explicit decision has been made that
      they're not needed yet for the current contributor count.
- [ ] No open PR targeting `main` is stale, conflicting, or duplicates
      already-merged work (verify with `gh pr list` + `gh pr view --json mergeable`
      for each, not by assumption).

## 7. Final Validation

- [ ] Every box above is checked, or every unchecked box has a linked issue in
      the `Version 1.0` milestone explaining why it's deliberately deferred.
- [ ] A second person (not the primary implementer of the change being
      validated) has reviewed the auto-update subsystem specifically, given how
      much of 1.0's actual new surface area it represents.
- [ ] Full regression suite, PSScriptAnalyzer, and a real release-ZIP build +
      validation are run one final time against the exact commit being tagged
      -- not against an earlier commit assumed to still be representative.
- [ ] The `Version 1.0` milestone is confirmed empty (or every remaining item
      is explicitly marked "post-1.0" and moved out of the milestone).

## 8. Post-Release Tasks

- [ ] Tag pushed, GitHub release published, release notes match CHANGELOG.
- [ ] Prune-to-5 release-retention policy applied.
- [ ] Announce/forum post updated (per existing project convention).
- [ ] `Version 1.0` milestone closed.
- [ ] This checklist archived (e.g. renamed with the release date) rather than
      left to silently apply to v1.1+ as if it were the ongoing release
      checklist -- that role belongs to `RELEASE-SAFETY-CHECKLIST.md`.
- [ ] A short retrospective added to `LESSONS_LEARNED.md`: what actually
      blocked 1.0 longest, and what process change (if any) would prevent that
      next time.
- [ ] Any issues moved out of the `Version 1.0` milestone during Final
      Validation are re-triaged into a real backlog view (label, next
      milestone, or explicit "post-1.0" tracking) so they aren't simply
      forgotten.
