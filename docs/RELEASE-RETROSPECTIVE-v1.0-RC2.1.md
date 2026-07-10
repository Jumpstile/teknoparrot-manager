# Release Retrospective: v1.0 RC2 -> v1.0 RC2.1

This document is a permanent engineering record of the RC2.1 hardening cycle.
It does not replace `TeknoParrot-Manager-CHANGELOG.txt` (the user-facing
changelog) or `LESSONS_LEARNED.md` (the standing engineering post-mortem
log) -- it is the single retrospective summary of this cycle end to end,
written once, at the end of the cycle, and not intended to be edited to
match later releases. A future release's retrospective is a new file, not
a rewrite of this one.

---

## Executive summary

v1.0 RC2.1 is a release-hardening pass on top of the already-published v1.0
RC2, shipped as a new, separate release rather than a replacement or retag.
It fixes three tester-discovered defects (#132, #134, #136), closes out the
remaining RC2 usability gate items (#111, #119-#122), and formalizes a
mandatory documentation sweep and a concrete release-process standard as
permanent practice going forward. The release was independently verified
twice -- locally and on real arcade hardware by a second AI agent -- before
publication, and certified 9/9 (100%) on real hardware prior to tagging.

## Timeline: RC2 -> RC2.1

- **2026-07-04** -- v1.0 RC2 published (tag `v1.0-RC2`, certified commit
  `15f3400e1f3d200c9df98a86605abff4fe419fe1`).
- **RC2 manual/hardware testing period** -- Eli's real-machine testing and
  Arcade Codex's independent certification runs surface three defects not
  caught by the RC2 gate: #132 (thumbnail download 404s and a stale
  progress overlay), #136 (certification suite can hang during the Pester
  regression phase), and later #134 (inconsistent version display in the
  update checker, found during manual testing of an unrelated flow).
- **RC2 gate reconciliation** -- the remaining open RC2 usability items
  (#111, #119, #120, #121, #122) are investigated; most are found already
  correctly implemented but lacking regression coverage, which is added to
  formally close them.
- **#132 fixed, then refined twice more** on direct tester feedback about
  wording (see "Tester feedback that changed the product" below).
- **#136 investigated, a first fix attempt lands** (heartbeat/timeout
  instrumentation) but a subsequent real-hardware certification run still
  times out -- diagnostics are insufficient to identify the hang source.
- **#136 root cause found independently by two agents** (Claude Code and
  Arcade Codex, working in parallel from different environments) and fixed;
  confirmed on real hardware: CERTIFIED 9/9 (100%), Pester 476/476.
- **Eli approves RC2 for release**, then requests the version label be
  `v1.0-RC2.1` rather than replacing RC2 or a plain RC3, once it's
  discovered `v1.0-RC2` is already an immutable published release.
