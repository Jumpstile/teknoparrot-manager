# TeknoParrot Manager -- Lessons Learned

Engineering retrospective notes from real bugs, near-misses, and design decisions
made during this project's development. Each entry links to the relevant version
and issue. These are the cases where the actual outcome differed from the expected
outcome -- the ones most likely to repeat.

---

## Governance exception: PR #87, #89, #91 merged by admin override (branch protection required 1 review)

**What happened.** `main`'s branch protection requires 1 approving review before
merge. PR #87 (pcsx2x6 fix, in-script auto-update hardening, TPM Certification
Suite fixes), PR #89 (a follow-up `$ScriptVersion` correction), and PR #91
(Issue #88 phase 1 Virtual Beta Tester coverage) were all authored and merged
by the same AI assistant session across one conversation. GitHub blocks
self-approval outright (`Can not approve your own pull request`), and no
separate Independent Reviewer account was configured for this repository at
the time. All three PRs were merged via `gh pr merge --admin`, bypassing the
required-review check, after explicit repository-owner authorization to
proceed with each specific merge -- for PR #91, the owner was explicitly
presented with the choice between reviewing it themselves or repeating the
admin override, and chose the override with the tradeoff stated plainly.

**Why this was judged acceptable in the moment.** CI (ASCII/parse/PSScriptAnalyzer/
Pester via `.github/workflows/ci.yml`) was green on all three PRs before merge.
This work is normal engineering (bug fixes, a version-string correction, and
new test coverage), not a production-release action under the Release
Governance Standard, so it did not require Release Manager sign-off on *what*
to merge -- only the *mechanism* (admin override instead of a genuine
independent review) was an exception to the standing workflow.
Real-arcade-machine certification was run after each merge against the exact
merged commit and returned CERTIFIED every time: 8/8 (100%) for PR #87/#89's
commit (`a85aa269`), 9/9 (100%) for PR #91's commit (`aa99b945`, including the
new Virtual Beta Tester gate) -- strong evidence the bypassed review didn't let
anything broken through in any of the three instances.

**Why this is still recorded as an exception, not a pattern -- and why three
instances is a stronger signal than one.** "CI was green" and "certification
passed afterward" are both evidence the change was *probably* safe -- they are
not a substitute for an actual second set of eyes before merge, which is the
entire point of requiring a review. Getting away with it three times in a row
is not the same as the practice being sound; if anything, three consecutive
instances without a single genuine review is exactly the pattern this entry
originally warned against becoming. Per `CONSTITUTION.md`'s "Release
governance: technical readiness is not release authorization" section,
"Recommendation authority" subsection ("Any engineering role may recommend
release readiness. Only the Release Manager may authorize a production
release" -- and, by the same logic, only an actual reviewer authorizes
bypassing a review requirement), normal PR review remains the standing
rule. This entry exists so a future session
doesn't read "admin override was used successfully, repeatedly" in the git
history and conclude it's a normal or preferred path.

**What should happen instead going forward.** Either configure a genuine
second reviewer (a human, or an independent AI reviewer account distinct from
the one authoring the PR) so self-approval is never the blocker, or route
merge decisions through the repository owner directly rather than an
AI-invoked admin override, even when the owner has authorized the specific
change being merged. Three instances in one session is the point at which
this stops being a reasonable one-off exception and starts being a real gap
in the review pipeline that should be fixed before a fourth instance, not
documented again.

**Resolution.** The independent-reviewer account this entry called for
was configured (Regular Codex, used as the documented external review
workflow across this session and since). `CONSTITUTION.md`'s
"Single-Maintainer Governance" section formalizes the underlying policy
this entry's recommendation implied: Independent Review Required is
satisfied by that documented external workflow, not by a GitHub approving
review this repository's sole maintainer cannot submit; `main`'s
required-approving-review branch protection was set to zero for exactly
this reason (GitHub's self-approval restriction, not a relaxation of the
review requirement itself), with `main`'s CI ("Quality gates") made an
explicitly *required* status check in the same change, so the admin-
override pattern this entry warned against is no longer the mechanism
this condition is handled by.

## TPM Certification Suite (commit bb2a160): [scriptblock]::Create() dot-sourcing breaks cross-file Pester module mocking

**What happened.** A real arcade-machine certification run reported 10 Pester
failures, all in `Tests/TpmAutoUpdate.DestructivePath.Tests.ps1`, all with the
same shape: `Response status code does not indicate success: 403 (rate limit
exceeded)`. That file's `Mock -ModuleName TpmAutoUpdate.Core Get-LatestRelease`
had stopped intercepting calls, letting the real (unmocked) call through to
GitHub's API. Local reruns of that file alone, and in various smaller
combinations with other test files, passed cleanly every time -- it only
failed when the *full* `Tests/` folder ran together, which is exactly how
`scripts/Invoke-TPM-RealInstanceSmoke.ps1` invokes Pester for a real
certification run.

**Root cause, isolated by bisection, not guessed.** `Tests/TPMCertificationHarness.Tests.ps1`
extracts functions from `Invoke-TPM-RealInstanceSmoke.ps1` via AST (the same
technique `Tests/TeknoParrot-Manager.Tests.ps1` uses for the main script,
since neither file can be dot-sourced directly -- both have top-level
executable code). The extraction dot-sourced each function with:
```powershell
. ([scriptblock]::Create($fn.Extent.Text))
```
When this file ran in the same Pester invocation as
`Tests/TpmAutoUpdate.DestructivePath.Tests.ps1`, that file's module-scoped
mock stopped working. Confirmed step by step:
- Reproduced with a single trivial, unrelated function
  (`function Get-TotallyUnrelatedThing { ... }`) dot-sourced the same way in
  an otherwise-empty file -- not specific to anything `TPMCertificationHarness.Tests.ps1`'s
  own functions do.
- The same dot-source using a literal `{ function ... }` scriptblock instead
  of `[scriptblock]::Create()` did **not** reproduce it.
- `Tests/TeknoParrot-Manager.Tests.ps1` uses the identical
  `[scriptblock]::Create()` extraction pattern and does **not** break the
  same mock when paired with the same destructive-path file -- so this is
  not a blanket "never use `[scriptblock]::Create()` in this repo" rule, it
  is specific to this exact file combination and needs re-verification if
  either file's extraction approach changes.

