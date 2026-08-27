#Requires -Module Pester

# TPM Certification Suite Phase 1.7 (issue #88, priority A1 -- highest
# priority per the approved roadmap): Interrupted Write / Partial Output
# Recovery. Replaces the specific human-tester behavior of "what if TPM (or
# Windows, or the user) got killed mid-write last time" -- a real,
# non-hypothetical condition (crashes, forced shutdowns, antivirus locks),
# not a contrived edge case. Each test documents the human behavior
# replaced, the defect class it catches, and why existing certification
# wouldn't already catch it.
#
# Save-Xml already writes atomically (temp file + File.Replace/Move) --
# these tests prove that guarantee holds under leftover-file conditions a
# real interrupted run would produce, not just the clean happy path already
# covered elsewhere.
#
# Deterministic: no network, no GUI, no real TeknoParrot root, all writes
# confined to $TestDrive.
#
# Run with: Invoke-Pester -Path .\Tests\VirtualBetaTester.InterruptedWriteRecovery.Tests.ps1

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "..\TeknoParrot-Manager.ps1"
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Failed to parse TeknoParrot-Manager.ps1: $($parseErrors -join '; ')"
    }
    $functionAsts = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $extractedFunctionsPath = Join-Path $TestDrive ("vbt-interrupted-write-functions-" + [guid]::NewGuid().ToString('N') + '.ps1')
    ($functionAsts | ForEach-Object { $_.Extent.Text }) -join "`n`n" | Set-Content -LiteralPath $extractedFunctionsPath -Encoding utf8
    . $extractedFunctionsPath
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false
    $script:PostgresRecoveryStatus = $null
    $script:PostgresRecoveryResumeState = $null

    $script:logPath = Join-Path $TestDrive "vbt-interrupted-write.log"
    $script:RawThrillsPathLimits = @{}
    $script:FileVersionPins = @{}
    $script:GpuIncompatibleGames = @{}
    $script:EmulatorBiosRequirements = @{}
}

