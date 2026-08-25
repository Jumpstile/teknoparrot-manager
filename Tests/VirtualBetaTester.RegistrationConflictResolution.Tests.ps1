#Requires -Module Pester

# TPM Certification Suite Phase 1.7 (issue #88, priority A3): AutoSync /
# Registration Conflict Resolution. Repair-GamePaths (the "a game folder
# moved since it was registered" handler) had zero test coverage of any
# kind before this round. Each test documents the human behavior replaced,
# the defect class it catches, and why existing certification wouldn't
# already catch it.
#
# Deterministic: no network, no GUI, no real TeknoParrot root, all writes
# confined to $TestDrive.
#
# Run with: Invoke-Pester -Path .\Tests\VirtualBetaTester.RegistrationConflictResolution.Tests.ps1

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "..\TeknoParrot-Manager.ps1"
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Failed to parse TeknoParrot-Manager.ps1: $($parseErrors -join '; ')"
    }
    $functionAsts = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $extractedFunctionsPath = Join-Path $TestDrive ("vbt-conflict-resolution-functions-" + [guid]::NewGuid().ToString('N') + '.ps1')
    ($functionAsts | ForEach-Object { $_.Extent.Text }) -join "`n`n" | Set-Content -LiteralPath $extractedFunctionsPath -Encoding utf8
    . $extractedFunctionsPath

    $script:logPath = Join-Path $TestDrive "vbt-conflict-resolution.log"

    function New-ConflictFixture {
        param([string]$Name)
        $root = Join-Path $TestDrive ($Name + '-' + [guid]::NewGuid().ToString('N'))
        $result = [pscustomobject]@{
            Root             = $root
            UserProfilesDir  = Join-Path $root 'UserProfiles'
            GameProfilesDir  = Join-Path $root 'GameProfiles'
            InstallFolder    = Join-Path $root 'Games'
        }
        New-Item -ItemType Directory -Path $result.UserProfilesDir, $result.GameProfilesDir, $result.InstallFolder -Force | Out-Null
        return $result
    }
}

Describe "Virtual Beta Tester: registered-but-moved recovery via Repair-GamePaths (issue #88 A3)" -Tag 'TVD-High' {
    # Human behavior replaced: a tester who moved or renamed a game's
    # install folder (reorganizing a drive, moving to a new SSD) runs
    # Repair and expects the broken GamePath to be found and fixed
    # automatically -- since the exe itself, by name, is unambiguous.
    # Defect class detectable: a repair that fails to find the exe at its
    # new location, or one that guesses wrong when the exe name isn't
    # actually unique.
    # Why existing certification wouldn't already catch it: Repair-
    # GamePaths had zero test coverage before this round.

    It "fixes a broken GamePath when the exe now lives at a new, unambiguous location" {
        $fx = New-ConflictFixture -Name 'moved-unambiguous'
        $newGameFolder = Join-Path $fx.InstallFolder 'Aliens Armageddon (New Location)'
        New-Item -ItemType Directory -Path $newGameFolder -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $newGameFolder 'ALIENS.exe') -Force | Out-Null

        $staleProfile = @'
<?xml version="1.0" encoding="utf-8"?>
<GameProfile>
  <ExecutableName>ALIENS.exe</ExecutableName>
  <GamePath>C:\OldLocation\ALIENS.exe</GamePath>
  <EmulationProfile>RawThrills</EmulationProfile>
</GameProfile>
'@
        Set-Content -LiteralPath (Join-Path $fx.UserProfilesDir 'ALIENS.xml') -Value $staleProfile -Encoding utf8

        $profileIndex = @{ 'aliens.exe' = @('ALIENS') }
        $reports = Repair-GamePaths -userProfilesDir $fx.UserProfilesDir -installFolder $fx.InstallFolder -profileIndex $profileIndex -DryRun $false

        $reports.Count | Should -Be 1
        $reports[0].Status | Should -Be 'fixed'
        $reports[0].NewPath | Should -Be (Join-Path $newGameFolder 'ALIENS.exe')

        $doc = [xml](Get-Content -LiteralPath (Join-Path $fx.UserProfilesDir 'ALIENS.xml') -Raw)
        $doc.GameProfile.GamePath | Should -Be (Join-Path $newGameFolder 'ALIENS.exe') -Because "the profile on disk must reflect the new, correct location"
    }

    It "reports ambiguous (does not guess) when the same exe name exists at two locations on disk" {
        $fx = New-ConflictFixture -Name 'moved-ambiguous-disk'
        $folderA = Join-Path $fx.InstallFolder 'CandidateA'
        $folderB = Join-Path $fx.InstallFolder 'CandidateB'
        New-Item -ItemType Directory -Path $folderA, $folderB -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $folderA 'game.exe') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $folderB 'game.exe') -Force | Out-Null

        $staleProfile = @'
<?xml version="1.0" encoding="utf-8"?>
<GameProfile>
  <ExecutableName>game.exe</ExecutableName>
  <GamePath>C:\OldLocation\game.exe</GamePath>
  <EmulationProfile>Generic</EmulationProfile>