The mechanism itself (why a *runtime-constructed-from-string* scriptblock's
dot-sourcing behaves differently from a *literal* scriptblock's with respect
to Pester's module-scoped mock session state) was not fully root-caused at
the PowerShell-internals level -- confirming the reproducible trigger and a
verified fix was judged sufficient given the cost of digging further into
Pester/PowerShell scoping internals.

**Fix.** `Tests/TPMCertificationHarness.Tests.ps1`'s `BeforeAll` now writes
the extracted function text to a real temporary `.ps1` file (under
`$TestDrive`, so Pester cleans it up automatically) and dot-sources that
file instead of a runtime-created scriptblock:
```powershell
$extractedPath = Join-Path $TestDrive ("harness-functions-" + [guid]::NewGuid().ToString('N') + '.ps1')
($functionAsts | ForEach-Object { $_.Extent.Text }) -join "`n`n" | Set-Content -LiteralPath $extractedPath -Encoding utf8
. $extractedPath
```
Verified against the full `Tests/` folder: 321/321 passing, where it
previously failed 311-312/321 on every run that included both files.

**Rule.** When a test file needs to dot-source dynamically-extracted
PowerShell source (AST-extracted functions, or any other runtime-assembled
code), write it to a real temp file and dot-source the file -- do not
dot-source a `[scriptblock]::Create()` result, even though it looks
equivalent and is more convenient. This is not a stylistic preference: it is
a verified fix for a real, reproduced cross-file Pester mock-isolation
failure that only shows up when running the full test suite together, not
any single file in isolation. Do not "simplify" this back to
`[scriptblock]::Create()` without re-running the full `Tests/` folder (not
just the file being changed) to confirm `Tests/TpmAutoUpdate.DestructivePath.Tests.ps1`
and `Tests/TpmAutoUpdate.Core.Tests.ps1` still pass -- a local single-file
test run will not catch this regression, since it only manifests in
combination.

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

The production startup has the same explicit two-assembly bootstrap before
`Expand-ReShadeSelfExtractingArchive` can reference `ZipArchive` or
`ZipArchiveMode`. This is required for a pristine Windows PowerShell 5.1
process: loading `System.IO.Compression.FileSystem` alone resolves the
`ZipFile` APIs but does not resolve the archive types in the separate
`System.IO.Compression` assembly. The regression test launches a fresh PS 5.1
child process and resolves both API families, so local assembly residue cannot
hide a release-only extraction failure.

The same rule applies to standard security/hash commands. A packaged launcher
must not rely on ambient module autoloading for `Get-AuthenticodeSignature` or
`Get-FileHash`: a host can disable autoloading while still allowing the script to
start. The production bootstrap now imports `Microsoft.PowerShell.Security`,
`Microsoft.PowerShell.Management`, and `Microsoft.PowerShell.Utility` explicitly,
and a fresh PS 5.1 child-process test disables autoloading, invokes both commands,
and verifies the digest result. This
keeps the existing ReShade status/thumbprint gate and SHA-256 verification intact.

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

---

## v1.0 RC2.1: a test harness's input fake can go stale silently when the real
input mechanism changes underneath it (issue #136)

**What happened.** The TPM Certification Suite could hang indefinitely during
the Pester regression phase, with no diagnostics -- process alive, report
folder created, nothing ever completing. It reproduced reliably on a real
double-clicked certification run but never in this dev environment or in any
prior CI run.

Root cause: `Tests/VirtualBetaTester.HumanWorkflow.Tests.ps1`'s main-menu test
harness faked `Read-Host` to drive scripted menu choices. That worked when the
main menu read input via `Read-Host` directly. Once issue #104's responsive
menu shipped, real input moved to `Read-MainMenuChoiceResponsive`, which only
falls back to `Read-Host` when `[Console]::IsInputRedirected` is true. A real
interactive console -- exactly what a double-clicked certification `.bat` has
attached -- takes the other branch instead: a raw `[Console]::KeyAvailable`/
`ReadKey` polling loop waiting for a keystroke that never comes during an
unattended run. The harness's `Read-Host` fake never intercepted that branch,
so the extracted menu code always executed the real polling loop and hung.
This also explains the "works here, hangs there" split: any environment whose
console happens to be redirected (this dev environment, most CI runners)
takes the `Read-Host` fallback and never reproduces the bug at all.

**Fix.** The harness now fakes `Read-MainMenuChoiceResponsive` directly (same
nearest-scope-wins pattern as its existing `Read-Host` fake), plus a
regression guard so removing that fake fails a fast, clear test instead of
silently reintroducing the hang. Separately, the certification runner's
Pester-output capture was fixed to actually receive live progress
(`Output.Verbosity: 'None'` at the previous Summary default meant nothing was
ever captured regardless of which stream was redirected; Pester's live text
turned out to be on the Information stream, not the Error stream the code was
redirecting) and gained a heartbeat/timeout so a real hang fails cleanly with
a diagnosable reason instead of blocking the whole certification run forever.

**Rule.** A test harness that fakes a production input function (`Read-Host`,
or anything else standing in for real user input) is coupled to *how* input
currently flows, not just *that* input is provided. When production code adds
a new input path with its own fallback logic, the fake must be verified
against the new path too -- a harness that "still passes" after a refactor is
not proof the input seam is still intact, only that the code path it happens
to exercise hasn't changed. Add a source-level regression guard asserting the
fake actually exists for the specific function currently in use, so a future
refactor away from it fails fast instead of reintroducing a silent, hard-to-
reproduce hang.

---

## Short-viewport menu truncation dropped the footer and Exit, not the content that should give first (issue #104, RC3 correction)

**What failed.** `Render-MainMenuScreen` built one flat list -- banner rows,
then body rows, then footer rows -- and `Limit-MainMenuRowsToViewport`
truncated that combined list to `Select-Object -First $maxRows` whenever it
overflowed the viewport height. At a short console height this kept the
*front* of the render (the banner and the earliest menu sections) and
silently dropped whatever didn't fit off the *end* -- which, because the
footer (Quit/Help controls) and the Application section (option 14, Exit)
are built last, meant exactly the controls a user needs to actually operate
the menu were the first things to disappear. A pre-existing Pester test even
asserted this as intentional (`Should -Not -Match 'Exit'` on a short-viewport
render), so the behavior passed its own regression suite while being wrong.
Caught by an independent review of PR #145, not by the test suite, which had
codified the bug as the expected result.

**Fix.** Banner, body, and footer rows are now built and reserved
separately. The footer is never truncated. If the body doesn't fit the
remaining budget, `Limit-MainMenuBodyRowsToBudget` trims BODY rows only, and
trims from the *front* (keeping the tail) specifically so the last real menu
item survives -- the opposite truncation direction from before. The Compact
tier's "Type ? for descriptions." hint (a purely decorative line) was also
moved from the end of the body to the beginning, because it was winning the
tail-preservation priority over the actual "14) Exit" line by virtue of
render order alone, not by design.

**Rule.** When a render pipeline has to drop content to fit a viewport,
truncation direction is a product decision, not an implementation detail --
"keep the front" and "keep the back" are both defensible defaults depending
on what's most essential, but the essential content (here: the controls
needed to operate the UI at all) must be identified explicitly and protected,
never left to whichever end of a flat list happens to survive. A test that
asserts truncation drops specific named content should be treated as a
signal to double-check that dropping it is actually the intended behavior,
not just documentation of whatever the code currently does.

---

## Reserving the footer wasn't enough at 60x10; a Pester closure gap made a real defect invisible (issue #104 RC3-B)

**What failed, part 1: reserving the footer alone still dropped every option.**
The RC3 fix above (reserve the footer, trim body from the front) assumed there
would always be *some* row budget left for body content. At the documented
minimum supported viewport, 60x10, that assumption was wrong: the framed
banner (6 rows) and footer (2 rows) alone consumed the entire 8-row budget,
leaving zero rows for ANY body content -- not just early items, everything,
including option 14 (Exit). The packaged diagnostic (`scripts\Debug-TPM-
MenuLayout.ps1`) made this directly visible once its own separate crash
(below) was fixed: `-Width 60 -Height 10 -Render` rendered only a banner and
a footer, with nothing in between.

**Fix.** `Get-MainMenuEmergencyCompactRows` is a genuinely different
presentation for viewports too short for one-item-per-row rendering, not a
tighter version of the same layout: single-line banner and footer (no frame,
no blank separator) free up several rows, and every option's `"N) Label"` is
flow-packed as densely as the width allows instead of one per row. Tokens are
packed whole (never split a number from its own label across two lines), and
if even that doesn't fit, item rows trim from the front so the last item
(ending in `14) Exit`) and the footer survive over the earliest options.

**What failed, part 2: the packaged diagnostic script drifted from the
render pipeline it exists to debug.** `scripts\Debug-TPM-MenuLayout.ps1`
loaded only a hand-maintained list of "the menu functions this diagnostic
needs" via AST extraction. The moment `Limit-MainMenuBodyRowsToBudget` was
added (the RC3 fix above), the diagnostic was never updated to know about
it, and crashed with `CommandNotFoundException` the instant `-Render`
exercised the render pipeline. A pre-existing Pester test that ran the
diagnostic (`& $debugScript ... -Render`) did not catch this: `&` runs in a
child scope of the *current* Pester process, which already had every
production function -- including the new one -- dot-sourced into it by this
test file's own top-level `BeforeAll`, so the missing function was invisibly
supplied by the test session itself, not the diagnostic script's own code.

**Fix.** The diagnostic now loads every function definition from the
production script via AST extraction (the same pattern the Pester suites
already use), not a hand-maintained allowlist, so it cannot drift out of
sync with new dependencies again. Regression coverage was added as a
genuinely separate child PROCESS (`pwsh -File` / `powershell.exe -File`),
not an in-process `&` call, specifically because the in-process form cannot
detect this class of missing-dependency bug -- confirmed by running the new
process-isolated tests against the pre-fix diagnostic and watching them fail
with the real error, then pass after the fix.

**What failed, part 3: a `foreach ($x in ...) { It ... { ...$x... } }` loop
variable is invisible inside the `It` body when Pester actually runs it.**
Discovered while writing regression tests for the 60x10 fix above, then
found to already be silently broken in a test committed earlier in the same
work (`Tests\InstallHealthCheck.Tests.ps1`'s six special-folder-name tests).
Confirmed by isolated repro: a scriptblock's own `It` TITLE is built at
Pester's Discovery phase and correctly shows the loop's per-iteration value
(discovery re-executes the whole container script top to bottom), but the
`It` BODY runs later in Pester's own scope chain, which does not inherit a
loop variable from the surrounding `Describe`/`Context` body at all -- only
`$script:` values assigned in an enclosing `BeforeAll`/`BeforeEach` are
visible there. The practical effect: the folder-name tests' bodies all read
an empty string for the loop variable, and because `Join-Path $TestDrive ''`
harmlessly resolves to `$TestDrive` itself, all six tests "passed" while
silently testing the exact same directory instead of six distinct
special-character folder names -- a false negative with a passing test
suite as the only visible signal that anything was wrong.

**Fix.** Both cases (the 60x10 height boundaries and the folder-name tests)
were rewritten to use Pester's `-TestCases` parameter, which passes each
case's values into the `It` scriptblock as real bound parameters instead of
relying on a closure. The folder-name rewrite also added an explicit
assertion (`(Split-Path -Leaf $dir) | Should -Be $FolderName`) proving each
iteration actually exercised its own distinct value, specifically so a
future regression of this class fails loudly instead of silently passing
again.

**Rule.** Never write `foreach ($x in $cases) { It "..." { ...$x... } }` in
this codebase's Pester suites -- it is silently broken in the Pester/
PowerShell version combination this project uses, and a broken instance of
it does not fail; it passes while testing the wrong thing. Use `It "..."
-TestCases @(...) { param($x) ... }` for any parameterized test instead.
When reviewing a loop-generated set of tests, check that each one asserts
something which would actually be FALSE if every iteration were silently
testing the same value -- a title alone (built at Discovery time, always
correct) is not evidence the body executed correctly.


## Issue #154 -- parameter validation can bypass controlled failure paths

A wrapper forwarded an omitted optional EvidenceType as an explicit empty string. ValidateSet rejected it before the callee body could return its intended Skipped/Failed record, aborting arcade certification during evidence finalization. For internal transaction metadata, validate inside the function and return structured failure evidence; wrappers must not forward capture-only parameters on skip paths. A required final artifact may remain outside numeric scoring, but failure must still force the overall certification outcome to NOT CERTIFIED.


## Issue #154 follow-up -- finalization must be one transaction

Fixing a parameter-binding crash was insufficient because evidence, scorecard outcome, report status, and process exit were still independent. A certification pipeline needs a formal manifest and one final authority. Intermediate gate arithmetic is eligibility, not certification. Finalization must validate the complete accumulated evidence set, reject missing/duplicate/substituted records, and propagate one outcome object to every human- and machine-readable output and the process exit code.

## Issue #154 round 2 -- a single authority still trusted mutable state around itself

Making one function the outcome authority was necessary but not sufficient: the authority itself still trusted several mutable inputs instead of deriving or enforcing them. Three concrete gaps, found by treating the pipeline as a database transaction rather than patching individual review findings: (1) evidence records had no capture-order field at all, so "the final screenshot was captured last" was true only because of source-code call order, not because anything checked it; (2) the transaction read `$Certification.Overall` -- a field set once at scorecard-construction time -- instead of recomputing the score from `$Certification.Items` itself, so a future code path that mutated `Items` without also updating `Overall` would have gone undetected; (3) publication happened as a separate step after the transaction returned, with the caller hardcoding its own duplicate FAIL/NOT CERTIFIED/exit-1 logic on a publish failure -- two independent places that had to agree about what "publish failed" means, rather than one.

The fix in each case was not "add a check" but "stop trusting the mutable thing and make the authoritative fact the only thing consulted": a monotonic Sequence assigned once, at the single ledger-append point, that the transaction can assert against directly; a single pure scoring function (`Get-TPMCertificationScoreFromItems`) that both the provisional display and the real commit decision call independently against the same immutable `Items`, so they can never diverge; and folding `Publish-TPMCertificationArtifacts` into `Complete-TPMCertificationTransaction` itself (via a `-BuildArtifacts` callback) so a publish failure downgrades the one object every consumer already reads, instead of being decided a second time by the caller. Generalizes to: when review findings keep recurring in the same subsystem, check whether the "authority" still reads any field it did not itself derive from an immutable fact -- that is usually where the next finding will come from.

## Issue #154 round 3 -- deriving state from a mutable field is not the same as trusting an unforgeable fact

Round 2 fixed the "trusted a stale field" class of gap, but the fields it started deriving from instead -- `$Results.Screenshots`, `$Certification.Items`, a `Sequence` property read back off an object -- were still ordinary, externally-mutable objects. Nothing stopped a caller (or an adversarial test standing in for one) from constructing a brand-new object with every field copied from a real record, including `WorkflowId` and `Sequence`, and getting it accepted: the transaction was checking whether a record's fields *described* legitimate evidence, not whether the record actually *was* the object the workflow produced. "Derive from Items instead of Overall" was real progress, but Items itself was still just as forgeable as Overall had been -- deriving from a mutable-but-plausible-looking fact is not the same fix as deriving from something that cannot be reconstructed by copying.

The fix that actually closes this: move the ground truth into a structure the transaction owns and never receives as a parameter to trust -- a private, workflow-populated issuance ledger (`$script:tpmEvidenceLedger`) -- and validate the caller-submitted description of evidence against it by reference identity (`[object]::ReferenceEquals`), not by re-checking fields. A copied object, however faithful, is a different object; reference identity is the one property that cannot be forged by knowing what a real record looks like. The same logic applied to score items (an exact, closed manifest validated before the numbers are trusted at all) and to publication (a mandatory, manifest-validated artifact set with a durably-verified commit marker, rather than an optional callback whose mere presence was treated as success). Generalizes further from round 2's lesson: after fixing "the authority trusts a stale field," check whether it now trusts a *fresh but still copyable* field instead -- the next question is never "is this the right field," it is "could an attacker who only sees the public shape of this object produce a convincing one," and if the answer is yes, the fix is a structural ownership boundary, not another validation rule.

## ADR155-0309 Checkpoint B1 -- nested Import-Module does not propagate visibility to a sibling module

`Test-TPMArtifactsPreflightV1`-style `Get-Command` checks for Reports/Publication commands returned false in a real harness even though every prior test run returned true. The real harness imports Shadow.psm1, Production.psm1, then Orchestration.psm1 (which imports Reports/Publication internally); every test and manual smoke session had imported Reports.psm1/Publication.psm1 directly alongside Production.psm1, masking the gap. A nested `Import-Module` call from within one module does not reliably expose that module's imports to a sibling module's own `Get-Command` calls in this environment -- confirmed empirically, not assumed. Fix: every module that genuinely depends on another module's exports must `Import-Module` it directly at its own top, never assume some other already-imported module already pulled it in. Generalizes: when a dependency check (`Get-Command`, `Get-Module`) passes in every test session but might fail in the real harness's actual import order, treat the two import orders as different until proven otherwise -- test with the exact import sequence production code uses, not whatever a test's `BeforeAll` happens to import.

## ADR155-0309 Checkpoint B1 -- Windows PowerShell 5.1 Start-Process -PassThru does not reliably populate .ExitCode

A `Start-Process -ArgumentList ... -PassThru` object's `.ExitCode` property read back `$null` on Windows PowerShell 5.1 even after the child process had genuinely exited normally (confirmed with `WaitForExit()` returning `$true`) -- reproducible every time on this build, not intermittent. pwsh 7.6.4 did not show the issue. Fix: call `[void]$proc.Handle` immediately after `Start-Process` returns, before `WaitForExit()` -- this appears to force some lazy internal state (`SafeProcessHandle`) that `.ExitCode` depends on to populate. Harmless to do unconditionally on both engines. Rule: any code path that reads `.ExitCode` off a `Start-Process -PassThru` object must touch `.Handle` first if it needs to run correctly under Windows PowerShell 5.1, not just pwsh.

## ADR155-0309 Checkpoint B1 -- Start-Process -ArgumentList does not quote elements containing spaces/metacharacters

An array passed to `Start-Process -ArgumentList` is joined with plain spaces before being handed to the child process on this environment's build -- an element like `a file (with) [odd] chars.ps1` arrived at the child process split into several separate argv tokens (`a`, `file`, `(with)`, `[odd]`, `chars.ps1`), not one path. This is not the auto-quoting behavior some PowerShell documentation/folklore assumes. Fix: quote every argument yourself with a CommandLineToArgvW-compatible algorithm (`ConvertTo-TPMWin32QuotedArgumentV1` in `TPMCertification.ProductionFacts.psm1`) before building the `-ArgumentList` array. Rule: never assume `Start-Process -ArgumentList` will safely handle an argument containing a space or Win32 command-line metacharacter (`"`, and by extension anything a human might type into a file/folder name) without testing it directly against a path built from real-world messy input; add a dedicated regression test with such a path whenever a new external-process invocation is introduced.

## ADR155-0309 Checkpoint B1 -- @() directly around a Collections.Generic.List[object] can silently corrupt data

`@($someGenericListVariable)` threw "Argument types do not match" on this environment's pwsh 7.6.4 build for a `List[object]` containing plain PowerShell Hashtables (and even a `List[object]` of plain strings) -- yet the identical list enumerated correctly via `.ToArray()`, an `[array]` cast, or piping through `ForEach-Object { $_ }`. Separately, and even harder to trace: piping that same kind of list through `Sort-Object <PropertyName>` intermittently returned an array whose reported `.Count` did not match the number of genuinely retrievable elements -- some indices silently evaluated to `$null` or threw property-not-found errors depending on unrelated code elsewhere in the same script, not the sort itself. Both failures were being silently absorbed by a surrounding `try`/`catch` as a bare `Executed=$false`, with no visible error, until each was reproduced directly outside the `catch`. Fix: never wrap a `Collections.Generic.List[object]` (especially one containing Hashtables) directly in `@(...)`; pipe it through `ForEach-Object { $_ }` first, or call `.ToArray()`. Never pipe a collection of Hashtables through `Sort-Object -Property <Name>`; write a small manual sort instead (see `Sort-TPMByLineV1`) when the collection is small. Rule: when debugging a mysterious "value looks right in isolation but wrong inside the real function," suspect the collection-enumeration operators themselves before suspecting the surrounding logic -- add a temporary `Write-Host $x.GetType().FullName` at the exact failure point rather than assuming a type you already believe you know.

## ADR155-0309 Checkpoint B1 round 3 -- Receive-Job attaches bookkeeping properties that a strict result schema check must not treat as malformed

A per-file bounded-execution result returned from a real (non-mocked) `Start-Job`/`Receive-Job` call unexpectedly failed a strict "exact expected field set" schema check, even though the job's own scriptblock returned exactly the documented fields. Reproduced directly: `Receive-Job`'s deserialized result object carries extra bookkeeping properties (`RunspaceId` always; `PSShowComputerName` observed in some runs) that are not part of the job's own returned shape. A schema check built by literally comparing `$result.PSObject.Properties.Name` against an expected list will reject every genuine job result as "malformed extra fields" unless those known job-bookkeeping properties are filtered out first. Rule: when validating the schema of any object that crossed a `Start-Job`/`Receive-Job` boundary, always strip `RunspaceId`/`PSComputerName`/`PSShowComputerName`/`PSSourceJobInstanceId` before comparing against the expected field set -- and prove the fix against a REAL job result, not just a hand-constructed `[pscustomobject]` in a test, since the hand-constructed version won't reproduce the bookkeeping properties at all.

## ADR155-0309 Checkpoint B1 round 3 -- an OrderedDictionary-typed parameter broke Pester's Mock proxy generation

`Mock Invoke-TPMBoundedScriptBlockV1 { ... } -ModuleName X` consistently threw `ParseException: The ordered attribute can be specified only on a hash literal node`, regardless of what the mock body returned and regardless of whether the mock was ever actually invoked (the same error occurred even when the test path returned before reaching the mocked call). Bisected by removing pieces of the test until only the `Mock` statement itself remained, then bisected the MODULE function's own signature: the failure traced to the function's `-Parameters` parameter being explicitly typed `[System.Collections.Specialized.OrderedDictionary]` -- Pester's mock-proxy generation could not handle that specific type constraint, apparently while reconstructing the original function's parameter block. Fixed by leaving `-Parameters` untyped (documented via a comment above `param()` establishing the `[ordered]@{...}` calling convention instead of a runtime type constraint). Rule: if `Mock` throws a parse error that mentions syntax nowhere in your own test file, suspect the ORIGINAL function's own parameter types/attributes, not the mock body -- reproduce with a minimal container script that mocks the function with a trivial body and never invokes it, to confirm whether the failure happens at `Mock` set-up time (a signature problem) or at invocation time (a mock-body problem) before spending more time on the wrong half of the code.

## ADR155-0309 Checkpoint B2 -- `sed -i` silently flattened CRLF to LF across an entire file, invalidating hardcoded-CRLF InjectionHunter disposition entries

Large-scale legacy-function removal from `Invoke-TPM-RealInstanceSmoke.ps1` was done with `sed -i '<start>,<end>d'` (chosen for reliability deleting big line ranges the Edit tool's exact-match requirement made awkward). This silently rewrote the entire file from CRLF to bare LF line endings -- `sed` on this environment does not preserve CRLF, even on lines it never touches. The file's own committed blob was already LF (`git show` confirmed this), but the actual Windows working-tree checkout is CRLF (`core.autocrlf` converts on checkout/`git stash pop`), and one disposition-registry entry (`InjectionHunterDispositions.psd1`, the `InjectionRisk.AddScript` entry for a multi-line Pester scriptblock literal) hardcoded its `Extent` field with explicit `` `r`n `` escapes to match that CRLF working-tree form exactly. After the `sed` edits flattened the file to LF, that entry's `Extent` no longer matched the live scan's `Extent.Text` (LF now), and the match-key lookup failed -- surfacing later as a confusing `DISPOSITION_REGISTRY_STALE` exception, not an obviously line-ending-related symptom. Fix: after any `sed -i` (or similar external-tool) edit to a file whose disposition-registry entries hardcode literal line-ending escapes, re-normalize the file back to the working tree's real line-ending convention before re-running the gates -- do not assume `sed`/similar tools preserve CRLF. Rule: when a match-key lookup that should trivially succeed (identical Extent text) instead reports "not found," check the file's actual line-ending bytes before suspecting the matching logic itself; `git show HEAD:<path>` and the live working-tree file can legitimately differ in line-ending convention even when their content is otherwise identical, so compare the working-tree file's real bytes, not the committed blob.

## ADR155-0309 Checkpoint B2 -- an `if/else` branch's own output enumeration collapses a bare `@()` empty-array literal to `$null` when captured by assignment

`Test-TPMProductionInjectionHunterV1`'s pairing loop used `$orderedEntries=if($registry.ByMatchKey.ContainsKey($key)){Sort-TPMByLineV1 $registry.ByMatchKey[$key]}else{@()}` -- when a current finding's match key had no corresponding registry entry at all (as opposed to a stale registry entry with no matching finding), the `else{@()}` branch was taken, and `$orderedEntries` came out `$null`, not an empty array, crashing the very next line's `$orderedEntries.Count` with `PropertyNotFoundException`, silently absorbed by the surrounding `try`/`catch` as `Executed=$false`. This is the exact same "`return @()` unwraps to `$null`" class already documented above (General section) and already worked around elsewhere in this same function via `Sort-TPMByLineV1`'s `return ,$arr` -- but the bare `else{@()}` branch was never comma-wrapped, so it hit the bug. This had never been exercised before (every prior finding always matched an existing registry entry), so it stayed latent through three B1 review rounds and was only exposed when Checkpoint B2's large-scale legacy-function deletion shifted enough code that at least one match key briefly had no registry counterpart. One test (`does not cross-match an identical extent in a different file`) had been asserting `Executed | Should -BeFalse` for this exact scenario -- that assertion happened to pass only because of the crash, not because it verified the intended behavior (a safe `Confirmed`/unresolved fallthrough); fixed the test to assert the real contract (`Executed=$true`, `UnresolvedFindingCount=1`, the unmatched finding disposed `Confirmed`) once the underlying bug was fixed. Rule: any `if(...){X}else{@()}` (or any bare empty-array literal as one branch of a value-producing `if/else`) is exactly as unsafe as a bare `return @()` and must be comma-wrapped (`else{,@()}`); a passing test that asserts a "fails closed"/`$false` outcome for an edge case is not proof the edge case is handled correctly -- verify what specifically caused the assertion to pass before trusting it as intentional-design coverage.

## Issue #172 -- the "return @() unwraps to $null" class reproduced on a real arcade certification run, three layers deep

Real certification (`RunIdentity 2e045f369a2240adb8eaaaed4d9496a0`) against an arcade machine whose pcsx2x6 crosshair setup was never completed (the canonical `Pcsx2x6Crosshairs` directory does not exist on that machine) reported `BeforeSkipped=1`/`AfterSkipped=1` for that tree even though nothing was ever unreadable -- the folder simply is not there. Confirmed root cause, three layers of the exact same class already documented above (General section; ADR155-0309 Checkpoint B2 entries), none of which had been connected to each other before this issue: (1) `Get-TreeHash`'s `if (!(Test-Path ...)) { return @() }` collapses to `$null` at the caller, same as every other bare-`return @()` case in this codebase; (2) `Compare-TreeSnapshot`'s own `foreach ($item in @($Before))` then wraps that `$null` into a ONE-element array containing a single `$null` (`@($null)` has `Count -eq 1` on this environment), which its per-item loop counted as a real skipped entry; (3) a caller-side `$preCrosshairs = if ($crosshairPath) { Get-TreeHash $crosshairPath } else { @() }` has the identical un-wrapped-empty-branch bug documented in the B2 `if/else` entry above, so even a caller who never touches `Get-TreeHash`'s own bug could independently manufacture the same phantom skip. Fixed all three: `Get-TreeHash` now `return ,@()`; `Compare-TreeSnapshot` now explicitly normalizes a `$null` argument to a real empty array (`if ($null -eq $Before) { ,@() } else { ,@($Before) }` -- both branches comma-wrapped, confirmed by direct reproduction that the non-null branch alone still collapses to `$null` when its own array happens to be empty) before its per-item loop runs, so it is no longer only as safe as its caller; and both caller-side `else { @() }` branches comma-wrapped too. Rule: this exact defect class (a bare `@()` -- as a `return`, as one branch of an `if/else`, as a function-call fallback -- collapsing to `$null` under this environment's assignment/capture semantics) has now independently bitten three unrelated subsystems in this codebase (InjectionHunter fact-adapter pairing, ProductionCycle rollback bookkeeping, and this pre-existing tree-snapshot diffing code that predates ADR-0155 entirely). Treat it as a standing audit item, not a one-off: grep for `else *{ *@\(\) *}` and bare `return @()` across the whole script whenever touching adjacent code, not only when a symptom already points at it. A producer-side fix alone is not sufficient when a consumer's own defense against `$null` is what a reviewer explicitly required -- fix the producer, the consumer's own defensive normalization, and every caller-side fallback independently, since any one of the three can reintroduce the same symptom on its own.

## ADR155-0309 / Issue #172 -- `finally` is not permission to finalize incomplete input

A real collection exception occurred before Pester and install-health state
existed, but an unconditional production tail in `finally` attempted to adapt
those absent values. Strict mode then raised a secondary missing-`Checks`
exception, hiding the initiating failure. Rule: initialize phase state before
the guarded work, retain the first `ErrorRecord`, and place a phase-completion
gate before every downstream authority/fact/evidence/publication operation.
Also test the top-level composition path, not only valid synthetic adapters.
Wrapper scripts must explicitly return the saved child exit code; a displayed
abort is not process failure unless every launcher layer propagates it.

## ADR155-0309 review follow-up -- validating a container is not validating its entries

Checking that `HealthResult` was a `PSCustomObject` and had a non-null `Checks`
property still left strict-mode member reads on each unchecked entry. A null,
scalar, nested collection, or missing `Name`/`Passed` member could therefore
escape as another raw `PropertyNotFoundException`. Rule: validate every layer
of a deserialized schema before the first member read, including unexpected
entries that will not be projected into the authoritative result; ignored data
is still attacker- or corruption-controlled input during enumeration.

Exit propagation has two different contracts: exact code preservation after a
child returns an exit code, and merely nonzero failure when process creation or
script execution throws before such a code exists. Documentation and tests
must not claim the former for the latter. Presentation work is tested
behaviorally with a real report-directory/Explorer branch while substituting a
harmless executable in the test-only PATH.

### Certification UI and process isolation are one safety boundary

Raw child streams are not merely noisy: progress redraws, host records, and prompts can obscure whether a run is still valid. Running Pester in-process also made its rich runtime object an undocumented composition dependency. The durable correction is a closed-input child boundary, separate technical logs, a small versioned result contract, strict parent validation, bounded termination, and a simple append-only operator status channel. Tests must exercise the composed process path under both PowerShell engines; source assertions alone cannot prove prompt or exit behavior. Never use a blanket confirmation override to make an unattended path appear safe.

## ADR155-0309 operator-experience review round -- a source-string test proves nothing about runtime behavior, and hardening a primitive can silently break its own callers

Independent review of PR #155 found the harness's only early-abort regression coverage was `$source|Should -Match 'CERTIFICATION PIPELINE ABORTED'` against the harness's own source text -- it would still pass if the abort code path were dead. Replaced with a real child-process test (`Tests/TPMCertificationHarness.Tests.ps1`, "a pre-Pester collection failure genuinely aborts the real harness child process") that injects a throw before the harness's own Pester-gate marker in a copied synthetic repository, launches the harness as a real child, and proves nonzero exit, retained sentinel text, the operator-facing abort banner, no certification-outcome claim, no Pester invocation, no production-composition entry, no authoritative artifact, and no hang. Rule: a "the source contains string X before string Y" assertion is a source-order smoke check at best; it is never a substitute for actually running the code path being claimed.

Two further, real regressions were found only by actually running the new/changed tests repeatedly under load, not by reading the code:

1. **Directory auto-create removal broke real callers, twice, at two different layers.** Hardening `Invoke-TPMIsolatedProcessV1`'s working/log directory handling (verify full path, reject reparse points) also silently dropped the pre-existing auto-create-if-missing behavior several real call sites depended on (e.g. the harness's own Pester-gate `TechnicalLogs` directory, never explicitly created anywhere else) -- every Pester-invoking certification run failed with `PROCESS_DIRECTORY_INVALID: directory does not exist`, but only once actually exercised end-to-end via a real child-process test; no unit test using a pre-created `$TestDrive` directory would ever have caught it. Fixed by adding an explicit `-CreateIfMissing` switch to `Assert-TPMOwnedDirectoryV1`. That fix alone was not sufficient: `TPMCertification.ProductionFacts.psm1`'s `Invoke-TPMExternalProcessWithTimeoutV1` (the parser-probe caller) had its own separate, redundant `if(-not(Test-Path ... )){return TimedOut=$true}` guard in front of the call to `Invoke-TPMIsolatedProcessV1` -- a leftover from when that function had its own standalone process-launch implementation -- which silently short-circuited before the fixed primitive's own `-CreateIfMissing` logic ever ran, so the parser-probe fact kept reporting `Executed=$false` for any working directory created lazily on first use (confirmed via `git stash`-based bisection against the real end-to-end `Tests/TPMCertification.ProductionHarnessComposition.Tests.ps1` composition test, which silently flipped from `CERTIFIED` to `NOT CERTIFIED`). Fixed by deleting the redundant guard entirely and trusting the shared primitive as the single source of truth, with the caller's existing `try`/`catch` as the fail-closed backstop. Rule: when delegating a function to a shared primitive, audit every guard clause the original standalone implementation had for one that silently duplicates (and can therefore silently shadow) logic the primitive now owns -- a leftover guard is not inert, it can neutralize a fix made only in the primitive.
2. **A just-exited child's redirected-output file can still be locked.** `Write-TPMSafeTechnicalFileV1` read a child's captured stdout/stderr log immediately after `Process.HasExited` (and the surrounding termination-confirmation logic) reported true, and intermittently hit `IOException: being used by another process` -- Windows can hold the OS-level file handle open briefly past the point .NET reports the process as exited. This never reproduced in a single isolated test run; it appeared only once several real child-process tests ran back-to-back under time pressure. Fixed with a short bounded retry (`IOException`-scoped only, ~2 seconds total) that gives up gracefully (leaves the file unsanitized) rather than throwing, since sanitization is a best-effort readability step, not a safety invariant worth aborting the caller over.

Rule: when hardening a shared, heavily-reused primitive (directory/path validation, process isolation), running every real caller's actual test suite end-to-end -- not just the primitive's own unit tests -- is the only way to catch a caller-breaking regression the primitive's own tests have no way to see. Timing-sensitive races (file-handle release, cross-process cleanup ordering) require running the real behavioral tests enough times / under enough concurrent load to surface them; a single green run of a new test is not proof it is race-free.

## ADR155-0309 static-review correction round -- "best-effort, fail open" was the wrong call, and a hypothesis needs an exact reproduction, not just a plausible story

A later independent static review of the same PR found two places where the round above had still failed open, and one place where a plausible-sounding root-cause hypothesis turned out to be wrong once actually reproduced.

1. **"Sanitization is best-effort, not a safety invariant" (item 2 in the entry above) was itself the bug.** Retrying every `IOException` indiscriminately and silently leaving a file unsanitized on exhaustion meant a persistently locked log could leave un-redacted/un-ANSI-stripped content on disk with no signal to the caller that sanitization never happened -- exactly the kind of silent-degrade this pipeline's own "never guess, never silently swallow errors" rule exists to prevent. Corrected: retries are now scoped to the exact two transient `IOException.HResult` values the handle-release race produces (`0x80070020`/`0x80070021`); everything else, and exhaustion of the transient retry itself, throws a deliberately tagged exception rather than returning silently. See ARCHITECTURE.md ("Fail-closed correction round") and SECURITY.md for the corrected contract. Rule: "best-effort, not a safety invariant" is a judgment call that itself needs review -- do not let a rationale written to explain away a flaky test become permanent policy without checking whether the thing being made best-effort was actually meant to be relied upon elsewhere.
2. **A reviewer's plausible root-cause hypothesis was wrong, and only an exact reproduction caught it.** A static reviewer noted the disposition registry (`scripts/InjectionHunterDispositions.psd1`) had one line-number change between two commits (163 -> 244) and hypothesized this was because a deleted `$PSDefaultParameterValues['*:Confirm']=$false` line (removed from `scripts/Invoke-TPM-PesterChild.ps1` in the same commit) had its own InjectionHunter finding that disappeared, explaining an assumed 27-to-26 finding-count drop. Running the actual InjectionHunter scan (same tool version, same production inventory, same per-file invocation as `Test-TPMProductionInjectionHunterV1`) against both commits directly proved this wrong on two counts: the finding count did not change at all (27 in both), and `Invoke-TPM-PesterChild.ps1` had zero InjectionHunter findings in either commit -- the deleted line was never flagged by the tool in the first place. The real explanation for the 163 -> 244 line change was mundane: unrelated function additions earlier in `TPMCertification.Execution.psm1` shifted every later line down, including the one existing, unchanged `$result.$name` finding the registry entry has always covered. Rule: "the review said X" is not "X is true" even when X sounds mechanically plausible and cites real evidence (a real deleted line, a real line-number change) -- run the exact tool, on the exact commits, over the exact inventory, and diff findings by identity (file+rule+extent), not by aggregate count, before accepting a causal story.

## ADR155-0309 round 3 -- a "hardened" chain validator that is always called with Root==Target only ever checks the leaf, and a disposition's "second occurrence" claim was already wrong when it was written

An independent static reviewer found that `Assert-TPMOwnedDirectoryV1` (the wrapper every real caller of `Invoke-TPMIsolatedProcessV1`/`New-TPMCreateNewFileV1` actually calls, added in the "Fail-closed correction round" documented above) always invoked the underlying `Assert-TPMNoReparseInChainV1 -Root $full -Target $full` with Root and Target set to the SAME path. `Assert-TPMNoReparseInChainV1`'s chain walk only inspects components at or after the point where Root's and Target's path-segment arrays start to differ -- with Root==Target there is no such point, so the walk collapses to inspecting only the final leaf. This meant the round-2 "walk every ancestor, not just the leaf" hardening never actually ran against any real ancestor in production: every real caller's working/log directory was validated no more thoroughly than the pre-round-2 leaf-only check it was written to replace, and `New-Item -ItemType Directory`'s own multi-level auto-create silently brought unvalidated intermediate directories (e.g. the harness's own `Reports`/`ProductionWork` folders, one level above the timestamped run directory actually passed to `Assert-TPMOwnedDirectoryV1`) into existence with no reparse check at all. None of round 2's own tests caught this because every one of them happened to validate a directory that was already exactly one level below an already-existing, already-validated parent -- the specific gap (an intermediate level strictly ABOVE a multi-level *missing* path) was never exercised by any test, only by real multi-level call sites in production code. Fixed by making the trusted root a distinct, mandatory, caller-supplied parameter (`-Root` vs. `-Path`/`-Parent`) that is validated on its own and never silently inferred from, or collapsed onto, the target -- see ARCHITECTURE.md's "Trusted-root wiring correction (ADR155-0309 round 3)" for the corrected API and the full caller list. Rule: a chain-walking validator's own unit tests proving it walks correctly when given *distinct* Root/Target inputs say nothing about whether any real caller ever actually supplies distinct inputs -- audit every call site of a "hardened" primitive for exactly what it was called with, not just whether the primitive's own isolated tests pass.

