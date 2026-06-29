# TeknoParrot Manager -- Lessons Learned

Engineering retrospective notes from real bugs, near-misses, and design decisions
made during this project's development. Each entry links to the relevant version
and issue. These are the cases where the actual outcome differed from the expected
outcome -- the ones most likely to repeat.

---

## v0.99.33 (issues #41 / #43 / #46 / #47): Capability gating and schema drift

**What happened.** The FFB Blaster setup flow used `Test-FFBBlasterUpToDate` to
decide whether to write a profile. That function answers "does this profile have a
writable Bool field?" -- but it cannot answer "is this platform one where FFB
Blaster actually works?" A pcsx2x6 profile that somehow acquired an FFB
Blaster-shaped field (via upstream schema addition or copy-paste) would have been
written without any platform check.

**What we added.**
- `Get-FFBBlasterSupport`: a structured capability gate returning
  `{Status, Reason, WouldWrite, Eligible, UpToDate, Changes, Platform}`. Only
  `Status = 'Supported'` ever sets `WouldWrite = $true`. The deny-list
  (`$script:FFBBlasterUnsupportedPlatforms`) is checked FIRST -- field presence
  cannot override it. An FFB-Blaster-shaped field with a non-Bool FieldType
  returns `Unknown`, not `Supported`, and `WouldWrite = $false`.
- `Get-GameProfileSchemaDrift`: a pure, read-only diagnostic that classifies a
  profile's structure against a known baseline. Unknown top-level nodes and
  unknown FieldTypes are reported but never acted on; `WouldWrite` is always
  `$false`.

**Rule.** Capability detection must answer TWO questions independently:
"does this profile have the right field?" AND "is this platform one where
the feature works?" A positive answer to the first question alone is not
sufficient to authorize a write.

**Test strategy.** The Pester contexts in
`Describe "Get-FFBBlasterSupport"` include a case where a pcsx2x6 profile
CARRIES an FFB Blaster field and confirms `WouldWrite = $false` anyway. The
schema drift tests include a case where a new FieldType appears and confirms
`WouldWrite = $false`. These are the specific failure modes the tests exist
to prevent, written in the form "here is the thing that would have gone wrong."

---

## v0.99.27: Deserialized types crossing Start-Job boundaries

**What happened.** `Get-LocalDriveInfoSafe` (v0.99.23) returned real
`[System.IO.DriveInfo]` objects out of a `Start-Job` background job.
`Receive-Job` does not reconstruct arbitrary .NET types from a child process --
a real `[System.IO.DriveInfo]` comes back as a `Deserialized.System.IO.DriveInfo`
PSObject, which fails any `[System.IO.DriveInfo[]]` parameter bind.
The original Pester test passed because it bypassed the job boundary by passing
real, in-process objects directly via `-Drives`.

**Fix.** Compute the classification (`DriveType -eq Network`) INSIDE the job
scriptblock where real types are available, and return only plain
`[pscustomobject]` data (`Name`, `IsNetwork` bool). String/bool primitives
survive `Receive-Job` deserialization intact.

**Rule.** Any Pester test for `Invoke-WithHardTimeout`-wrapped logic must go
through the real job at least once, not bypass the boundary with a synthetic
in-process value. A test that only exercises the sunny-path shortcut cannot
catch the type-deserialization failure.

---

## v0.99.24 / v0.99.25: Subagent and external review findings require independent verification

**What happened (twice).** A subagent review and an external (DeepSeek) review
both claimed that `New-PostgresPgPassFile`'s backslash-escaping
(`-replace '\\', '\\'`) was a no-op. In both cases, an empirical check
(input `p:a\ss` -> output `p\:a\\ss`, verified via raw char codes) proved
the escaping was already correct. Applying the "fix" would have reintroduced
the exact quadrupling bug that was already caught and corrected during v0.99.21.

**Rule.** "The agent/review said X" is not the same as "X is true." Every
concrete code claim from a review must be verified empirically against the
actual code before acting. For a claim about a pure function, the fastest
verification is a one-line live test with a concrete input and expected output.

---

## v0.99.12 / v0.99.14: Input API retroactive fix

**What happened.** v0.99.12 attempted to fix an already-bound profile's Input
API by comparing it against a fuzzy-matched archetype. This is wrong in
principle: `Build-ArchetypePool` and the already-bound check both use the same
`$minBound` threshold, so a profile bound well enough to need the retroactive
check IS, by construction, simultaneously a potential archetype. There is no
"already-bound but not an archetype" category that could be safely targeted.
On a real library, the fix flipped 10 archetypes to the wrong API.

