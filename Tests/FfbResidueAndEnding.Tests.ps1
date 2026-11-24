#Requires -Module Pester

# Force feedback results:
#   - a removal that is verified but leaves only a temporary folder behind counts as done and shows the folder as a warning.
#   - the ending says the true reason when the plugin or FFB Blaster was skipped.
# Only the function definitions are loaded. Nothing real is read or written outside TestDrive.

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
}

Describe 'FFB plugin removal with only leftover temporary files' {
    It 'counts the removal as done, records the items and shows the leftover folder' {
        # Mutation: accept only SUCCEEDED/NO_OP -> this throws "rollback was incomplete" although the files are gone.
        $gameRoot = Join-Path $TestDrive 'Game'
        [void][IO.Directory]::CreateDirectory($gameRoot)
        $dest = Join-Path $gameRoot 'dinput8.dll'
        [IO.File]::WriteAllText($dest, 'plugin')
        $hash = (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash
        $entry = [pscustomobject]@{ ProfileCode = 'G1'; GameRoot = $gameRoot; Destination = $dest; DeployedSha256 = $hash }
        $leftover = Join-Path $TestDrive 'tx-leftover'
        Mock Read-FFBPluginOwnership { @($entry) }
        Mock Invoke-TpmFfbPluginFileTransaction {
            [pscustomobject]@{ Outcome = 'CLEANUP_RESIDUE'; UnderlyingOutcome = 'SUCCEEDED'; Cleanup = [pscustomobject]@{ ResiduePaths = @($leftover) } }
        }
        (Remove-FFBPluginOwnedDeployment -CacheDir (Join-Path $TestDrive 'cache') -ProfileCode 'G1') | Should -BeTrue
        @($script:FFBOwnedRemovalRecords).Count | Should -Be 1
        Should -Invoke Write-Host -ParameterFilter { $Object -like "*$leftover*" } -Times 1 -Exactly
    }
}

Describe 'Force feedback ending names the real reason for a skip' {
    It 'says the plugin was skipped because a file already exists' {
        # Mutation: fall back to "no game needed a change" -> the user is told nothing was needed when a file blocked the install.
        $view = Get-TpmFfbSetupEndingView -NativeResult $null -Plugin ([pscustomobject]@{ Deployed = 0; SkippedCollision = 2 }) -PluginChosen $true
        ($view.Done -join ' ') | Should -Match 'already have one of its files'
        ($view.Done -join ' ') | Should -Not -Match 'no game needed a change'
    }

    It 'says FFB Blaster was skipped when there is no membership' {
        $native = [pscustomobject]@{ Outcome = 'NO_OP'; ReasonCode = 'NO_MEMBERSHIP'; Mutation = $null }
        $view = Get-TpmFfbSetupEndingView -NativeResult $native -Plugin $null -PluginChosen $false
        ($view.Done -join ' ') | Should -Match 'FFB Blaster was skipped because you do not have the paid membership'
    }
}

Describe 'FFB plugin setup with an unreadable record of installed files' {
    It 'stops with a plain message and leaves the record as it was' {
        # Mutation: read an unreadable record as empty -> setup goes on and writes a new record over it.
        $cache = Join-Path $TestDrive 'ffbcache'
        [void][IO.Directory]::CreateDirectory($cache)
        $manifest = Get-FFBPluginOwnershipPath -CacheDir $cache
        [IO.File]::WriteAllText($manifest, '{ "Entries": [ { broken')
        $before = (Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash
        Mock Get-FFBPluginLatestRelease { throw 'setup must stop before it looks for a release' }
        $r = Invoke-FFBPluginSetup -UserProfilesDir (Join-Path $TestDrive 'UserProfiles') -CacheDir $cache
        $r.Succeeded | Should -BeFalse
        $r.Reason | Should -Be 'OWNERSHIP_MANIFEST_UNREADABLE'
        (Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash | Should -Be $before
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*cannot be read*' } -Times 1 -Exactly
    }
}