The same reviewer separately found that the "A second, separate occurrence of Add-Type with the same fixed AssemblyName literal elsewhere in this file (see line 1169 above)" disposition-registry reasoning for `scripts/Invoke-TPM-RealInstanceSmoke.ps1`'s `Add-Type -AssemblyName System.Drawing` finding was factually wrong -- not merely stale from later line drift, but wrong about the underlying source at the time it was written. A direct grep of the source (confirmed against both the pre-round-3 commit `3931b5e9` and the round-3-corrected checkout) shows THREE textually-identical `Add-Type -AssemblyName System.Drawing` statements in that file (PNG-structure validation, `Save-TPMScreenCapture`, `Save-TPMRenderedTextCapture`), not the two the reasoning implied. Running the actual InjectionHunter scanner against both commits (same tool version, same 19-file production inventory, exported to raw JSON and diffed by File+RuleName+Line+Column+Extent identity, not aggregate count) showed the scanner itself only ever emits a finding for TWO of the three source occurrences in either commit -- the `Save-TPMScreenCapture` occurrence, immediately preceded in the same function by a separate `Add-Type -AssemblyName System.Windows.Forms` call, never produces its own separate `InjectionRisk.AddType` finding from this scanner/rule version. So the registry was not missing a disposition (the third occurrence genuinely never raises a raw finding to disposition), but its reasoning text's occurrence count was still factually wrong about the source, which matters because a human reviewer reads that reasoning as a claim about the code, not just about the scanner's output. Corrected the reasoning text to state the true count (three source occurrences, two flagged) and to explain, from direct empirical comparison rather than assumption, why the third is not separately dispositioned. Rule: when a disposition's reasoning makes an explicit or implicit claim about how many times a pattern occurs in the source ("a second, separate occurrence..."), verify that claim against the actual current source with a direct search every time the registry is touched for that file -- a registry entry can be simultaneously "matches its raw finding correctly" (so the automated stale/duplicate checks pass) and "factually wrong about the source" (because those checks never validate the English reasoning text against anything).