**Fix.** Full revert. The safe version (v0.99.17) requires the user to supply
the ground truth via `canonicalArchetype` in the overrides file, rather than
guessing it from button-key overlap.

**Rule.** A heuristic that produces false positives as a write-gating criterion
is not made safe by limiting it to a "smaller" target set if the smaller set is
defined by the same heuristic. A human override mechanism is always preferable
to a heuristic-on-top-of-heuristic stack.

---

## v0.99.8: The ambiguous-exe list was never cross-checked against matched folders

**What happened.** `Register-Games` builds `$matchedFolders` so the "unrecognized
game" list can exclude already-matched folders. The "needs manual registration"
list (`$ambiguous`) was built incrementally in the same loop but never filtered
against `$matchedFolders` before being returned. Alphabetical enumeration meant a
generic exe stub (e.g. `main`) could be added to `$ambiguous` BEFORE the real
named exe in the same folder set `$matchedFolders[$folderKey] = $true` later in
the same pass.

**Fix.** Added a post-loop filter right before `return` that drops any `$ambiguous`
entry whose folder key is by then in `$matchedFolders`.

**Rule.** Any list that exists to report "what still needs work" must be filtered
at the END of the pass against the full set of "what was resolved," not just
as items are added mid-loop. The resolution state is not final until the loop ends.

---

## General: script-scope constants are invisible to the Pester AST extraction

The test harness uses PowerShell AST parsing to load function bodies from the
production script without executing the interactive menu loop. This only extracts
function definitions -- top-level `$script:X = ...` assignments are never loaded.
Functions that read those variables as unqualified names get `$null` in test scope.

Every test session must mirror all relevant script-scope constants in `BeforeAll`
(see the existing mirroring for `$FuzzyAutoThreshold`, `$FuzzyTieMargin`,
`$script:FFBBlasterUnsupportedPlatforms`, etc.). When a new constant is added to
the production script, add the matching mirror to `BeforeAll` in the same commit.

---

## v0.99: PostgreSQL 8.3 silent-install recipe for Incredible Technologies games

**What happened.** Several games (Golden Tee Live, Power Putt Live, Silver
Strike Bowling Live, Target Toss Pro Bags/Lawn Darts, Orange County Choppers
Pinball) need a local PostgreSQL 8.3 database. Getting a fully silent,
unattended install working took several genuine failed attempts on a real
machine, each root-caused via verbose MSI logs rather than guessed.

**Key facts, confirmed the hard way:**
- Target `postgresql-8.3-int.msi` directly, NOT `postgresql-8.3.msi` -- the
  latter is a near-empty UI wrapper with no real Feature/Component data of
  its own; under `/qn` it has nothing to do and fails, since its only job is
  to drive the internal MSI through dialogs in the InstallUISequence, which
  silent mode skips.
- `INTERNALLAUNCH=1` is required to satisfy the internal MSI's own
  `LaunchCondition` (`INTERNALLAUNCH=1 OR Installed`), bypassing the wrapper
  entirely -- found by reading the MSI's LaunchCondition table directly via
  the WindowsInstaller COM API.
- `ROOTDRIVE=C:\` is required -- without it, MSI's drive-selection heuristic
  can pick whatever local drive has the most free space, which would not
  match the hardcoded `C:\Program Files (x86)\PostgreSQL\8.3\` path baked
  into every GameProfile's `Path` field.
- `SERVICEDOMAIN` must be the real computer name, NOT the Win32 "local
  machine" literal `.` -- the install's custom action does its own
  domain\username string handling and does not resolve `.` correctly,
  which manifests as "No mapping between account names and security IDs
  was done."
- The real installed service name is `pgsql-8.3` (DisplayName "PostgreSQL
  Database Server 8.3") -- it does not contain the substring "postgres",
  so detection/cleanup must check for `pgsql-8.3` specifically, not a
  `*postgres*` wildcard. A real bug shipped from checking the wrong name
  and silently never finding the real service.
- A failed/partial install leaves a real local Windows account (`postgres`)
  and an orphaned profile + `ProfileList` registry SID entry behind even
  when the installer itself reports failure -- removing the user alone does
  not clean up the profile folder or registry entry, and a leftover entry
  reproduces the same mapping error on the next attempt.
- The MSI's deferred custom actions log connection passwords in **plaintext**
  in the verbose install log even though the command-line echo masks them --
  the install routine always deletes its entire working folder (ZIP,
  extracted MSI, verbose log) in a `finally` block, success or failure.

**Rule.** For any future MSI-driven silent install: read the MSI's own
LaunchCondition/Property tables directly rather than guessing property
names from documentation, verify the real installed service/display name
empirically rather than assuming it matches the product name, and always
clean up verbose logs that may contain plaintext secrets.