- **Full documentation sweep performed** as a precondition of packaging --
  surfaces and fixes a pre-existing stale issue reference (#137) and two
  bugs in the release package validator itself, found while validating the
  version-bumped package.
- **2026-07-10** -- v1.0 RC2.1 tagged, packaged, validated, published, and
  asset-verified.

## 1. Release summary

- **Scope of RC2.1:** a release-hardening pass on top of the already-published
  v1.0 RC2 (2026-07-04). RC2.1 does not replace or retag RC2 -- both remain
  published, separate GitHub releases. Scope: thumbnail download reliability
  and messaging (#132), update-check version display consistency (#134),
  certification-suite hang detection and diagnostics (#136), a documentation
  sweep, and closing out the remaining RC2 usability gate items (#111,
  #119-#122). No new user-facing features; the standing feature freeze
  (since v0.97) held throughout.
- **Certified release commit:** `c7c01b7c9a9682b3031e7f36902455d17d9de6e8`
  (real-arcade-hardware certification ran against this commit). The actual
  tagged/published commit, `25c7220aa6dba6d31b60482d39c3fbaf7f688fb7`, is
  `c7c01b7` plus the version bump and documentation sweep only -- no
  functional code changes -- reconfirmed with a full local test run
  (476/476 passed, matching the certified count exactly) before tagging.
- **Git tag:** `v1.0-RC2.1`
- **Release date:** 2026-07-10
- **Certification evidence location:** `E:/Development/TPM-TestHarness/Reports/2026-07-10_05-36-21`
  (real arcade machine, independently run by Arcade Codex)
- **Release URL:** https://github.com/Jumpstile/teknoparrot-manager/releases/tag/v1.0-RC2.1
- **Release ZIP SHA256:** `7056FBE6B6602FA3A940AF1C8983B13CB7327260706D5B1B845A076849E08567`
  (confirmed identical between the locally built, validated package and the
  asset downloaded back from the published GitHub release)

---

## 2. Engineering achievements

- **Independent implementation.** Two independent agents (Claude Code and
  Arcade Codex) worked the same defects in parallel at different points in
  the cycle -- most notably #136, where both independently traced the
  certification hang to the same root cause
  (`Read-MainMenuChoiceResponsive`'s console-input branch bypassing the test
  harness's `Read-Host` fake) before either had seen the other's diagnosis.
  Convergent independent diagnosis of the same root cause is itself
  meaningful evidence the fix targets the real defect, not a plausible-looking
  symptom.
- **Independent verification.** Every fix in this cycle was verified twice:
  once locally (parse/ASCII checks, PSScriptAnalyzer, targeted and full
  Pester runs, and for the #136 fix specifically, an end-to-end run of the
  actual production code path against the real Pester module -- not just
  unit tests of extracted helper functions), and again independently on the
  real arcade machine by Arcade Codex, with the two verification passes
  coordinated over shared commits on `main` rather than divergent branches.
- **Real arcade-machine certification.** The certified commit passed a full
  certification run on real hardware: CERTIFIED 9/9 (100%).
- **Behavioral Certification:** 58/58 passed.
- **Virtual Beta Tester:** all Phase 1/1.5/1.6/1.7 scenarios included in the
  476-test Pester total; the #136 test-harness fix specifically repaired the
  `VirtualBetaTester.HumanWorkflow.Tests.ps1` main-menu suite, which is part
  of this coverage.
- **Package validation:** the release ZIP passed `Test-ReleasePackage.ps1`
  (330 entries, 321 crosshair PNGs, 0 root-level crosshairs, 0 forbidden
  entries, correct packaged version/header/banner identity) -- and the
  validator itself had two real bugs found and fixed during this cycle (see
  section 3).
- **Documentation sweep.** Every tracked `.md`/`.txt` file, the `docs/`
  folder, and the GitHub wiki (Home, Quick-Start, AutoSync, Register,
  Changelog) were reviewed and updated for version identity, stale wording
  that no longer matched shipped behavior (thumbnail messaging, the
  apply-for-real prompt), and a genuine pre-existing defect (see #137
  below). Verified no AI attribution, no placeholder markers, and no other
  stale wording remained.
- **Release provenance.** The certification scorecard (both Markdown and
  JSON) records the certified commit, branch, origin/main sync status,
  working-tree cleanliness, Git/PowerShell/TPM script versions, and
  timestamp -- confirmed already fully implemented and covered by regression
  tests (issue #111) during this cycle's gate reconciliation.
- **SHA256 verification.** The published GitHub release asset was
  downloaded back and hash-compared against the locally validated package
  before the release was left in its final published state, closing the
  loop on "what got built is what got shipped."

---

## 3. Significant bugs fixed

### #132 -- Thumbnail download 404s and stale progress overlay

**Symptom:** after a thumbnail-download batch where downloads failed (most
visibly, every thumbnail 404'd because the online icon pack didn't have
those specific games), TPM left a stale "Downloading Thumbnails /
Invoke-WebRequest: 0 MB downloaded 0 MB/s" progress overlay stuck over the
menu indefinitely.

**Root cause:** each download tier (BITS, HttpClient, Invoke-WebRequest)
raises the `Id 42` `Write-Progress` overlay as it starts, but only each
tier's own *success* path cleared it. Every failure exit -- a 404, a generic
error, or an unexpected exception -- left whatever was last written on
screen permanently, because nothing downstream of that point ever touched
`Id 42` again.

**Fix:** `Invoke-TpmDownload` now wraps its body in a `finally` block that
unconditionally completes the `Id 42` overlay regardless of how the
function exits. Separately, thumbnail messaging was reworded (in two
passes) to stop implying a missing icon means the game is unsupported --
"no icon in the online pack" now, not "not in repo" or "less common or
homebrew" -- and the generic "Download failed" message was suppressed for
the expected-404 case specifically, without weakening it for real failures
elsewhere in the script.

**Lesson learned:** a resource-acquisition/cleanup pattern (raise on start,
clear on success) is incomplete unless cleanup is unconditional. Every
failure exit path needs the same audit as the success path gets by default,
especially for stateful UI like a progress overlay that has no natural
expiry.

### #134 -- Inconsistent Current/Latest version display in update check

**Symptom:** the update checker could show `Current version: v1.0` and
`Latest version: v1.0-RC2` for the exact same release -- the underlying
comparison logic was correct throughout (both were correctly recognized as
equal), but the display was confusing.

**Root cause:** "Current version" was built from `$ScriptVersion` alone,
silently dropping the release-candidate label; "Latest version" printed the
raw GitHub release tag with its dash-separated suffix, never normalized to
this script's own canonical space-separated display shape.

**Fix:** added `ConvertTo-ManagerDisplayVersionFromTag`, converting any raw
tag into the same `"v<version> <LABEL>"` shape already used for the running
script's own display version. Applied everywhere a raw tag was previously
shown to the user.

**Lesson learned:** when two independently-sourced strings are meant to
represent "the same thing" (a running version and a fetched release
version), route both through one shared formatter rather than formatting
each at its own call site -- otherwise they drift apart the moment either
side changes independently, exactly as happened here.

### #136 -- Certification Suite hang during Pester regression phase

**Symptom:** a real, double-clicked certification run could hang
indefinitely during the Pester regression phase, with the process alive,
a report folder created, and no way to distinguish a genuine hang from a
merely slow run -- and no diagnostic content in the saved report
(`Pester-output.txt` was empty) when it did happen.

**Root cause (two independent findings converging on the same defect):**
the main menu's real input path is `Read-MainMenuChoiceResponsive` (issue
#104's responsive menu), which only falls back to `Read-Host` when
`[Console]::IsInputRedirected` is true. A real interactive console --
exactly what a double-clicked certification `.bat` has attached -- takes
the other branch instead: a raw `[Console]::KeyAvailable`/`ReadKey`
polling loop waiting for a keystroke that never comes during an unattended
run. `Tests/VirtualBetaTester.HumanWorkflow.Tests.ps1`'s main-menu test
harness faked `Read-Host` only, never intercepting this branch, so it
always executed the real polling loop once the responsive-menu code
shipped. This also explains why the bug never reproduced in this dev
environment or in CI: any environment whose console happens to be
redirected takes the `Read-Host` fallback and never exercises the buggy
path at all.

**Separately, why diagnostics came back empty:** `Output.Verbosity: 'None'`
(the previous Summary-mode default) meant Pester emitted zero per-test text
to any stream, so nothing could have been captured regardless of which
stream was redirected. Independently, the capture mechanism itself was
also wrong: Pester's live progress text turned out to be written to the
Information stream (6), not the Error stream (2) the code was redirecting
-- confirmed empirically, not assumed.

**Fix:** the test harness now fakes `Read-MainMenuChoiceResponsive` directly
(same nearest-scope-wins pattern as its existing `Read-Host` fake), with a
regression guard so removing that fake fails a fast, clear test instead of
silently reintroducing the hang. The certification runner now runs Pester
on a dedicated in-process runspace (not a background Job, which would lose
object fidelity across a process boundary), polls for a heartbeat every 15
seconds, and enforces a configurable timeout that throws a clear diagnostic
error instead of hanging forever. Verbosity is now always at least
`Detailed` internally and captured via the Information stream, confirmed
not to additionally echo to the live console even in Summary mode.

**Bonus bug caught during verification:** `BeginInvoke`/`EndInvoke` returns
a `PSDataCollection[PSObject]`, which is not `-is [array]` -- the existing
result-unwrapping logic branches on that check, so without wrapping the
return in `@()`, every field in the Pester summary would have silently come
back `$null` even on a normal passing run. Found by running the real
production code path end-to-end against the actual Pester module, not by
code review alone.

**Lesson learned (see also `LESSONS_LEARNED.md`):** a test harness that
fakes a production input function is coupled to *how* input currently
flows, not just *that* input is provided. When production code adds a new
input path with its own fallback logic, the fake must be re-verified
against the new path -- a harness that "still passes" after a refactor is
not proof the input seam is intact, only that the code path it happens to
exercise hasn't changed.

### #137 -- Stale feedback-tracking issue reference (found during the doc sweep, not filed as a bug)

Not a code defect, but worth recording: `README.md` had cited issue #102 as
"the v1.0 RC2 feedback tracking issue" since RC2 first shipped. #102 is
explicitly scoped to RC1 only ("Track only reports that reproduce on v1.0
RC1 specifically"). No RC2 (or RC2.1) tracking issue existed at all --
#137 was filed to close that gap and README.md's reference was corrected.

**Lesson learned:** a doc-sweep gate that only checks "does the version
number match" will not catch a wrong *link target* -- the string can be
perfectly current while pointing at content that's actually scoped to a
different release. Verifying a linked issue's actual scope, not just its
existence, needs to be part of the sweep.

### Other meaningful RC2.1 fixes

- **#119** -- the Overrides diagnostic summary line (already gated to only
  appear when something is actually configured) printed raw internal
  config-key names with no explanation. Now explains what the settings mean
  and what action to take, in plain language.
- **Package validator, two separate bugs found and fixed same-cycle:**
  `Test-ReleasePackage.ps1` checked a literal banner string that no longer
  existed after the FIGlet banner refactor (fixed in commit `88a4235`), and
  separately hardcoded the release-candidate label to the literal `"RC2"`,
  which broke validation the moment the version bumped to RC2.1 (fixed in
  commit `25c7220`, now derived from the `-ExpectedDisplayVersion` parameter
  so it cannot drift out of sync again on the next release).
- **Preview "apply for real" prompt wording** -- reworded to explain that
  applying performs a fresh scan, not a replay of the preview, since state
  could have changed since the preview ran. A UX clarity request, not a
  discovered defect, but shipped in the same cycle.

---

## Tester feedback that changed the product

Beyond surfacing #132/#134/#136 in the first place, direct in-session
feedback shaped how those fixes actually read to a real user, through more
than one iteration:

- An initial #132 wording fix used the phrase "profile code" without
  explanation; feedback ("won't know what a profile code is") led to a pass
  rewriting every thumbnail-related console message in plain English, with
  the technical term kept in parentheses for advanced users who want it
  ("write the technical term in parenthesis so an advanced user can have
  it") -- rather than removing it, which would have made the messages less
  useful to a tester cross-referencing `TeknoParrot-Manager-controls.txt`.
- A follow-up round of feedback rejected the phrase "less common or
  homebrew games" for games with no online icon available, on the grounds
  that it wrongly implied those games were somehow non-standard or
  unsupported -- the actual product wording was changed to make clear a
  missing icon reflects a gap in the online icon pack, not a limitation of
  the game or TPM's support for it. This is now the standing wording used
  everywhere the product describes an item as "not available" rather than
  "broken" or "unsupported."
- The RC2.1 version label itself was tester-directed, not engineering-
  decided: an initial assumption that this would tag as a fresh `v1.0-RC2`
  was corrected on discovering that tag was already an immutable published
  release, and the choice between `v1.0-RC3` and a patch-style
  `v1.0-RC2.1` was made by the Release Manager, not inferred.

## 4. Release process improvements

The following became, or were confirmed as, the permanent release workflow
during this cycle:

- **Certification.** Real-hardware certification via
  `scripts\Run-TPM-Certification-Suite.bat`, producing a CERTIFIED/NOT
  CERTIFIED scorecard with full Git/version provenance (issue #111). The
  certification suite's Pester regression gate now has live heartbeat
  progress and a hard timeout (issue #136), so a future hang fails cleanly
  with a diagnosable reason instead of blocking a certification run
  indefinitely.
- **Documentation sweep.** Formalized this cycle as a mandatory,
  now-permanent release gate covering every `*.md`, every `*.txt`, `docs/`,
  the GitHub wiki, version numbers, in-app wording that changed, and a check
  for AI attribution, placeholder text, broken links, and obsolete issue
  references. This is now standing practice for every release, not a
  one-time RC2.1 activity.
- **Package validation.** `Test-ReleasePackage.ps1` checks ZIP structure
  (required entries, crosshair PNG count and location, forbidden entries)
  and packaged-script release identity (header, `$ReleaseCandidateLabel`,
  banner) before any release is published. The two validator bugs found
  this cycle were fixed so the same class of drift is structurally harder to
  reintroduce (the label check is now derived from the version parameter
  instead of separately hardcoded).
- **Release verification.** Tag created only after all checks pass; GitHub
  release created as a draft first and only published after the asset is
  confirmed attached and correct, per the standing rule that a non-draft
  release immediately and permanently locks the tag name and assets.
- **Artifact verification.** The published release asset is downloaded back
  and SHA256-compared against the locally validated package before
  considering the release complete -- not just trusting that the upload
  succeeded.
- **Independent review.** This cycle ran with two independent agents
  (Claude Code locally, Arcade Codex on the real arcade machine)
  cross-checking each other's diagnoses and fixes over shared commits on
  `main`, including one explicit coordination point where both had
  independently produced uncommitted fixes for the same root cause (#136)
  and one was designated canonical to avoid a conflicting merge.

---

## 5. Lessons learned

**What worked well:**

- Empirical verification caught real bugs that code review alone would have
  missed or misjudged: the `PSDataCollection` array-unwrapping bug (#136),
  the actual stream carrying Pester's live output (Information, not Error),
  and an initially-suspected #111 gap that turned out to be a false alarm
  from an imprecise `grep` -- corrected before an unnecessary change was
  made, rather than after.
- Independent parallel verification (two agents, real hardware plus local)
  surfaced the #136 root cause faster and with higher confidence than either
  working alone would have, and caught the coordination risk (competing
  uncommitted fixes) before it became a merge conflict.
- Treating "already implemented but untested" as a real gap (issues #120,
  #121, #122, #111) rather than assuming code-complete meant tested was a
  useful distinction -- all four closed cleanly with regression coverage
  added, no behavior changes needed.

**What should change before 1.0:**

- The documentation sweep should have been a standing gate from the start
  of RC2, not formalized only during RC2.1 -- the stale #102 reference and
  the stale thumbnail/prompt wording in `.txt`/wiki docs both existed
  because a version bump updated the script but not every doc that quoted
  its behavior. This is now fixed as a permanent gate, but the underlying
  pattern (docs quoting exact console wording that then changes) is worth
  watching for in every future wording change, not just release-time sweeps.
  Consider a lighter-weight check (grep for known volatile-wording anchors)
  that can run more often than a full release sweep.
- Test harnesses that fake a production input/output seam (the #136 root
  cause) need an explicit, cheap regression guard confirming the fake is
  still intercepting the *current* production code path -- not just that
  the tests using it still pass. This is now in place for the one harness
  that broke; worth auditing whether any other test harness in the suite
  has the same latent risk.
- Package-validator hardcoded expectations (the two bugs found this cycle)
  suggest a general pattern: any test or validator that encodes "the
  current version" as a separate literal, rather than deriving it from a
  single source of truth, will drift on the next version bump. Worth a
  one-time audit of the whole test suite for other instances of this
  pattern before 1.0, rather than finding them one release at a time.

---

## 6. Recommendations for Version 1.0

Highest-priority remaining work, in rough priority order:

1. **Close the remaining RC2 gate items.** #104 (adaptive main menu) and
   #123 (verify the responsive-menu behavior against the real build) are
   still open pending a human read on real hardware -- this is the last
   piece of the original RC2 usability gate (#124) that hasn't closed.
2. **Confirm #132 on real hardware.** The thumbnail/progress-bar fix has
   shipped and been verified by automated tests, but per this project's own
   standing rule, a UX/visual fix like this still needs a human look on the
   real machine before the underlying issue closes.
3. **Audit for the "hardcoded current-version literal" pattern** described
   in section 5, across the full test suite, proactively rather than
   reactively.
4. **Consider the general "test harness fake staleness" pattern** from the
   #136 lesson: identify any other harness in the suite faking a production
   seam, and add the same kind of "is this fake still intercepting the real
   path" regression guard preemptively.
5. Once #104/#123/#132 close and #124 (the RC2 release gate) closes, 1.0
   itself requires explicit Release Manager authorization to drop the RC
   designation, per `CONSTITUTION.md`'s "Release governance: technical
   readiness is not release authorization" -- technical readiness alone,
   however thorough the certification evidence, is not sufficient on its
   own for that decision.