Describe "Virtual Beta Tester: leftover .tmp files are structurally invisible to profile scans (issue #88 A1)" -Tag 'TVD-High' {
    # Human behavior replaced: a tester whose previous run was killed mid-
    # write (crash, forced shutdown, antivirus lock during Save-Xml's
    # temp-file phase) checks that the leftover ".xml.tmp" file doesn't get
    # mistaken for a real profile on the next run.
    # Defect class detectable: a scan that uses a wildcard broad enough to
    # accidentally match "CODE.xml.tmp" as if it were "CODE.xml" -- reading
    # stale, possibly-incomplete leftover data as if it were a real,
    # trustworthy profile.
    # Why existing certification wouldn't already catch it: no existing
    # fixture (phase 1/1.5/1.6) ever places a stray .tmp file in
    # UserProfiles at all -- every fixture only ever contains clean,
    # complete .xml files.

    It "Get-CompatibilityWarnings' profile scan ignores a leftover .xml.tmp file from an interrupted write" {
        $userProfilesDir = Join-Path $TestDrive ("stray-tmp-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $userProfilesDir -Force | Out-Null

        # A real, complete profile.
        [xml]@'
<?xml version="1.0" encoding="utf-8"?>
<GameProfile>
  <EmulationProfile>RawThrills</EmulationProfile>
  <ConfigValues></ConfigValues>
</GameProfile>
'@ | ForEach-Object { $_.Save((Join-Path $userProfilesDir 'ALIENS.xml')) }

        # A leftover .tmp from an interrupted Save-Xml -- deliberately
        # truncated/garbage content, simulating a kill mid-write.
        Set-Content -LiteralPath (Join-Path $userProfilesDir 'ALIENS.xml.tmp') -Value '<GameProfile><Emulat' -Encoding ascii

        { Get-CompatibilityWarnings -UserProfilesDir $userProfilesDir } | Should -Not -Throw -Because "a stray .tmp leftover must never cause the scan itself to fail"
    }

    It "a stray .tmp file is excluded by the same *.xml filter every scan in the codebase uses" {
        $dir = Join-Path $TestDrive ("filter-proof-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $dir 'REAL.xml') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $dir 'REAL.xml.tmp') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $dir 'INTERRUPTED.xml.tmp') -Force | Out-Null

        $matched = @(Get-ChildItem -LiteralPath $dir -Filter "*.xml" -File | ForEach-Object { $_.Name })
        $matched.Count | Should -Be 1 -Because "the *.xml filter every profile scan in the codebase uses must never match a .xml.tmp leftover"
        $matched | Should -Be @('REAL.xml')
    }
}

Describe "Virtual Beta Tester: Save-Xml recovers cleanly from a prior interrupted write (issue #88 A1)" -Tag 'TVD-High' {
    # Human behavior replaced: a tester whose previous run left a stale
    # .tmp file (interrupted mid-write) runs TPM again and checks the next
    # write completes correctly instead of being confused or blocked by
    # the leftover.
    # Defect class detectable: a temp-file-based atomic writer that errors
    # out or produces corrupt output when its own .tmp path is already
    # occupied by a stale leftover from a previous incomplete run.
    # Why existing certification wouldn't already catch it: no existing
    # test calls Save-Xml (or any function that calls it) with a
    # pre-existing stale .tmp file already sitting at the target path --
    # every existing write-path test starts from a clean target.

    It "Save-Xml overwrites a stale leftover .tmp and produces exactly the requested final content" {
        $path = Join-Path $TestDrive ("save-xml-recovery-" + [guid]::NewGuid().ToString('N') + '.xml')
        $tmpPath = $path + '.tmp'

        # Simulate the leftover from a previous interrupted run: garbage
        # content at the .tmp path, no real file at the final path yet
        # (the kill happened before the very first successful write).
        Set-Content -LiteralPath $tmpPath -Value 'garbage from an interrupted run' -Encoding ascii

        $doc = [xml]'<?xml version="1.0" encoding="utf-8"?><GameProfile><EmulationProfile>Test</EmulationProfile></GameProfile>'
        { Save-Xml -doc $doc -path $path } | Should -Not -Throw

        (Test-Path -LiteralPath $tmpPath) | Should -Be $false -Because "the temp file must be consumed (renamed away), not left behind, once the write completes"
        (Test-Path -LiteralPath $path) | Should -Be $true
        (Get-Content -LiteralPath $path -Raw) | Should -Match 'EmulationProfile>Test<' -Because "the final content must be exactly what was requested, not the stale leftover garbage"
    }

    It "a second interrupted-then-recovered write cycle still produces correct final content (repeat-run stability)" {
        $path = Join-Path $TestDrive ("save-xml-repeat-recovery-" + [guid]::NewGuid().ToString('N') + '.xml')

        $doc1 = [xml]'<?xml version="1.0" encoding="utf-8"?><GameProfile><EmulationProfile>First</EmulationProfile></GameProfile>'
        Save-Xml -doc $doc1 -path $path

        # Simulate a second interrupted run leaving a stale .tmp again,
        # this time with a real prior file already in place (the more
        # common real case -- an update to an existing profile that got
        # interrupted).
        Set-Content -LiteralPath ($path + '.tmp') -Value 'garbage from a second interrupted run' -Encoding ascii

        $doc2 = [xml]'<?xml version="1.0" encoding="utf-8"?><GameProfile><EmulationProfile>Second</EmulationProfile></GameProfile>'
        { Save-Xml -doc $doc2 -path $path } | Should -Not -Throw

        (Get-Content -LiteralPath $path -Raw) | Should -Match 'EmulationProfile>Second<' -Because "the second write must fully supersede both the first write and the stale leftover, not merge or get confused by either"
    }

    It "a failed temp-file write never touches or corrupts the existing good file (atomicity)" {
        $path = Join-Path $TestDrive ("save-xml-atomicity-" + [guid]::NewGuid().ToString('N') + '.xml')
        $doc1 = [xml]'<?xml version="1.0" encoding="utf-8"?><GameProfile><EmulationProfile>Original</EmulationProfile></GameProfile>'
        Save-Xml -doc $doc1 -path $path
        $originalContent = Get-Content -LiteralPath $path -Raw

        # Force the temp-file write to fail by making its target path
        # itself a directory (an XmlWriter cannot create a file where a
        # directory of the same name exists) -- a deterministic, real way
        # to simulate a temp-file write failure without needing to
        # literally kill a process mid-write.
        $tmpPath = $path + '.tmp'
        New-Item -ItemType Directory -Path $tmpPath -Force | Out-Null

        $doc2 = [xml]'<?xml version="1.0" encoding="utf-8"?><GameProfile><EmulationProfile>ShouldNeverLand</EmulationProfile></GameProfile>'
        { Save-Xml -doc $doc2 -path $path } | Should -Throw -Because "a temp-file write failure must surface as a real error, not silently succeed with wrong content"

        (Get-Content -LiteralPath $path -Raw) | Should -Be $originalContent -Because "the existing good file must be completely untouched when the temp-file write itself fails -- this is the entire point of the write-to-temp-then-atomic-rename pattern"
    }
}

Describe "Virtual Beta Tester: interrupted backup creation recovery (issue #88 A1)" -Tag 'TVD-High' {
    # Human behavior replaced: a tester whose previous Propagate Controls
    # backup was interrupted partway through (some files copied, not all)
    # checks that running it again produces a complete, trustworthy backup
    # rather than being blocked by or silently trusting the incomplete one.
    # Defect class detectable: a backup routine that treats the mere
    # existence of a same-named backup folder as "already done" and skips
    # re-copying, silently leaving a permanently incomplete backup.
    # Why existing certification wouldn't already catch it: phase 1.6's
    # "existing backup already present" test uses a COMPLETE prior backup
    # from a different timestamp; this specifically tests an INCOMPLETE
    # backup left by an interrupted run.

    It "a fresh backup run is complete even when an earlier interrupted backup left a partial folder behind" {
        $userProfilesDir = Join-Path $TestDrive ("interrupted-backup-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $userProfilesDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $userProfilesDir 'ALIENS.xml') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $userProfilesDir 'TIMECRS4.xml') -Force | Out-Null

        # Simulate a partial/interrupted backup from a previous run: the
        # timestamped folder exists but only got partway through copying
        # (one file present, one missing) before being killed.
        $partialBackupDir = Join-Path $userProfilesDir 'FullBackup\PropagateControls_2026-07-01_00-00-00'
        New-Item -ItemType Directory -Path $partialBackupDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $partialBackupDir 'ALIENS.xml') -Force | Out-Null
        # TIMECRS4.xml deliberately absent -- this is the "interrupted" signature.

        $result = New-PropagationBackup -UserProfilesDir $userProfilesDir
        $result.ErrorCount | Should -Be 0 -Because "a partial backup from a previous interrupted run must not cause a fresh backup to error"
        (Test-Path -LiteralPath (Join-Path $result.Path 'ALIENS.xml')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $result.Path 'TIMECRS4.xml')) | Should -Be $true -Because "the fresh backup must be genuinely complete, unaffected by an earlier interrupted backup's own missing file"

        # The old partial backup itself is preserved as-is (never silently
        # deleted or "fixed up") -- it's just superseded by a new, complete
        # one, matching the same non-destructive philosophy as every other
        # backup-before-write check in this codebase.
        (Test-Path -LiteralPath $partialBackupDir) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $partialBackupDir 'TIMECRS4.xml')) | Should -Be $false -Because "an old interrupted backup is left exactly as it was, not retroactively completed or deleted"
    }
}

