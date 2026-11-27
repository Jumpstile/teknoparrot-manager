#Requires -Module Pester

# Focused tests for recursive game-file discovery progress. The production
# script is parsed and only the pure functions under test are dot-sourced.
BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:sourcePath = Join-Path $script:repoRoot 'TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:sourcePath,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if ($parseErrors.Count -gt 0) {
        throw "Failed to parse TeknoParrot-Manager.ps1: $($parseErrors -join '; ')"
    }

    $functions = @(
        $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -in @('Get-GameFiles', 'Register-GamesLegacy', 'Get-TpmProfileFileExtensions', 'Get-TpmDatNamedProfileCodes', 'Register-TpmDatSecondProfiles', 'Register-TpmTeknoChiTwins')
        }, $true)
    )
    if ($functions.Count -ne 6) {
        throw "Expected the Get-GameFiles, Register-GamesLegacy and registration helper definitions; found $($functions.Count)."
    }

    $functionPath = Join-Path $TestDrive ('register-discovery-functions-' + [guid]::NewGuid().ToString('N') + '.ps1')
    ($functions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" |
        Set-Content -LiteralPath $functionPath -Encoding utf8
    $script:getGameFilesDefinition = ($functions | Where-Object { $_.Name -eq 'Get-GameFiles' }).Extent.Text
    . $functionPath

    # Registration's profile-index scans and compact renderer are outside this
    # discovery-progress test. Keep their inputs empty and side effects inert.
    function Get-TpmRegisteredProfileFilesWithDiscoveryProgress {
        param([string]$UserProfilesDir, [string]$ProgressLabel, [string]$EnumerationErrorAction)
        return @()
    }
    function Write-TpmCompactExtractionProgress {
        param([string]$Phase, [string]$Label, [int]$Current, [int]$Total, [datetime]$StartedAt, [switch]$Complete, [string]$Outcome = 'Final')
    }
    function Write-Log {
        param([string]$Message)
    }
}

Describe 'Get-GameFiles discovery progress' {
    It 'preserves candidate membership and order while emitting truthful callback counts' {
        $root = 'C:\Fixture\Games'
        $script:gameFileDiscoveryInput = @(
            [pscustomobject]@{ Name='z.exe'; Extension='.exe'; FullName="$root\B\z.exe" }
            [pscustomobject]@{ Name='readme.txt'; Extension='.txt'; FullName="$root\B\readme.txt" }
            [pscustomobject]@{ Name='a.bin'; Extension='.bin'; FullName="$root\A\a.bin" }
            [pscustomobject]@{ Name='bare'; Extension=''; FullName="$root\bare" }
            [pscustomobject]@{ Name='too-deep'; Extension=''; FullName="$root\a\b\c\d\e\f\g\too-deep" }
            [pscustomobject]@{ Name='tpm.dll'; Extension='.dll'; FullName="$root\C\tpm.dll" }
        )
        $script:gameFileDiscoveryChildItemCalls = New-Object System.Collections.Generic.List[object]
        $script:gameFileDiscoveryCallbacks = New-Object System.Collections.Generic.List[object]

        Mock Get-ChildItem {
            [void]$script:gameFileDiscoveryChildItemCalls.Add([pscustomobject]@{
                LiteralPath = [string]$LiteralPath
                Recurse = [bool]$Recurse
                File = [bool]$File
            })
            $script:gameFileDiscoveryInput
        }

        $withoutProgress = @(Get-GameFiles -folder $root)
        $callback = {
            param($file, $seen)
            [void]$script:gameFileDiscoveryCallbacks.Add([pscustomobject]@{
                Path = if ($null -ne $file) { [string]$file.FullName } else { $null }
                Seen = [int]$seen
            })
            'callback output must not enter the candidate pipeline'
        }
        $withProgress = @(Get-GameFiles -folder $root -ProgressScript $callback)

        @($withoutProgress | ForEach-Object { $_.FullName }) -join '|' |
            Should -Be "$root\B\z.exe|$root\A\a.bin|$root\bare|$root\C\tpm.dll"
        @($withProgress | ForEach-Object { $_.FullName }) -join '|' |
            Should -Be (@($withoutProgress | ForEach-Object { $_.FullName }) -join '|')
        $callbackSeen = @($script:gameFileDiscoveryCallbacks | ForEach-Object { $_.Seen })
        $callbackSeen.Count | Should -BeGreaterThan 0
        $callbackSeen[0] | Should -Be 1
        $callbackSeen[-1] | Should -Be 6
        for ($i = 1; $i -lt $callbackSeen.Count; $i++) {
            $callbackSeen[$i] | Should -BeGreaterThan $callbackSeen[$i - 1]
        }
        foreach ($event in $script:gameFileDiscoveryCallbacks) {
            if ($event.Path) { $event.Path | Should -Be $script:gameFileDiscoveryInput[$event.Seen - 1].FullName }
        }
        $script:gameFileDiscoveryChildItemCalls.Count | Should -Be 2
        foreach ($call in $script:gameFileDiscoveryChildItemCalls) {
            $call.LiteralPath | Should -Be $root
            # The folder walk is manual (one call per folder, links are not followed), so it never asks for -Recurse.
            $call.Recurse | Should -BeFalse
        }
        @([regex]::Matches($script:getGameFilesDefinition, '-ErrorAction SilentlyContinue')).Count | Should -Be 1
    }

    It 'propagates a cancellation exception without returning a partial candidate set' {
        $root = 'C:\Fixture\Games'
        $script:gameFileDiscoveryInput = @(
            [pscustomobject]@{ Name='one.exe'; Extension='.exe'; FullName="$root\A\one.exe" }
        )
        Mock Get-ChildItem {
            $script:gameFileDiscoveryInput
            throw [System.OperationCanceledException]::new('fixture cancellation')
        }

        $script:gameFileDiscoverySeen = New-Object System.Collections.Generic.List[int]
        $callback = { param($file, $count) [void]$script:gameFileDiscoverySeen.Add([int]$count) }
        $caught = $null
        try {
            $null = Get-GameFiles -folder $root -ProgressScript $callback
        } catch {
            $caught = $_.Exception
        }

        $caught | Should -BeOfType [System.OperationCanceledException]
        # A folder listing that fails is abandoned as a whole: nothing from it is reported or returned.
        @($script:gameFileDiscoverySeen.ToArray()) -join ',' | Should -Be ''
    }
}

