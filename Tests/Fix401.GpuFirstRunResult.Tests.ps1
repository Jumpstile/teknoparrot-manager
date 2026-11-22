#Requires -Module Pester

# Issue #401 follow-up: the GPU fix result (menu 7 and the first-run setup) for games on a drive that is not connected.
#   - A skip because of a missing drive names the drive and is not counted as a failure.
#   - The progress bar does not end as FAILED when nothing failed and games were only skipped.
#   - The counts line says how many games were selected, changed, skipped and failed.
# Only the function definitions are loaded. Nothing real is read or written.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:logPath = Join-Path $TestDrive 'test.log'
    Mock Write-Log {}
    Mock Write-Host {}

    function New-GpuSkip { param([string]$Game, [string]$Path) [pscustomobject]@{ Game = $Game; ReasonKey = 'DEVICE_UNAVAILABLE'; Reason = 'The saved game drive or device is unavailable.'; SavedPath = $Path; NextAction = 'n'; Technical = 't' } }
    # What the GPU fix engine returns when two of four selected games are on drive L: (not connected) and two were changed.
    function New-LegacyGpu {
        param([string[]]$Changed, [string[]]$Skipped, [object[]]$Details)
        [pscustomobject]@{
            Succeeded = $false; GpuName = 'NVIDIA Test'; GpuVendor = 'NVIDIA'; Updated = $Changed.Count; Unchanged = 0; NotApplicable = 0; Skipped = $Skipped.Count
            MissingDevice = $Skipped.Count; MissingPath = 0; Errors = 0; SkipDetails = $Details; FailureRecords = @(); Backup = $null; Reason = $null
            SelectedItems = @($Changed + $Skipped); ChangedItems = $Changed; CompletedItems = $Changed; FailedItems = @(); SkippedItems = $Skipped; UnattemptedItems = @(); UnknownItems = @()
        }
    }
}

Describe 'GPU fix with games on a drive that is not connected (#401)' {
    It 'names the drive, calls the games skipped, and shows how many were selected, changed and skipped' {
        $details = @((New-GpuSkip 'GameC' 'L:\Games\c\c.exe'), (New-GpuSkip 'GameD' 'L:\Games\d\d.exe'))
        Mock Invoke-GpuFixSetupLegacy { New-LegacyGpu -Changed @('GameA', 'GameB') -Skipped @('GameC', 'GameD') -Details $details }
        $result = Invoke-GpuFixSetup -UserProfilesDir (Join-Path $TestDrive 'UP') -TpRoot $TestDrive
        $view = Get-TpmGpuFixResultView -Result $result
        $view.Needs | Should -Contain '2 games skipped. Drive L: is not connected.'
        ($view.Done -join ' ') | Should -Match 'You selected 4 games: 2 changed, 2 skipped\.'
        ($view.Needs -join ' ') | Should -Not -Match 'fail'
    }

    It 'does not end the progress bar as FAILED when games were only skipped' {
        $details = @((New-GpuSkip 'GameC' 'L:\Games\c\c.exe'))
        Mock Invoke-GpuFixSetupLegacy { New-LegacyGpu -Changed @() -Skipped @('GameC') -Details $details }
        $result = Invoke-GpuFixSetup -UserProfilesDir (Join-Path $TestDrive 'UP') -TpRoot $TestDrive
        $result.Outcome | Should -Be 'FAILED_BEFORE_MUTATION'
        Get-TpmProgressCloseState -Result $result | Should -Be 'Final'
    }

    It 'names two missing drives' {
        $details = @((New-GpuSkip 'GameC' 'L:\a.exe'), (New-GpuSkip 'GameD' 'M:\b.exe'))
        Mock Invoke-GpuFixSetupLegacy { New-LegacyGpu -Changed @('GameA') -Skipped @('GameC', 'GameD') -Details $details }
        $result = Invoke-GpuFixSetup -UserProfilesDir (Join-Path $TestDrive 'UP') -TpRoot $TestDrive
        (Get-TpmGpuFixResultView -Result $result).Needs | Should -Contain '2 games skipped. Drives L: and M: are not connected.'
    }
}