## ADR155-0309 operator-experience follow-up round -- "hardened this failure path" does not mean "hardened every structurally identical failure path in the sibling function," and a validated shape still needs a validator

A prior round's commit message described adding `Diagnostic` (Stage/ExceptionType/sanitized Message) to every `Executed=$false` return in both `Test-TPMProductionPSScriptAnalyzerV1` and `Test-TPMProductionInjectionHunterV1`, framed as closing the same defect class in both tool-execution wrappers. Auditing the actual diff line-by-line (not trusting the commit message's own characterization) showed only 2 of PSScriptAnalyzer's 8 failure branches were actually hardened -- the settings-missing and job-execution-failure paths -- while the 6 result-shape/schema/path/version-mismatch branches, structurally identical to ones InjectionHunter tags with distinct Stage values, still returned `Diagnostic=$null` with no `Write-Warning`. The two functions look parallel (same tool-execution pattern, same bounded-job primitive) but were hardened independently and asymmetrically, and nothing about the commit message or the surrounding tests (which only asserted `Executed|Should -BeFalse`, never `.Diagnostic`) would have caught the gap. Separately, a bare `try{Stop-Job -Job $job -ErrorAction Stop}catch{}` survived untouched in the same module the whole time -- exactly the defect class the round claimed to have eliminated from "this code path," just one call earlier in the same function. And even after both were fixed, nothing validated the `Diagnostic` shape itself anywhere in the codebase -- a schema-shaped record with no schema validator is not actually a schema, just a convention every hand-written call site has to remember to follow correctly on its own (`Assert-TPMDiagnosticRecordV1` was added specifically to close this: it also caught, on first use, that both functions' success paths omit the `Diagnostic` key entirely rather than setting it to `$null`, which meant the validator's caller had to switch from dot-access to hashtable bracket-indexing to avoid a `Set-StrictMode` `PropertyNotFoundException` on the happy path). Rule: "we hardened this failure path" is a claim about one function; when a sibling function shares the same failure-path *shape*, audit it independently rather than assuming symmetric treatment, and when a record's fields are asserted by convention rather than by a validator, add the validator -- and run it against the actual return values (including the success path) before assuming the "additive-only" contract holds exactly as described.

