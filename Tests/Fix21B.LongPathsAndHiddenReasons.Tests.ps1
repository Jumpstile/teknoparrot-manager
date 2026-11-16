#Requires -Module Pester

# Plain refusal for a game folder over 259 characters, a cursor-hide scan that could not read UserProfiles, and a LaunchBox check
# that cannot list every process. Every case drives the real product function; the over-259 path is fake (nothing is created), because
# a real run with Windows long paths off is not possible on the PC these tests run on.
# The product script is parsed and only its function definitions are dot-sourced; nothing touches TeknoParrot, LaunchBox, the registry or the network.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'fix21b-functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false
    $script:logPath = Join-Path $TestDrive 'fix21b.log'
    $script:logWarnShown = $false
    $script:logFailedCount = 0

    # A folder path over 259 characters that does not exist anywhere.
    $script:F21LongDir = Join-Path $TestDrive 'game'
    while ($script:F21LongDir.Length -lt 280) { $script:F21LongDir = Join-Path $script:F21LongDir 'a-long-folder-name-for-testing' }
}

Describe 'A game folder over 259 characters is refused before anything is changed' {
    BeforeEach {
        Mock Write-Log {}
        Mock Write-Host {}
        Mock Write-TpmCompactExtractionProgress {}
    }

    It 'the fake path really is longer than 259 characters' {
        $script:F21LongDir.Length | Should -BeGreaterThan 259
    }

    It 'the promote refuses in plain words, creates no folder and leaves the staged file alone' {
        # Mutation: remove the length check -> the move throws a raw error and the result talks about an inconsistent target.
        $staging = Join-Path $TestDrive 'stage-promote'
        [void][System.IO.Directory]::CreateDirectory($staging)
        [System.IO.File]::WriteAllText((Join-Path $staging 'a.txt'), 'NEW')
        $caught = $null
        try { Invoke-TpmTransactionalPromote -StagingDir $staging -DestDir $script:F21LongDir -FileNames @('a.txt') } catch { $caught = $_ }
        $caught | Should -Not -BeNullOrEmpty
        $caught.Exception.Message | Should -Match 'too long'
        $caught.Exception.Message | Should -Match 'Move the game to a shorter folder'
        $caught.Exception.Message | Should -Match 'Nothing was changed\.$'
        $caught.Exception.Message | Should -Not -Match 'inconsistent'
        [string]$caught.Exception.Data['TpmNoChange'] | Should -BeExactly 'PATH_TOO_LONG'
        [System.IO.Directory]::Exists('\\?\' + $script:F21LongDir) | Should -BeFalse
        [System.IO.File]::ReadAllText((Join-Path $staging 'a.txt')) | Should -BeExactly 'NEW'
    }

    It 'the file batch (dgVoodoo2, force feedback, crosshair, CPS3) stops before the change with the same plain words' {
        # Mutation: remove the check in the batch preflight -> the result says "safety check" or a raw path error.
        $source = Join-Path $TestDrive 'batch-source.txt'
        [System.IO.File]::WriteAllText($source, 'NEW')
        $operation = [pscustomobject]@{ ItemId = 'one'; Operation = 'ADD'; DestinationPath = (Join-Path $script:F21LongDir 'a.txt'); SourcePath = $source; RootPath = $TestDrive }
        $result = Invoke-TpmTransactionalFileBatch -WorkflowKey 'Fix21B' -OperationKey 'LongPath' -Operations @($operation) -StagingDir (Join-Path $TestDrive 'batch-stage')
        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.ReasonCode | Should -BeExactly 'PATH_TOO_LONG'
        $result.Summary | Should -Match 'too long'
        $result.Summary | Should -Match 'Nothing was changed\.$'
        [System.IO.Directory]::Exists('\\?\' + $script:F21LongDir) | Should -BeFalse
    }
}

Describe 'Cursor-hide setup when UserProfiles cannot be read' {
    It 'says it could not check, never that no change is needed' {
        # Mutation: scan with SilentlyContinue again -> zero profiles gives NO_OP "No cursor-hiding profile changes are needed."
        $screen = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { [void]$screen.Add([string]($Object -join ' ')) }
        Mock Write-Log {}
        Mock Write-TpmCompactExtractionProgress {}
        $result = Invoke-CursorHideSetup -UserProfilesDir (Join-Path $TestDrive 'no-such-UserProfiles')
        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.ReasonCode | Should -BeExactly 'PROFILE_SCAN_INCOMPLETE'
        ($screen -join "`n") | Should -Match 'could not read the UserProfiles folder'
        ($screen -join "`n") | Should -Not -Match 'No cursor-hiding profile changes are needed'
    }
}

Describe 'LaunchBox running check' {
    It 'does not stop a LaunchBox write when Windows refuses to list every process' {
        # Mutation: let the Get-Process failure escape -> the write is aborted with a raw error instead of the plain "close LaunchBox" answer.
        Mock Write-Log {}
        Mock Get-Process { throw 'Access is denied' }
        { Test-LaunchBoxRunning } | Should -Not -Throw
        Test-LaunchBoxRunning | Should -BeOfType [bool]
    }
}

Describe 'Library Health force feedback row' {
    It 'reads Not checked, not OK, because the plugin itself is never looked at' {
        # Mutation: show OK when no profile needs the setting -> a user with a missing plugin reads OK.
        $result = [pscustomobject]@{
            DiscoveryComplete = $true; Registered = 1; Valid = @('A'); Broken = @(); Empty = @()
            GpuFixNeeded = @(); FfbBlasterNeeded = @(); DgVoodoo2Needed = @(); DetectedGpuVendor = 'Intel'
            PostgresInventoryStatus = 'Complete'; PostgresNeeded = @(); PostgresConfigured = 0
        }
        $row = @(Get-TpmLibraryHealthRows -Result $result | Where-Object Area -eq 'Force feedback')
        $row.Count | Should -Be 1
        $row[0].Text | Should -Match '^Not checked'
    }
}
