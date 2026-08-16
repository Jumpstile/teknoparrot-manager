#Requires -Module Pester

# Phase 0 contract tests. These tests invoke the explicit TPM contract entry
# point in a child PowerShell process. They never use the normal interactive
# menu and keep all fixture data under Pester's isolated TestDrive.

function global:New-Phase0Fixture {
    param([Parameter(Mandatory = $true)][string]$Root)

    $fixtureRoot = Join-Path $Root 'LaunchBox Phase0 Fixture With Spaces'
    $launchBoxData = Join-Path $fixtureRoot 'LaunchBox Data'
    $tpRoot = Join-Path $fixtureRoot 'TeknoParrot Root'
    $userProfiles = Join-Path $tpRoot 'UserProfiles'
    $gameRoot = Join-Path $fixtureRoot 'Selected Game Folder With Spaces'
    $tpmState = Join-Path $fixtureRoot 'TPM State'
    $resultDir = Join-Path $fixtureRoot 'Plugin Temp'
    $directories = @(
        $launchBoxData,
        (Join-Path $tpRoot 'GameProfiles'),
        $userProfiles,
        $gameRoot,
        $tpmState,
        $resultDir
    )
    New-Item -ItemType Directory -Path $directories -Force | Out-Null

    $launchBoxExe = Join-Path $fixtureRoot 'LaunchBox.exe'
    $tpExe = Join-Path $tpRoot 'TeknoParrotUi.exe'
    $gameExe = Join-Path $gameRoot 'Example Game.exe'
    New-Item -ItemType File -Path $launchBoxExe,$tpExe,$gameExe -Force | Out-Null
    $escapedGamePath = $gameExe.Replace('&', '&amp;')
    Set-Content -LiteralPath (Join-Path $userProfiles 'Example.xml') `
        -Value ("<GameProfile><GamePath>{0}</GamePath></GameProfile>" -f $escapedGamePath) -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $launchBoxData 'Games.xml') -Value '<LaunchBoxData />' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $tpmState 'TeknoParrot-Manager.config.json') -Value '{"readOnlyFixture":true}' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $gameRoot 'game-state.bin') -Value 'fixture' -Encoding ASCII

    return [pscustomobject][ordered]@{
        Root = $fixtureRoot
        LaunchBoxData = $launchBoxData
        TpRoot = $tpRoot
        UserProfiles = $userProfiles
        GameRoot = $gameRoot
        TpmState = $tpmState
        ResultDir = $resultDir
    }
}

function global:Get-Phase0Snapshot {
    param([Parameter(Mandatory = $true)][object]$Fixture)

    $roots = @(
        @{ Label = 'LaunchBoxData'; Path = $Fixture.LaunchBoxData }
        @{ Label = 'TeknoParrot'; Path = $Fixture.TpRoot }
        @{ Label = 'SelectedGame'; Path = $Fixture.GameRoot }
        @{ Label = 'TpmState'; Path = $Fixture.TpmState }
    )
    $records = New-Object System.Collections.ArrayList
    foreach ($root in $roots) {
        $rootFull = [System.IO.Path]::GetFullPath($root.Path).TrimEnd('\','/')
        $items = @(Get-Item -LiteralPath $root.Path -Force) + @(Get-ChildItem -LiteralPath $root.Path -Force -Recurse)
        foreach ($item in ($items | Sort-Object FullName)) {
            $relative = $item.FullName.Substring($rootFull.Length).TrimStart('\','/')
            $hash = $null
            $length = $null
            if (-not $item.PSIsContainer) {
                $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
                $length = [int64]$item.Length
            }
            [void]$records.Add([ordered]@{
                Label = $root.Label
                RelativePath = $relative
                IsDirectory = [bool]$item.PSIsContainer
                Length = $length
                Hash = $hash
                # Windows may update directory access bookkeeping during a
                # read-only enumeration. File timestamps remain strict; for
                # directories, creation time and attributes prove structure
                # without treating read access bookkeeping as a data write.
                LastWriteTimeUtc = if ($item.PSIsContainer) { $null } else { $item.LastWriteTimeUtc.ToString('o') }
                CreationTimeUtc = $item.CreationTimeUtc.ToString('o')
                Attributes = [string]$item.Attributes
            })
        }
    }
    return ($records | ConvertTo-Json -Depth 6 -Compress)
}

function global:Invoke-Phase0Contract {
    param(
        [Parameter(Mandatory = $true)][object]$Fixture,
        [hashtable]$RequestOverride,
        [string]$RawRequest,
        [string]$ExpectedCorrelationId,
        [string]$ResultPath,
        [Parameter(Mandatory = $true)][string]$ProductionScript,
        [Parameter(Mandatory = $true)][string]$PowerShellPath,
        [switch]$SkipRequestFile
    )

    $requestPath = Join-Path $Fixture.ResultDir ('request-' + [guid]::NewGuid().ToString('N') + '.json')
    if ([string]::IsNullOrWhiteSpace($RawRequest)) {
        $request = [ordered]@{
            contractVersion = '1.0'
            operationId = 'library.health-check'
            correlationId = ([guid]::NewGuid().ToString())
            paths = [ordered]@{
                userProfilesDirectory = $Fixture.UserProfiles
                teknoParrotRoot = $Fixture.TpRoot
            }
        }
        if ($RequestOverride) {
            foreach ($key in $RequestOverride.Keys) {
                $request[$key] = $RequestOverride[$key]
            }
        }
        $RawRequest = $request | ConvertTo-Json -Depth 6 -Compress
        if ([string]::IsNullOrWhiteSpace($ExpectedCorrelationId)) {
            $ExpectedCorrelationId = [string]$request.correlationId
        }
    }
    if (-not $SkipRequestFile) {
        Set-Content -LiteralPath $requestPath -Value $RawRequest -Encoding UTF8
    }
    if ([string]::IsNullOrWhiteSpace($ResultPath)) {
        $ResultPath = Join-Path $Fixture.ResultDir ('result-' + [guid]::NewGuid().ToString('N') + '.json')
    }

    $arguments = @(
        '-NoProfile',
        '-NonInteractive',
        '-File', $ProductionScript,
        '-FrontendContractRequestPath', $requestPath,
        '-FrontendContractResultPath', $ResultPath
    )
    if (-not [string]::IsNullOrWhiteSpace($ExpectedCorrelationId)) {
        $arguments += @('-FrontendContractCorrelationId', $ExpectedCorrelationId)
    }
    & $PowerShellPath @arguments
    $exitCode = $LASTEXITCODE
    $result = $null
    if (Test-Path -LiteralPath $ResultPath -PathType Leaf) {
        try { $result = Get-Content -LiteralPath $ResultPath -Raw | ConvertFrom-Json } catch { $result = $null }
    }
    return [pscustomobject][ordered]@{
        ExitCode = $exitCode
        Result = $result
        RequestPath = $requestPath
        ResultPath = $ResultPath
    }
}

BeforeAll {
    $script:Phase0ProductionScript = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'))
    $windowsPowerShell = Join-Path ([Environment]::GetFolderPath('Windows')) 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf) {
        $script:Phase0PowerShell = $windowsPowerShell
    } else {
        $script:Phase0PowerShell = (Get-Command pwsh -ErrorAction Stop).Source
    }
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    $script:Phase0PowerShell7 = if ($pwsh) { $pwsh.Source } else { $null }
}

Describe 'LaunchBox Phase 0 TPM contract' {
    It 'returns a structured read-only health result for paths containing spaces' {
        $fixture = New-Phase0Fixture -Root $TestDrive
        $before = Get-Phase0Snapshot -Fixture $fixture
        $call = Invoke-Phase0Contract -Fixture $fixture -ProductionScript $script:Phase0ProductionScript -PowerShellPath $script:Phase0PowerShell
        $after = Get-Phase0Snapshot -Fixture $fixture
        $call.ExitCode | Should -Be 0
        $call.Result.contractVersion | Should -Be '1.0'
        $call.Result.operationId | Should -Be 'library.health-check'
        $call.Result.status | Should -Be 'success'
        $call.Result.success | Should -BeTrue
        $call.Result.cancelled | Should -BeFalse
        $call.Result.errorCode | Should -Be 'NONE'
        @($call.Result.evidence).Count | Should -BeGreaterThan 0
        $after | Should -Be $before
    }

    It 'fails closed on an unsupported contract version' {
        $fixture = New-Phase0Fixture -Root $TestDrive
        $call = Invoke-Phase0Contract -Fixture $fixture -RequestOverride @{ contractVersion = '9.0' } -ProductionScript $script:Phase0ProductionScript -PowerShellPath $script:Phase0PowerShell

        $call.ExitCode | Should -Be 1
        $call.Result.errorCode | Should -Be 'CONTRACT_UNSUPPORTED_VERSION'
        $call.Result.success | Should -BeFalse
    }

    It 'returns a structured failure for malformed or truncated JSON' {
        $fixture = New-Phase0Fixture -Root $TestDrive
        $correlationId = [guid]::NewGuid().ToString()
        $call = Invoke-Phase0Contract -Fixture $fixture -RawRequest '{"contractVersion":"1.0"' -ExpectedCorrelationId $correlationId -ProductionScript $script:Phase0ProductionScript -PowerShellPath $script:Phase0PowerShell

        $call.ExitCode | Should -Be 1
        $call.Result.errorCode | Should -Be 'REQUEST_MALFORMED'
        ([guid]$call.Result.correlationId).ToString() | Should -Be $correlationId
    }

    It 'fails closed on a mismatched correlation ID' {
        $fixture = New-Phase0Fixture -Root $TestDrive
        $call = Invoke-Phase0Contract -Fixture $fixture -ExpectedCorrelationId ([guid]::NewGuid().ToString()) -ProductionScript $script:Phase0ProductionScript -PowerShellPath $script:Phase0PowerShell

        $call.ExitCode | Should -Be 1
        $call.Result.errorCode | Should -Be 'CORRELATION_MISMATCH'
    }

    It 'reports a missing TeknoParrot root without guessing' {
        $fixture = New-Phase0Fixture -Root $TestDrive
        $missingRoot = Join-Path $fixture.Root 'Missing TeknoParrot'
        $call = Invoke-Phase0Contract -Fixture $fixture -RequestOverride @{
            paths = [ordered]@{
                userProfilesDirectory = $fixture.UserProfiles
                teknoParrotRoot = $missingRoot
            }
        } -ProductionScript $script:Phase0ProductionScript -PowerShellPath $script:Phase0PowerShell

        $call.ExitCode | Should -Be 1
        $call.Result.errorCode | Should -Be 'TEKNOPARROT_NOT_FOUND'
    }

    It 'does not write when the result path overlaps protected TPM data' {
        $fixture = New-Phase0Fixture -Root $TestDrive
        $unsafeResult = Join-Path $fixture.TpRoot 'contract-result.json'
        $call = Invoke-Phase0Contract -Fixture $fixture -ResultPath $unsafeResult -ProductionScript $script:Phase0ProductionScript -PowerShellPath $script:Phase0PowerShell

        $call.ExitCode | Should -Be 1
        Test-Path -LiteralPath $unsafeResult | Should -BeFalse
    }
    It 'enters contract mode before normal startup and never prompts' {
        $fixture = New-Phase0Fixture -Root $TestDrive
        $before = Get-Phase0Snapshot -Fixture $fixture
        $call = Invoke-Phase0Contract -Fixture $fixture -ProductionScript $script:Phase0ProductionScript -PowerShellPath $script:Phase0PowerShell
        $after = Get-Phase0Snapshot -Fixture $fixture
        $source = Get-Content -LiteralPath $script:Phase0ProductionScript -Raw
        $mode = $source.IndexOf('$script:FrontendContractMode = -not')
        $dispatch = $source.IndexOf('if ($script:FrontendContractMode)')
        $normalLog = $source.IndexOf('Write-Log "Script started')
        $config = $source.IndexOf('$configPath')
        $mode | Should -BeGreaterThan -1
        $dispatch | Should -BeGreaterThan $mode
        $normalLog | Should -BeGreaterThan $dispatch
        $config | Should -BeGreaterThan $dispatch
        $call.ExitCode | Should -Be 0
        $call.Result.success | Should -BeTrue
        $after | Should -Be $before
    }

    It 'returns a structured failure when the request file is missing' {
        $fixture = New-Phase0Fixture -Root $TestDrive
        $call = Invoke-Phase0Contract -Fixture $fixture -SkipRequestFile -ProductionScript $script:Phase0ProductionScript -PowerShellPath $script:Phase0PowerShell
        $call.ExitCode | Should -Be 1
        $call.Result.errorCode | Should -Be 'REQUEST_MISSING'
    }

    It 'has equivalent contract semantics under PowerShell 5.1 and PowerShell 7' {
        if (-not $script:Phase0PowerShell7) { Set-ItResult -Skipped -Because 'pwsh is not installed'; return }
        $fixture = New-Phase0Fixture -Root $TestDrive
        $ps51 = Invoke-Phase0Contract -Fixture $fixture -ProductionScript $script:Phase0ProductionScript -PowerShellPath $script:Phase0PowerShell
        $ps7 = Invoke-Phase0Contract -Fixture $fixture -ProductionScript $script:Phase0ProductionScript -PowerShellPath $script:Phase0PowerShell7
        $ps51.ExitCode | Should -Be $ps7.ExitCode
        $ps51.Result.contractVersion | Should -Be $ps7.Result.contractVersion
        $ps51.Result.operationId | Should -Be $ps7.Result.operationId
        $ps51.Result.status | Should -Be $ps7.Result.status
        $ps51.Result.success | Should -Be $ps7.Result.success
        @($ps51.Result.evidence).Count | Should -Be @($ps7.Result.evidence).Count
    }

}