## Issue #154 -- an open-ended `-MinimumVersion` on a test-running tool is an unpinned dependency on the tool's own future behavior, and a full-suite failure that vanishes when run one file at a time is a cross-file symptom, not 225 separate bugs

A real-hardware certification run reported 225 Pester failures out of 1235 tests, spread across dozens of unrelated files (zip extraction, DAT parsing, screenshot capture, ADR-0155 authority primitives, backup restore). The instinct on seeing that many failures across that many files is to suspect either a real, widespread production regression or a batch of independently broken tests. Neither was true. `Invoke-TPM-PesterChild.ps1` imported Pester with `-MinimumVersion 5.0` -- an open floor, not a pin -- so it silently picked up whatever the newest installed Pester happened to be. The certification machine had auto-installed Pester 5.8.0 (a real PowerShell Gallery release, published after the 5.7.1 this suite had actually been validated against). Direct A/B reproduction of the exact same 1235-test suite proved it: 1234/1235 under 5.7.1 (the one remaining failure a pre-existing, unrelated, already-documented flaky test), 1010/225/1235 under 5.8.0, nothing else in the environment changed. Running any single affected file alone showed no difference between the two Pester versions at all -- the regression only appeared running the full multi-file suite together, which is exactly why isolated single-file spot-checks would never have caught it, and why the failure signatures looked like unrelated chaos (mostly `$script:`-scoped setup variables "cannot be retrieved because it has not been set," a cross-file/BeforeAll symptom, not a per-test one) rather than one coherent bug. Fixed by changing the pin to `-RequiredVersion 5.7.1` (hard pin, not a floor) and aligning the harness's own preflight check to look for that exact version instead of "any Pester >= 5," so a future Pester release can never again silently change certification behavior without a human deciding to re-validate and bump the pin.

