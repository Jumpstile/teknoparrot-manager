# TeknoParrot Manager -- Lessons Learned

Engineering retrospective notes from real bugs, near-misses, and design decisions
made during this project's development. Each entry links to the relevant version
and issue. These are the cases where the actual outcome differed from the expected
outcome -- the ones most likely to repeat. See PROJECT_IDENTITY_STANDARD.md for
the permanent identity/attribution policy that grew out of one such incident.

## v0.99.40: identity contamination from an unverified environment git config

A working environment's git identity resolved to a non-Jumpstile personal
identity for several commits before being noticed, and a separate,
independently-authored PR reused the same underlying email as its genuine
GitHub account identity -- both landed on public branches (one via a
squash-merge's auto-generated `Co-authored-by:` trailer on `main` itself)
before being caught by a dedicated audit. Root cause: commit identity was
never verified against the expected value before committing; it was assumed
correct because it usually had been. Fixed by rewriting the affected public
history (main and open PR branches, with mirror backups taken first) and by
writing PROJECT_IDENTITY_STANDARD.md, which makes identity verification a
named, required step (Section 5) rather than an assumption. See that
document for the full policy and the compliance checklist now required
before every release.

---

## v0.99.38: Local success does not equal release readiness

**What happened.** The CI pipeline (added in v0.99.36) immediately caught a
Pester failure that local test runs had been silently hiding.
`Describe "Expand-ZipFileSafe"` uses a helper `New-TestZip` that calls
`[System.IO.Compression.ZipArchive]::new(...)`. On the GitHub Actions
runner -- a fresh `powershell.EXE` process with no prior session state --
this threw `RuntimeException: Unable to find type [System.IO.Compression.ZipArchive]`
for all four tests that called the helper.

The first attempted fix (v0.99.37) loaded `System.IO.Compression.FileSystem`
in the top-level `BeforeAll`. This did not fix the failure. The root cause was
an assembly name confusion: `System.IO.Compression.FileSystem.dll` contains
`ZipFile` and `ZipFileExtensions`; `ZipArchive` and `ZipArchiveMode` live in
the SEPARATE assembly `System.IO.Compression.dll`. Loading the FileSystem
assembly does not make `ZipArchive` available, even though the two assemblies
are shipped together and .NET may load `System.IO.Compression.dll` as a
transitive dependency.

Local Pester runs had always passed because interactive development sessions
had previously loaded `System.IO.Compression.dll` -- by building a ZIP,
running the production script, or any other earlier activity in the same
terminal. The assembly stays loaded for the lifetime of the process, so any
later Pester invocation in that session inherited the type for free. The CI
runner starts a pristine process every run; no prior activity loads anything.

**Why independent verification mattered.** The CI failure was caught via an
independent audit (Codex) against the committed code, not via local
re-running. The Codex review surfaced the failures at a point where local
tests showed all-green, providing objective evidence that the code in
the repository was broken even though the development machine was not
reporting it.

**Fix.** The `Describe "Expand-ZipFileSafe"` `BeforeAll` now loads both
assemblies explicitly before `New-TestZip` is defined:
```powershell
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
```
Both calls are idempotent -- if the assembly is already loaded, `Add-Type`
does nothing and returns silently. The Describe is now self-contained
regardless of how the surrounding session arrived at that point.

**Rule.** A change is not considered complete until: (1) local quality gates
pass, (2) the CI pipeline passes on the committed code, and (3) any
independent review findings are resolved. Local success is a necessary
condition, not a sufficient one. The CI runner is the canonical quality gate
because it starts from a known-clean state; local sessions accumulate
in-process state that can mask environmental dependencies.

When writing test helpers that use .NET types, load the assembly that
contains the type explicitly in the same `BeforeAll` that defines the helper
-- do not rely on the production script's own `Add-Type` (top-level script
code, never captured by AST extraction) or on prior session activity. Two
assemblies that appear together in a framework bundle can still have separate
names: confirm the assembly name matches the namespace prefix of the type
you are actually using.

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

**Extension (v0.99.19).** A constant reading as `$null` causes numeric comparisons
to silently pass rather than fail -- PowerShell coerces `$null` to `0` in numeric
context, so every "greater than threshold" check becomes trivially true. When a test
suite produces suspiciously easy "all pass" results for threshold logic, check
whether the threshold constants are actually loaded in test scope.

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

---

## v0.99.6: Split-Path -LiteralPath -Parent throws in PS 5.1

**What happened.** `Split-Path -LiteralPath $x -Parent` throws "Parameter set
cannot be resolved" in PowerShell 5.1. The `-Parent` switch only exists in the
parameter set keyed on `-Path`, not `-LiteralPath`. This is a real PS 5.1
limitation that does not apply to newer PS versions.

**Fix.** Use `[System.IO.Path]::GetDirectoryName()` instead. This is consistent
with how the rest of the script already avoids provider-cmdlet path quirks.