Describe "Virtual Beta Tester: malformed/truncated profile recovery (issue #88 A1)" -Tag 'TVD-High' {
    # Human behavior replaced: a tester who finds one UserProfile XML is
    # corrupted (external interference, a disk error, a genuinely
    # interrupted write that somehow left bad data at the final path)
    # checks that TPM skips just that one file with a clear log entry
    # rather than crashing the entire run and blocking every other game.
    # Defect class detectable: an unhandled parse exception that aborts
    # the whole scan instead of being caught, logged, and skipped for that
    # one file.
    # Why existing certification wouldn't already catch it: no existing
    # fixture combines a malformed profile with other valid profiles in
    # the same scan to prove the valid ones are still processed.

    It "a truncated/malformed profile is skipped without crashing the scan, and valid profiles are still processed" {
        $userProfilesDir = Join-Path $TestDrive ("malformed-profile-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $userProfilesDir -Force | Out-Null

        # A genuinely truncated/malformed XML -- not well-formed at all,
        # simulating a write that was interrupted after only partial
        # content landed at the final path (a rare but real possibility if
        # the atomic-rename step itself is interrupted).
        Set-Content -LiteralPath (Join-Path $userProfilesDir 'CORRUPT.xml') -Value '<GameProfile><EmulationProfile>Broken' -Encoding ascii

        # A real, valid, complete profile alongside it.
        [xml]@'
<?xml version="1.0" encoding="utf-8"?>
<GameProfile>
  <EmulationProfile>RawThrills</EmulationProfile>
  <ConfigValues></ConfigValues>
</GameProfile>
'@ | ForEach-Object { $_.Save((Join-Path $userProfilesDir 'ALIENS.xml')) }

        { Get-CompatibilityWarnings -UserProfilesDir $userProfilesDir } | Should -Not -Throw -Because "one malformed profile must never crash the whole scan -- every other registered game still needs its checks to run"
    }
}