Rule: any tool invoked with an open-ended minimum-version constraint (`-MinimumVersion`, `>=`, "latest") is an implicit bet that the tool's future releases won't change behavior you depend on -- for a test RUNNER specifically (not just the code under test), that bet is on the very thing verifying everything else, so pin it exactly and require a deliberate, documented decision to move the pin. And when a large number of failures span many unrelated-looking files with a shared generic error signature, test whether the failure survives running one one of those files in isolation before concluding you have many separate bugs -- a failure that disappears in isolation but reappears in the full run is telling you about state or environment shared across files, not about any single file's own logic.

## Issue #154 follow-up -- a bare `$obj.Property` read is a latent strict-mode defect even when the live entry point never sets strict mode, and `&` versus `.` changes whether a reproduction proves anything

The Blocker-1 `UnattendedMode` fix (previous entry) read `$cfg.UnattendedMode` via plain dot-access in three spots. A review reported this throws `PropertyNotFoundException` under `Set-StrictMode -Version Latest` when a legacy config (saved before the field existed) is missing the property entirely -- not `$null`, genuinely absent. Confirmed real: reproduced in isolation immediately. But reproducing it through the actual product script took several wrong turns, because PowerShell's strict-mode scoping does not behave uniformly across every way a script can be invoked. Set-StrictMode set in a caller does NOT propagate into a separately invoked `.ps1` file called with the call operator (`& 'script.ps1'`) -- confirmed by direct A/B: identical code, identical config, throws when dot-sourced (`. 'script.ps1'`) into the caller's scope, does not throw (or even evaluate strict mode at all) when invoked with `&`. A first attempt at a regression test used `&` in the wrapper and passed unconditionally regardless of whether the underlying bug was fixed -- a test that cannot fail is not a test. The fix (`$cfg.PSObject.Properties['UnattendedMode']` existence guards instead of bare dot-access) is correct regardless of this scoping nuance, but proving the regression test actually exercises the defect required dot-sourcing the real script from a wrapper, and reconstructing the exact pre-guard code (this worktree has no intermediate commit between "Blocker-1 landed" and "strict-mode guard added" -- both are uncommitted working-tree diffs on top of the same parent commit, so `git stash` reverts both at once, not just the latest edit) to confirm the test fails on it and passes on the fix.