Describe 'Register-GamesLegacy discovery progress' {
    It 'shows truthful unknown-total progress during a dry-run with no candidates' {
        $root = Join-Path $TestDrive 'register-discovery-progress'
        $userProfiles = Join-Path $root 'UserProfiles'
        $games = Join-Path $root 'Games'
        $gameProfiles = Join-Path $root 'GameProfiles'
        New-Item -ItemType Directory -Path $userProfiles, $games, $gameProfiles -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $games 'readme.txt'), 'fixture')

        $script:registerDiscoveryMessages = New-Object System.Collections.Generic.List[string]
        $script:registerProgressCalls = New-Object System.Collections.Generic.List[object]
        Mock Write-Host {
            [void]$script:registerDiscoveryMessages.Add([string]$Object)
        }
        Mock Write-TpmCompactExtractionProgress {
            [void]$script:registerProgressCalls.Add([pscustomobject]@{ Phase = [string]$Phase; Label = [string]$Label; Current = [int]$Current; Total = [int]$Total; Complete = [bool]$Complete; Outcome = [string]$Outcome })
        }

        $result = @(Register-GamesLegacy -userProfilesDir $userProfiles -installFolder $games -profileIndex @{} -gameProfilesDir $gameProfiles -datIndex @{} -subFolderMap @{} -DryRun:$true)

        $result.Count | Should -Be 1
        @($result[0].Registered).Count | Should -Be 0
        @($result[0].Already).Count | Should -Be 0
        @($result[0].Ambiguous).Count | Should -Be 0
        # Discovery reports through the progress renderer: a zero start, the first visited entry, then one
        # completed row. Every call keeps the total unknown (0); no starting/visited console lines remain.
        $calls = @($script:registerProgressCalls | Where-Object { $_.Label -eq 'Game-file discovery' })
        $calls.Count | Should -BeGreaterOrEqual 3
        @($calls | Where-Object { $_.Phase -ne 'Scanning' -or $_.Total -ne 0 }).Count | Should -Be 0
        $calls[0].Current | Should -Be 0
        $calls[0].Complete | Should -BeFalse
        @($calls | Where-Object { -not $_.Complete -and $_.Current -eq 1 }).Count | Should -Be 1
        @($calls | Where-Object { $_.Complete }).Count | Should -Be 1
        $calls[$calls.Count - 1].Complete | Should -BeTrue
        $calls[$calls.Count - 1].Current | Should -Be 1
        $calls[$calls.Count - 1].Outcome | Should -Not -Be 'Error'
        (@($script:registerDiscoveryMessages) -join "`n") |
            Should -Match 'Game-file discovery: ended; candidates=0; visited=1'
        (@($script:registerDiscoveryMessages) -join "`n") | Should -Not -Match '\d+%'
        @(Get-ChildItem -LiteralPath $userProfiles -File).Count | Should -Be 0
    }

    It 'reports the exact final count after trailing entries fall below the progress interval' {
        $root = 'C:\Fixture\Games'
        $script:registerProgressRoot = $root
        $script:registerProgressInput = @(
            for ($i = 1; $i -le 260; $i++) {
                [pscustomobject]@{
                    Name = "note$i.txt"
                    Extension = '.txt'
                    FullName = "$root\note$i.txt"
                }
            }
        )
        $script:registerDiscoveryMessages = New-Object System.Collections.Generic.List[string]
        $script:registerProgressCalls = New-Object System.Collections.Generic.List[object]
        Mock Write-Host {
            [void]$script:registerDiscoveryMessages.Add([string]$Object)
        }
        Mock Write-TpmCompactExtractionProgress {
            [void]$script:registerProgressCalls.Add([pscustomobject]@{ Phase = [string]$Phase; Label = [string]$Label; Current = [int]$Current; Total = [int]$Total; Complete = [bool]$Complete; Outcome = [string]$Outcome })
        }
        Mock Get-ChildItem {
            if ($LiteralPath -eq $script:registerProgressRoot) { $script:registerProgressInput }
        }

        $result = @(Register-GamesLegacy -userProfilesDir 'C:\Fixture\UserProfiles' -installFolder $root -profileIndex @{} -datIndex @{} -subFolderMap @{} -DryRun:$true)
        $result.Count | Should -Be 1
        @($result[0].Registered).Count | Should -Be 0
        # The first visited entry is reported through progress; trailing entries below the interval are not
        # reported individually, but the completed row carries the exact final count with an unknown total.
        $calls = @($script:registerProgressCalls | Where-Object { $_.Label -eq 'Game-file discovery' })
        @($calls | Where-Object { $_.Total -ne 0 }).Count | Should -Be 0
        @($calls | Where-Object { -not $_.Complete -and $_.Current -eq 1 }).Count | Should -Be 1
        $calls[$calls.Count - 1].Complete | Should -BeTrue
        $calls[$calls.Count - 1].Current | Should -Be 260
        $calls[$calls.Count - 1].Outcome | Should -Not -Be 'Error'
        (@($script:registerDiscoveryMessages) -join "`n") | Should -Match 'ended; candidates=0; visited=260'
        (@($script:registerDiscoveryMessages) -join "`n") | Should -Not -Match '\d+%'
    }
    It 'closes the status as interrupted and propagates cancellation' {
        $root = Join-Path $TestDrive 'register-discovery-cancel'
        $userProfiles = Join-Path $root 'UserProfiles'
        $games = Join-Path $root 'Games'
        $gameProfiles = Join-Path $root 'GameProfiles'
        New-Item -ItemType Directory -Path $userProfiles, $games, $gameProfiles -Force | Out-Null
        $script:registerDiscoveryMessages = New-Object System.Collections.Generic.List[string]

        Mock Write-Host {
            [void]$script:registerDiscoveryMessages.Add([string]$Object)
        }
        Mock Get-GameFiles {
            param([string]$folder, [scriptblock]$ProgressScript)
            $file = [pscustomobject]@{
                Name='one.exe'; Extension='.exe'; FullName=(Join-Path $folder 'one.exe')
            }
            & $ProgressScript $file 1
            throw [System.OperationCanceledException]::new('fixture cancellation')
        }

        $caught = $null
        try {
            $null = Register-GamesLegacy -userProfilesDir $userProfiles -installFolder $games -profileIndex @{} -gameProfilesDir $gameProfiles -datIndex @{} -subFolderMap @{} -DryRun:$true
        } catch {
            $caught = $_.Exception
        }

        $caught | Should -BeOfType [System.OperationCanceledException]
        (@($script:registerDiscoveryMessages) -join "`n") |
            Should -Match 'Game-file discovery: interrupted; last-reported-visited=1'
        @(Get-ChildItem -LiteralPath $userProfiles -File).Count | Should -Be 0
    }
}