</GameProfile>
'@
        Set-Content -LiteralPath (Join-Path $fx.UserProfilesDir 'AMBIGUOUS.xml') -Value $staleProfile -Encoding utf8
        $originalContent = Get-Content -LiteralPath (Join-Path $fx.UserProfilesDir 'AMBIGUOUS.xml') -Raw

        $profileIndex = @{ 'game.exe' = @('AMBIGUOUS') }
        $reports = Repair-GamePaths -userProfilesDir $fx.UserProfilesDir -installFolder $fx.InstallFolder -profileIndex $profileIndex -DryRun $false

        $reports.Count | Should -Be 1
        $reports[0].Status | Should -Be 'ambiguous' -Because "two candidates on disk for the same exe name must never be auto-resolved by guessing"
        (Get-Content -LiteralPath (Join-Path $fx.UserProfilesDir 'AMBIGUOUS.xml') -Raw) | Should -Be $originalContent -Because "an ambiguous case must leave the existing (broken) profile completely untouched -- Action Required, not a guess"
    }

    It "reports ambiguous (does not guess) when the exe name maps to more than one profile in the library" {
        $fx = New-ConflictFixture -Name 'moved-ambiguous-profiles'
        $gameFolder = Join-Path $fx.InstallFolder 'SharedExeGame'
        New-Item -ItemType Directory -Path $gameFolder -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $gameFolder 'shared.exe') -Force | Out-Null

        $staleProfile = @'
<?xml version="1.0" encoding="utf-8"?>
<GameProfile>
  <ExecutableName>shared.exe</ExecutableName>
  <GamePath>C:\OldLocation\shared.exe</GamePath>
  <EmulationProfile>Generic</EmulationProfile>
</GameProfile>
'@
        Set-Content -LiteralPath (Join-Path $fx.UserProfilesDir 'SHAREDA.xml') -Value $staleProfile -Encoding utf8
        $originalContent = Get-Content -LiteralPath (Join-Path $fx.UserProfilesDir 'SHAREDA.xml') -Raw

        # shared.exe maps to two different profile codes in the library --
        # inherently ambiguous regardless of what's on disk.
        $profileIndex = @{ 'shared.exe' = @('SHAREDA', 'SHAREDB') }
        $reports = Repair-GamePaths -userProfilesDir $fx.UserProfilesDir -installFolder $fx.InstallFolder -profileIndex $profileIndex -DryRun $false

        $reports.Count | Should -Be 1
        $reports[0].Status | Should -Be 'ambiguous'
        (Get-Content -LiteralPath (Join-Path $fx.UserProfilesDir 'SHAREDA.xml') -Raw) | Should -Be $originalContent
    }

    It "reports not-found (does not fabricate a path) when the exe genuinely no longer exists anywhere" {
        $fx = New-ConflictFixture -Name 'moved-not-found'
        # Install folder exists but the exe is nowhere in it -- simulates
        # a game that was uninstalled/deleted, not just moved.

        $staleProfile = @'
<?xml version="1.0" encoding="utf-8"?>
<GameProfile>
  <ExecutableName>gone.exe</ExecutableName>
  <GamePath>C:\OldLocation\gone.exe</GamePath>
  <EmulationProfile>Generic</EmulationProfile>
</GameProfile>
'@
        Set-Content -LiteralPath (Join-Path $fx.UserProfilesDir 'GONE.xml') -Value $staleProfile -Encoding utf8
        $originalContent = Get-Content -LiteralPath (Join-Path $fx.UserProfilesDir 'GONE.xml') -Raw

        $profileIndex = @{ 'gone.exe' = @('GONE') }
        $reports = Repair-GamePaths -userProfilesDir $fx.UserProfilesDir -installFolder $fx.InstallFolder -profileIndex $profileIndex -DryRun $false

        $reports.Count | Should -Be 1
        $reports[0].Status | Should -Be 'not-found' -Because "a genuinely missing exe must surface as Action Required, never a fabricated or guessed path"
        (Get-Content -LiteralPath (Join-Path $fx.UserProfilesDir 'GONE.xml') -Raw) | Should -Be $originalContent
    }

    It "a valid, already-correct GamePath is left completely untouched (no unnecessary writes)" {
        $fx = New-ConflictFixture -Name 'moved-already-valid'
        $gameFolder = Join-Path $fx.InstallFolder 'StillHere'
        New-Item -ItemType Directory -Path $gameFolder -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $gameFolder 'valid.exe') -Force | Out-Null

        $validProfile = @"
<?xml version="1.0" encoding="utf-8"?>
<GameProfile>
  <ExecutableName>valid.exe</ExecutableName>
  <GamePath>$(Join-Path $gameFolder 'valid.exe')</GamePath>
  <EmulationProfile>Generic</EmulationProfile>
