#Requires -Module Pester

# FIX110A (S-22): the ReShade numbers and the removal preview agree with what the worker will really do about the source collection.
#   TeknoParrot Manager never writes inside the configured source folders. The deployment and the removal already refuse such a game, but
#   (1) the pre-consent preflight did not know the source folders, so "N can be changed now" counted games that are then refused, and
#   (2) the removal preview listed REMOVE lines for a game the removal then refused.
#   Now the preflight gets the same configured roots (and counts such a game as left alone, like the deployment loop does) and the preview says KEEP.
# These tests drive the real functions with synthetic profiles and scan records in $TestDrive; the ReShade file inspection is replaced by fixtures.
# What this CANNOT prove: that the menu passes the two source folders to the removal (script body) or a real ReShade install.

BeforeAll {
    $script:f110aScriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $script:f110aAst = [System.Management.Automation.Language.Parser]::ParseFile($script:f110aScriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX110A bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'fix110a-rp-functions.ps1'
    ($script:f110aAst.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:DisplayVersion = 'v1.0 RC8'
    $script:logPath = Join-Path $TestDrive 'fix110a-rp.log'
    $script:logWarnShown = $false

    # Two games: one inside the source folder (Main) and one in the games folder. Each has a game file and a profile.
    function New-F110aLibrary {
        $root = Join-Path $TestDrive ('lib-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $library = [ordered]@{ Root = $root; Profiles = (Join-Path $root 'UserProfiles'); Main = (Join-Path $root 'Collection'); Games = (Join-Path $root 'Games'); Files = @{}; Dirs = @{} }
        foreach ($folder in @($library.Profiles, $library.Main, $library.Games)) { [void][System.IO.Directory]::CreateDirectory($folder) }
        foreach ($spec in @(@{ Code = 'InsideGame'; Parent = $library.Main }, @{ Code = 'OutsideGame'; Parent = $library.Games })) {
            $dir = Join-Path $spec.Parent $spec.Code
            [void][System.IO.Directory]::CreateDirectory($dir)
            $exe = Join-Path $dir 'game.exe'
            [System.IO.File]::WriteAllText($exe, 'MZ-test-game')
            $profile = Join-Path $library.Profiles ($spec.Code + '.xml')
            [System.IO.File]::WriteAllText($profile, ('<GameProfile><GameName>Game {0}</GameName><GamePath>{1}</GamePath></GameProfile>' -f $spec.Code, [System.Security.SecurityElement]::Escape($exe)), (New-Object System.Text.UTF8Encoding $false))
            $library.Files[$spec.Code] = $profile
            $library.Dirs[$spec.Code] = $dir
        }
        return [pscustomobject]$library
    }
}

Describe 'FIX110A S-22 ReShade preflight counts agree with the source-folder guard' {
    BeforeEach {
        $script:f110aRows = New-Object System.Collections.Generic.List[string]
        $script:f110aLog = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { [void]$script:f110aRows.Add([string]($Object -join ' ')) }
        Mock Write-Log { [void]$script:f110aLog.Add([string]$msg) }
        Mock Write-TpmCompactExtractionProgress {}
        Mock Get-TpmReShadeGameLabel { [string]$Fallback }
        Mock Get-ExeArchitecture { 'x64' }
        Mock Get-ReShadeTargetInfo { [pscustomobject]@{ TargetDir = [string]$ExeDir; DllName = 'dxgi.dll' } }
        Mock Get-TpmReShadeOwnershipClassification { [pscustomobject]@{ Status = 'NotInstalled'; Detail = 'fixture' } }
    }

    It 'does not count a game inside the source folder as ready, and shows it as left alone' {
        # Mutation: drop -ProtectedRoots from the Test-TpmGameMutationPath call of Get-TpmReShadeApplyPreflight -> the game inside the source folder is counted Ready.
        $library = New-F110aLibrary
        $games = @($library.Files.Values | ForEach-Object { Get-Item -LiteralPath $_ } | Sort-Object BaseName)
        $profileDefinition = [pscustomobject]@{ ProfileId = 'Levels'; Effects = @() }
        $summary = Get-TpmReShadeApplyPreflight -SelectedGames $games -ProfileDefinition $profileDefinition -SourceDll '' -ProtectedRoots @($library.Main)
        @($summary.Records).Count | Should -Be 2
        $summary.Ready | Should -Be 1
        $summary.Unsafe | Should -Be 1
        $inside = @($summary.Records | Where-Object Game -eq 'InsideGame')
        $inside.Count | Should -Be 1
        $inside[0].Status | Should -BeExactly 'Unsafe'
        $inside[0].Detail | Should -Match 'inside the source folder'
        @($summary.Records | Where-Object Game -eq 'OutsideGame')[0].Status | Should -BeExactly 'Ready'
    }

    It 'still counts both games as ready when no source folder is configured' {
        # Mutation: treat every game as protected (ignore an empty root list) -> the game outside any source folder is left alone too.
        $library = New-F110aLibrary
        $games = @($library.Files.Values | ForEach-Object { Get-Item -LiteralPath $_ } | Sort-Object BaseName)
        $profileDefinition = [pscustomobject]@{ ProfileId = 'Levels'; Effects = @() }
        $summary = Get-TpmReShadeApplyPreflight -SelectedGames $games -ProfileDefinition $profileDefinition -SourceDll ''
        $summary.Ready | Should -Be 2
        $summary.Unsafe | Should -Be 0
    }

    It 'the setup passes the configured source folders to the preflight' {
        # Mutation: call Get-TpmReShadeApplyPreflight in Invoke-ReShadeSetupLegacy without -ProtectedRoots $sourceCollectionRoots -> the pre-consent counts ignore the source folders again.
        $source = [System.IO.File]::ReadAllText($script:f110aScriptPath)
        $source | Should -Match 'Get-TpmReShadeApplyPreflight -SelectedGames \$selectedGames[^\r\n]*-ProtectedRoots \$sourceCollectionRoots'
    }
}

Describe 'FIX110A S-22 ReShade removal preview does not promise a removal the worker refuses' {
    BeforeEach {
        $script:f110aRows = New-Object System.Collections.Generic.List[string]
        $script:f110aLog = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { [void]$script:f110aRows.Add([string]($Object -join ' ')) }
        Mock Write-Log { [void]$script:f110aLog.Add([string]$msg) }
        Mock Write-TpmCompactExtractionProgress {}
        Mock Read-HostSafe { '' }
        Mock Remove-TpmReShadeOwnedDeployment { throw 'nothing may be removed after the preview was declined' }
    }

    It 'says KEEP, not REMOVE, for a game inside the source folder and still says REMOVE for the others' {
        # Mutation: drop the source-folder check from the preview loop of Invoke-TpmReShadeRemoval -> a REMOVE line is shown for the game inside the source folder.
        $library = New-F110aLibrary
        $records = foreach ($code in @('InsideGame', 'OutsideGame')) {
            $file = Get-Item -LiteralPath $library.Files[$code]
            $dll = Join-Path $library.Dirs[$code] 'dxgi.dll'
            [pscustomobject]@{
                GameId = $code; ProfileFile = $file; Status = 'Removable'; Detail = 'fixture'; TargetDir = $library.Dirs[$code]
                RemovableFiles = @([pscustomobject]@{ Kind = 'Hook'; DestinationPath = $dll; RelativeSource = 'dxgi.dll' })
                ProtectedFiles = @(); ChangedFiles = @(); Reviewable = $true
            }
        }
        $scan = [pscustomobject]@{ Records = @($records); Reviewable = @($records) }
        Mock Get-TpmReShadeRemovalScan { $scan }
        Mock Select-RegisteredGamesInteractive { @($records | ForEach-Object { $_.ProfileFile }) }
        $null = Invoke-TpmReShadeRemoval -UserProfilesDir $library.Profiles -ProtectedRoots @($library.Main)
        $text = @($script:f110aRows) -join "`n"
        $text | Should -Not -Match 'REMOVE InsideGame'
        $text | Should -Match 'KEEP\s+InsideGame: the game is inside your source folder'
        $text | Should -Match 'REMOVE OutsideGame: dxgi\.dll'
        ($script:f110aLog -join "`n") | Should -Match 'ReShade removal preview KEEP source folder: InsideGame'
        Should -Invoke Remove-TpmReShadeOwnedDeployment -Times 0 -Exactly
    }

    It 'shows REMOVE for every game when no source folder is configured' {
        # Mutation: always show KEEP for a game with a known target folder -> a game outside every source folder is no longer listed for removal.
        $library = New-F110aLibrary
        $file = Get-Item -LiteralPath $library.Files['InsideGame']
        $record = [pscustomobject]@{
            GameId = 'InsideGame'; ProfileFile = $file; Status = 'Removable'; Detail = 'fixture'; TargetDir = $library.Dirs['InsideGame']
            RemovableFiles = @([pscustomobject]@{ Kind = 'Hook'; DestinationPath = (Join-Path $library.Dirs['InsideGame'] 'dxgi.dll'); RelativeSource = 'dxgi.dll' })
            ProtectedFiles = @(); ChangedFiles = @(); Reviewable = $true
        }
        $scan = [pscustomobject]@{ Records = @($record); Reviewable = @($record) }
        Mock Get-TpmReShadeRemovalScan { $scan }
        Mock Select-RegisteredGamesInteractive { @($file) }
        $null = Invoke-TpmReShadeRemoval -UserProfilesDir $library.Profiles
        (@($script:f110aRows) -join "`n") | Should -Match 'REMOVE InsideGame: dxgi\.dll'
    }

    It 'does not say all clear when a game with ReShade files could not be checked' {
        # Who gets hurt: a user whose game is on an unplugged drive was told "No ReShade games need review" right under "missing saved path: 1".
        # Mutation: print the green all-clear whenever nothing is reviewable.
        $library = New-F110aLibrary
        $record = [pscustomobject]@{ GameId = 'InsideGame'; ProfileFile = (Get-Item -LiteralPath $library.Files['InsideGame']); Status = 'MissingPath'; Detail = 'fixture'; Reviewable = $false }
        $scan = [pscustomobject]@{ Records = @($record); Reviewable = @() }
        Mock Get-TpmReShadeRemovalScan { $scan }
        $null = Invoke-TpmReShadeRemoval -UserProfilesDir $library.Profiles
        $text = @($script:f110aRows) -join "`n"
        $text | Should -Not -Match 'No ReShade games need review'
        $text | Should -Match 'some games could not be checked'
    }

    It 'still says all clear when every game is already clean' {
        $library = New-F110aLibrary
        $record = [pscustomobject]@{ GameId = 'InsideGame'; ProfileFile = (Get-Item -LiteralPath $library.Files['InsideGame']); Status = 'AlreadyClean'; Detail = 'fixture'; Reviewable = $false }
        $scan = [pscustomobject]@{ Records = @($record); Reviewable = @() }
        Mock Get-TpmReShadeRemovalScan { $scan }
        $null = Invoke-TpmReShadeRemoval -UserProfilesDir $library.Profiles
        (@($script:f110aRows) -join "`n") | Should -Match 'No ReShade games need review or safe removal'
    }
}