Rule: a defensive fix for a strict-mode/property-existence class of bug is correct on its own logical merits and should be applied even without a perfect end-to-end reproduction. But before trusting a NEW regression test that wraps a real child-process invocation to prove a caller-imposed setting (strict mode, `$ErrorActionPreference`, a session config) reaches the code under test, verify the test actually fails against the pre-fix code first -- do not assume a wrapper "looks right" propagates the setting just because the syntax resembles a working pattern elsewhere; `&` and `.` are not interchangeable for anything scope-dependent. And when reconstructing a specific historical code state for an A/B test inside a worktree with no relevant intermediate commit, `git stash` is not a scalpel -- it reverts every uncommitted change at once, so isolating one specific edit requires manually reintroducing the sibling changes, not just stashing and assuming the result matches the intended baseline.

## RC4 -- a release-ZIP include list that names a module's dependents but not the dependency itself ships a module that cannot load

The RC4 packaging list (RELEASE-SAFETY-CHECKLIST.md section 4, mirrored in AGENTS.md) included `scripts\TPMCertification.Contracts.psm1` -- the ECVF loader/validator/evaluator module `TeknoParrot-Manager.ps1` itself imports at runtime for pcsx2x6 crosshair setup -- but not `scripts\TPMCertification.Authority.psm1`. `TPMCertification.Contracts.psm1`'s very first line is `Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Authority.psm1')`: a hard, unconditional dependency. Every real install of the already-published RC4 ZIP that reaches the pcsx2x6 crosshair code path therefore has `Import-Module $ecvfContractsModule` throw immediately (the sibling file it tries to import next to itself does not exist in the package), which every call site's own try/catch design correctly catches and fails closed on -- "could not load or evaluate the pcsx2x6 emulator contract," ECVF state `Unknown`, cursor_path write skipped -- so nothing crashes, but the ECVF safety layer silently never actually runs for any RC4 pcsx2x6 user. Found 2026-08-14 via a dependency read of `TPMCertification.Contracts.psm1` itself (`Import-Module` at line 1), not by any packaging test -- `Tests\Test-ReleasePackage.ps1`'s required-entry list had the same gap as the checklist it was validated against, so it could not have caught this either. Both the checklist/AGENTS.md include lists and the validator's required-entry list were corrected in the same pass to require `TPMCertification.Authority.psm1`. The already-published RC4 asset itself was NOT modified (out of scope for the task that found this); it needs a separate patch release.

Rule: when a release-ZIP include list names a module, grep that module's own source for `Import-Module`/`. $PSScriptRoot\...` and confirm every sibling file it loads at runtime is also on the include list -- a module "included in the ZIP" that cannot actually load once extracted is indistinguishable, to every downstream fail-closed try/catch, from a module that was never imported at all, which means the gap produces no crash and no obviously-wrong error message, only a silently-disabled safety feature. A packaging validator that enumerates required entries by hand alongside the checklist it mirrors will silently inherit the checklist's own omissions; neither one is a substitute for actually reading the shipped module's own dependency imports.