**Rule.** When combining `-LiteralPath` with any of `-Parent`/`-Leaf`/`-Extension`,
check the cmdlet's actual parameter sets first -- not all switches are available
with all path parameter variants.

---

## v0.99.18: Lookup table backfill keyed on the wrong string format (issue #13)

**What happened.** The v0.99.15 fix added a `$RawThrillsPathLimits` backfill to
`Get-StagingFolderMap`, keyed by bare profile code (e.g. `"Cars"`,
`"AliensArmageddon"`). Every caller looks the map up by the ZIP's full base name
(e.g. `"Cars (1.42)(2013-08-28)[Raw Thrills PC][TP]"`). These are completely
different strings. The backfill was never queried by anything -- it silently did
nothing for the real-world case where ZIP filenames include version and date suffixes.
The v0.99.16 follow-up fixed a separate call site but the same root cause: 18 games
in rgecko's collection (the exact size of `$RawThrillsPathLimits`) still showed as
"available to extract" on v0.99.16 despite all 18 being already registered and bound.

**Fix.** `Resolve-RegisteredGameFolder` resolves a ZIP to its real folder via the
collection dat: dat maps the ZIP's normalised name -> `ProfileCode` ->
`UserProfiles\<Code>.xml` -> `GamePath` -> containing folder. Independent of folder
name -- correct as long as the game is already registered.

**Rule.** When adding a lookup table backfill, confirm the EXACT key format callers
use to query it. A backfill keyed on one string format and queried on another is a
silent no-op, not an error. When a supposed fix has no measurable effect on the
reported symptom, re-read the lookup path end-to-end rather than adding another
layer on top of the broken one.

---

## v0.99.20: Write to disk did not update the in-memory cache (issue #1)

**What happened.** `Invoke-ControlPropagation` corrected an archetype's Input API
and wrote it to disk via `Save-XmlMaybe`, but never updated that profile's entry in
the in-memory `$pool` array (built once at function start via `Build-ArchetypePool`).
Every later non-archetype target in the same loop that resolved `$best` to that
archetype read `$best.InputApi` from the stale snapshot. The disk was correct; the
cache was not. Confirmed from tester log timestamps: the canonical correction and the
downstream propagations using the old value landed in the same second of the same run.

**Fix.** One line -- `$selfEntry.InputApi = $canon.InputApi` -- immediately after the
canonical correction's `Save-XmlMaybe` succeeds. `$selfEntry` is the same object
instance held in `$pool` (PowerShell pscustomobjects are reference types), so the
update is visible to every later iteration without restructuring anything.

**Rule.** Whenever a write to disk updates a value that is also cached in a data
structure built before the write, update the in-memory copy immediately after the
write succeeds. The disk and the in-process cache must agree for the remainder of the
same function call.

---

## General: `return @()` unwraps to `$null`; use `return ,@()` when empty vs. null must differ

**What happened (twice).** A function returning `@()` (an empty array) to a caller
that assigned the result to a plain variable received `$null` instead of an empty
array. PowerShell's pipeline unwraps a single-element or empty collection on
assignment. Two separate bugs were traced to this root cause: in both cases,
downstream code that checked `if ($result -eq $null)` took the wrong branch because
a real "found nothing" empty result was indistinguishable from a genuine null/error.

**Fix.** `return ,@()` wraps the empty array in a single-element outer array so
the pipeline delivers it intact as an array. The comma operator is the only guard;
there is no other PS 5.1 mechanism that reliably preserves an empty-array return
through a pipeline assignment.

**Rule.** Whenever a function must distinguish "found nothing (empty result)" from
"did not run / errored ($null)", use `return ,@()` for the empty case. A bare
`return @()` is only safe when the caller always treats `$null` and `@()` identically.

---

## v0.99.28: Doc-sweep grep must include the production script itself

**What happened.** Two stale mode-number references inside the script's own
`Write-Host` prompt strings were never caught by the doc-sweep grep, because that
sweep only targeted `*.md` and `*.txt` files, not `TeknoParrot-Manager.ps1` itself.
The ReShade DLL-not-found prompt said "choose option 5 from the menu" (should be 4)
and the dgVoodoo2 DLL-not-found prompt said "choose option 6" (should be 5) -- the
same off-by-one pattern as the README/QuickStart bug fixed in v0.99.25, but in a
source no one was grepping.

**Fix.** The mode-number grep in `RELEASE-SAFETY-CHECKLIST.md` now explicitly
includes `TeknoParrot-Manager.ps1`:
```powershell
Select-String -Path "*.md","*.txt","TeknoParrot-Manager.ps1" -Pattern 'mode\s+\d+|option\s+\d+' -CaseSensitive:$false
```

**Rule.** After any menu reorder, grep the production script's own embedded strings
with the same pattern used for the external docs. Prompt text in `Write-Host` calls
can contain stale mode numbers just as easily as any .txt or .md file.