</GameProfile>
"@
        $profilePath = Join-Path $fx.UserProfilesDir 'VALID.xml'
        Set-Content -LiteralPath $profilePath -Value $validProfile -Encoding utf8
        $originalWriteTime = (Get-Item -LiteralPath $profilePath).LastWriteTimeUtc
        Start-Sleep -Milliseconds 50

        $profileIndex = @{ 'valid.exe' = @('VALID') }
        $reports = Repair-GamePaths -userProfilesDir $fx.UserProfilesDir -installFolder $fx.InstallFolder -profileIndex $profileIndex -DryRun $false

        $reports.Count | Should -Be 0 -Because "a profile whose GamePath already resolves must never even be reported, let alone rewritten"
        (Get-Item -LiteralPath $profilePath).LastWriteTimeUtc | Should -Be $originalWriteTime -Because "the file must not be touched at all -- proves the valid-path check happens before any write attempt"
    }

    It "DryRun reports what would be fixed without writing anything to disk" {
        $fx = New-ConflictFixture -Name 'moved-dryrun'
        $newGameFolder = Join-Path $fx.InstallFolder 'NewLocation'
        New-Item -ItemType Directory -Path $newGameFolder -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $newGameFolder 'dryrun.exe') -Force | Out-Null

        $staleProfile = @'
<?xml version="1.0" encoding="utf-8"?>
<GameProfile>
  <ExecutableName>dryrun.exe</ExecutableName>
  <GamePath>C:\OldLocation\dryrun.exe</GamePath>
  <EmulationProfile>Generic</EmulationProfile>
</GameProfile>
'@
        $profilePath = Join-Path $fx.UserProfilesDir 'DRYRUN.xml'
        Set-Content -LiteralPath $profilePath -Value $staleProfile -Encoding utf8
        $originalContent = Get-Content -LiteralPath $profilePath -Raw

        $profileIndex = @{ 'dryrun.exe' = @('DRYRUN') }
        $reports = Repair-GamePaths -userProfilesDir $fx.UserProfilesDir -installFolder $fx.InstallFolder -profileIndex $profileIndex -DryRun $true

        $reports.Count | Should -Be 1
        $reports[0].Status | Should -Be 'fixed' -Because "DryRun still reports what WOULD happen, so a preview is meaningful"
        (Get-Content -LiteralPath $profilePath -Raw) | Should -Be $originalContent -Because "DryRun must never actually write the fix to disk"
    }


Describe "Virtual Beta Tester: manual registration candidate choice" -Tag 'TVD-High' {
    It "writes only the explicitly selected candidate profile and preserves the ambiguity boundary" {
        $fx = New-ConflictFixture -Name 'manual-registration-choice'
        $gameFolder = Join-Path $fx.InstallFolder 'Shared Game'
        New-Item -ItemType Directory -Path $gameFolder -Force | Out-Null
        $exePath = Join-Path $gameFolder 'shared.exe'
        New-Item -ItemType File -Path $exePath -Force | Out-Null
        $template = @'
<?xml version="1.0" encoding="utf-8"?>
<GameProfile><ExecutableName>shared.exe</ExecutableName><GamePath></GamePath></GameProfile>
'@
        Set-Content -LiteralPath (Join-Path $fx.GameProfilesDir 'PROFILEA.xml') -Value $template -Encoding utf8
        Set-Content -LiteralPath (Join-Path $fx.GameProfilesDir 'PROFILEB.xml') -Value $template -Encoding utf8
        $manual = @{ 'Shared Game' = @{ Exe = $exePath; Profiles = 'PROFILEA, PROFILEB' } }
        $result = [pscustomobject]@{ Registered = New-Object System.Collections.ArrayList }
        Mock Read-Host { return '2' }

        Invoke-ManualRegistrationChoices -ManualRegData $manual -UserProfilesDir $fx.UserProfilesDir `
            -GameProfilesDir $fx.GameProfilesDir -InstallFolder $fx.InstallFolder -Result $result

        (Test-Path -LiteralPath (Join-Path $fx.UserProfilesDir 'PROFILEB.xml')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $fx.UserProfilesDir 'PROFILEA.xml')) | Should -Be $false
        $manual.Count | Should -Be 0
        ([xml](Get-Content -LiteralPath (Join-Path $fx.UserProfilesDir 'PROFILEB.xml') -Raw)).GameProfile.GamePath | Should -Be $exePath
    }

    It "leaves the candidate unresolved when the user declines to choose" {
        $fx = New-ConflictFixture -Name 'manual-registration-decline'
        $gameFolder = Join-Path $fx.InstallFolder 'Shared Game'
        New-Item -ItemType Directory -Path $gameFolder -Force | Out-Null
        $exePath = Join-Path $gameFolder 'shared.exe'
        New-Item -ItemType File -Path $exePath -Force | Out-Null
        $manual = @{ 'Shared Game' = @{ Exe = $exePath; Profiles = 'PROFILEA, PROFILEB' } }
        $result = [pscustomobject]@{ Registered = New-Object System.Collections.ArrayList }
        Mock Read-Host { return '' }

        Invoke-ManualRegistrationChoices -ManualRegData $manual -UserProfilesDir $fx.UserProfilesDir `
            -GameProfilesDir $fx.GameProfilesDir -InstallFolder $fx.InstallFolder -Result $result

        $manual.Count | Should -Be 1
        $result.Registered.Count | Should -Be 0
    }
}

}