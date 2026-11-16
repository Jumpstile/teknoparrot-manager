#Requires -Module Pester

# FIX110A (S-6): Invoke-PostgresReinitializePlan keeps the selection and tells the truth about what happened.
#   1. Only the selected databases are looked at again before the first change. An unrelated registered database is not "drift".
#   2. Only SUCCEEDED counts as finished work. A rebuild that was undone and checked (ROLLED_BACK_VERIFIED) is reported as undone, never as reinitialized.
#   3. Every rebuild input is checked before the first database is touched, and a later problem never erases the result of an earlier database.
# These tests drive the real product function with synthetic plans in $TestDrive. The database reset, the profile scan and the log are replaced by fixtures,
# so no database, profile, service or network is touched.
# What this CANNOT prove: that a real PostgreSQL rebuild succeeds or rolls back (the nested reset is a fixture).

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $script:f110aAst = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX110A bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'fix110a-pg-functions.ps1'
    ($script:f110aAst.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:DisplayVersion = 'v1.0 RC8'
    $script:logPath = Join-Path $TestDrive 'fix110a-pg.log'
    $script:logWarnShown = $false

    function New-F110aPlan {
        param([string]$Code, [string]$Database, [switch]$NoBackupFile, [string]$Encoding = 'UTF8')
        $backup = ''
        if (-not $NoBackupFile) {
            $backup = Join-Path $TestDrive ($Code + '.pg_backup')
            [System.IO.File]::WriteAllText($backup, 'fixture')
        }
        return [pscustomobject]@{ GameLabel = ('Game ' + $Code); ProfileName = $Code; Database = $Database; BackupFile = $backup; Encoding = $Encoding }
    }
    function Get-F110aSelection {
        param([object[]]$Plans)
        $json = ConvertTo-PostgresReinitializePlanJson -Plans $Plans
        return [pscustomobject]@{ Json = $json; Hash = (Get-PostgresReinitializePlanHash -PlanJson $json) }
    }
    function Invoke-F110aPlan {
        param($Selection)
        return (Invoke-PostgresReinitializePlan -PlanJson $Selection.Json -PlanHash $Selection.Hash -UserProfilesDir $TestDrive -SuperPasswordPlain 'fixture-secret' -RecoveryBackup ([pscustomobject]@{ Path = $TestDrive; Verified = $true }))
    }
    # What the real nested reset returns for one database (only the fields the aggregate reads).
    function New-F110aNested {
        param([string]$Database, [string]$Outcome)
        return [pscustomobject]@{ Outcome = $Outcome; Items = @($Database) }
    }
}

Describe 'FIX110A S-6 reinitialize selection and honest aggregate outcome' {
    BeforeEach {
        $script:f110aLog = New-Object System.Collections.Generic.List[string]
        $script:f110aResets = New-Object System.Collections.Generic.List[string]
        Mock Write-Log { [void]$script:f110aLog.Add([string]$msg) }
        Mock Write-Host {}
        Mock Write-TpmCompactExtractionProgress {}
    }

    It 'revalidates only the selected databases, so an unrelated registered database is not drift' {
        # Mutation: call Get-PostgresReinitializePlansFromProfiles without -OnlyDatabases in Invoke-PostgresReinitializePlan -> the unrelated database B is part of "current" and the run stops with PLAN_CHANGED.
        $planA = New-F110aPlan -Code 'A' -Database 'DbA'
        $planB = New-F110aPlan -Code 'B' -Database 'DbB'
        $script:f110aRegistry = @($planA, $planB)
        Mock Get-PostgresReinitializePlansFromProfiles {
            param([string]$UserProfilesDir, [string[]]$OnlyDatabases = @())
            @($script:f110aRegistry | Where-Object { $OnlyDatabases.Count -eq 0 -or $OnlyDatabases -contains $_.Database })
        }
        Mock Reset-PostgresDatabaseFromBackup { [void]$script:f110aResets.Add([string]$DbName); New-F110aNested -Database $DbName -Outcome 'SUCCEEDED' }
        $result = Invoke-F110aPlan -Selection (Get-F110aSelection -Plans @($planA))
        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        @($script:f110aResets) | Should -Be @('DbA')
        Should -Invoke Get-PostgresReinitializePlansFromProfiles -Times 1 -Exactly -ParameterFilter { @($OnlyDatabases).Count -eq 1 -and @($OnlyDatabases)[0] -ceq 'DbA' }
    }

    It 'still stops before any change when a selected profile really changed' {
        # Mutation: skip the Test-PostgresReinitializePlan comparison of the current plans -> the changed profile is reinitialized anyway.
        $planA = New-F110aPlan -Code 'A' -Database 'DbA'
        $drifted = New-F110aPlan -Code 'A' -Database 'DbA'
        $drifted.GameLabel = 'Game A renamed'
        $script:f110aRegistry = @($drifted)
        Mock Get-PostgresReinitializePlansFromProfiles { param([string]$UserProfilesDir, [string[]]$OnlyDatabases = @()) @($script:f110aRegistry) }
        Mock Reset-PostgresDatabaseFromBackup { throw 'a drifted selection must never be reset' }
        $result = Invoke-F110aPlan -Selection (Get-F110aSelection -Plans @($planA))
        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.ReasonCode | Should -BeExactly 'PLAN_CHANGED'
        Should -Invoke Reset-PostgresDatabaseFromBackup -Times 0 -Exactly
    }

    It 'does not call a rebuild that was undone and checked a success, and keeps the rollback evidence' {
        # Mutation: put ROLLED_BACK_VERIFIED back into the success list of the aggregate (or keep looping after it) -> the run is reported SUCCEEDED/REINITIALIZED and database B is rebuilt too.
        # Mutation: parse the plan with @($PlanJson | ConvertFrom-Json) (no inner parentheses) -> on Windows PowerShell 5.1 the two-database plan is one nested item and every two-database test here stops with PLAN_INVALID.
        $planA = New-F110aPlan -Code 'A' -Database 'DbA'
        $planB = New-F110aPlan -Code 'B' -Database 'DbB'
        $script:f110aRegistry = @($planA, $planB)
        Mock Get-PostgresReinitializePlansFromProfiles { param([string]$UserProfilesDir, [string[]]$OnlyDatabases = @()) @($script:f110aRegistry | Where-Object { $OnlyDatabases -contains $_.Database }) }
        Mock Reset-PostgresDatabaseFromBackup { [void]$script:f110aResets.Add([string]$DbName); New-F110aNested -Database $DbName -Outcome 'ROLLED_BACK_VERIFIED' }
        $result = Invoke-F110aPlan -Selection (Get-F110aSelection -Plans @($planA, $planB))
        $result.Outcome | Should -BeExactly 'ROLLED_BACK_VERIFIED'
        # FIX128: the Summary is plain words. Mutation: the old "...The previous database state was restored and verified." text.
        $result.Summary | Should -BeExactly 'The rebuild did not finish. Your old data was put back and checked.'
        $result.Succeeded | Should -BeFalse
        $result.ProductState | Should -BeExactly 'UNCHANGED'
        $result.ReasonCode | Should -Not -BeExactly 'REINITIALIZED'
        @($script:f110aResets) | Should -Be @('DbA')
        $result.Rollback.Verified | Should -BeTrue
        @($result.Rollback.Items) | Should -Contain 'DbA'
        @($result.Mutation.FailedItems) | Should -Contain 'DbA'
        @($result.Mutation.FailedItems) | Should -Contain 'DbB'
        @($result.Mutation.CompletedItems) | Should -Not -Contain 'DbA'
    }

    It 'reports a partial result, with the rollback evidence, when one database finished and the next was undone' {
        # Mutation: count the undone database as completed, or lose the finished one -> DbB shows as done, or DbA is missing from ChangedItems.
        $planA = New-F110aPlan -Code 'A' -Database 'DbA'
        $planB = New-F110aPlan -Code 'B' -Database 'DbB'
        $script:f110aRegistry = @($planA, $planB)
        Mock Get-PostgresReinitializePlansFromProfiles { param([string]$UserProfilesDir, [string[]]$OnlyDatabases = @()) @($script:f110aRegistry | Where-Object { $OnlyDatabases -contains $_.Database }) }
        Mock Reset-PostgresDatabaseFromBackup { [void]$script:f110aResets.Add([string]$DbName); New-F110aNested -Database $DbName -Outcome $(if ($DbName -eq 'DbA') { 'SUCCEEDED' } else { 'ROLLED_BACK_VERIFIED' }) }
        $result = Invoke-F110aPlan -Selection (Get-F110aSelection -Plans @($planA, $planB))
        $result.Outcome | Should -BeExactly 'PARTIAL_APPLIED'
        $result.Summary | Should -BeExactly 'The rebuild worked for some of the games but not for all of them.'
        @($result.Mutation.ChangedItems) | Should -Be @('DbA')
        @($result.Mutation.CompletedItems) | Should -Be @('DbA')
        @($result.Mutation.FailedItems) | Should -Contain 'DbB'
        @($result.Rollback.Items) | Should -Contain 'DbB'
    }

    It 'checks every rebuild source before the first database is touched' {
        # Mutation: check each rebuild file only inside the loop (or drop the preflight loop) -> database A is rebuilt before the missing file of B is noticed.
        $planA = New-F110aPlan -Code 'A' -Database 'DbA'
        $planB = New-F110aPlan -Code 'B' -Database 'DbB' -NoBackupFile
        $script:f110aRegistry = @($planA, $planB)
        Mock Get-PostgresReinitializePlansFromProfiles { param([string]$UserProfilesDir, [string[]]$OnlyDatabases = @()) @($script:f110aRegistry | Where-Object { $OnlyDatabases -contains $_.Database }) }
        Mock Reset-PostgresDatabaseFromBackup { [void]$script:f110aResets.Add([string]$DbName); New-F110aNested -Database $DbName -Outcome 'SUCCEEDED' }
        $result = Invoke-F110aPlan -Selection (Get-F110aSelection -Plans @($planA, $planB))
        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.ReasonCode | Should -BeExactly 'REBUILD_BACKUP_MISSING'
        Should -Invoke Reset-PostgresDatabaseFromBackup -Times 0 -Exactly
    }

    It 'checks every other rebuild input (encoding, database name) before the first database is touched' {
        # Mutation: drop the Encoding / database-name checks of the preflight -> the blank Encoding of B stops the run with a binding error after A was rebuilt.
        $planA = New-F110aPlan -Code 'A' -Database 'DbA'
        $planB = New-F110aPlan -Code 'B' -Database 'DbB' -Encoding ''
        $script:f110aRegistry = @($planA, $planB)
        Mock Get-PostgresReinitializePlansFromProfiles { param([string]$UserProfilesDir, [string[]]$OnlyDatabases = @()) @($script:f110aRegistry | Where-Object { $OnlyDatabases -contains $_.Database }) }
        Mock Reset-PostgresDatabaseFromBackup { [void]$script:f110aResets.Add([string]$DbName); New-F110aNested -Database $DbName -Outcome 'SUCCEEDED' }
        $result = Invoke-F110aPlan -Selection (Get-F110aSelection -Plans @($planA, $planB))
        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.ReasonCode | Should -BeExactly 'PLAN_INVALID'
        Should -Invoke Reset-PostgresDatabaseFromBackup -Times 0 -Exactly
    }

    It 'keeps the finished database when the rebuild source of the next one disappears after the preflight' {
        # Mutation: return the default FAILED_BEFORE_MUTATION/UNCHANGED failure (or drop the earlier result) when a later database fails -> the finished database A vanishes from the result.
        $planA = New-F110aPlan -Code 'A' -Database 'DbA'
        $planB = New-F110aPlan -Code 'B' -Database 'DbB'
        $script:f110aRegistry = @($planA, $planB)
        Mock Get-PostgresReinitializePlansFromProfiles { param([string]$UserProfilesDir, [string[]]$OnlyDatabases = @()) @($script:f110aRegistry | Where-Object { $OnlyDatabases -contains $_.Database }) }
        Mock Reset-PostgresDatabaseFromBackup { [void]$script:f110aResets.Add([string]$DbName); New-F110aNested -Database $DbName -Outcome $(if ($DbName -eq 'DbA') { 'SUCCEEDED' } else { 'FAILED_BEFORE_MUTATION' }) }
        $result = Invoke-F110aPlan -Selection (Get-F110aSelection -Plans @($planA, $planB))
        $result.Outcome | Should -BeExactly 'PARTIAL_APPLIED'
        $result.ProductState | Should -BeExactly 'PARTIAL_KNOWN'
        @($result.Mutation.ChangedItems) | Should -Be @('DbA')
        @($result.Mutation.FailedItems) | Should -Contain 'DbB'
        $result.Mutation.Started | Should -BeTrue
    }

    It 'keeps the finished database and asks for attention when the next reset stops unexpectedly, without logging the password' {
        # Mutation: let the exception of the nested reset escape (no result at all) or log its text unredacted -> the finished database A is lost, or the password is written to the log.
        $planA = New-F110aPlan -Code 'A' -Database 'DbA'
        $planB = New-F110aPlan -Code 'B' -Database 'DbB'
        $script:f110aRegistry = @($planA, $planB)
        Mock Get-PostgresReinitializePlansFromProfiles { param([string]$UserProfilesDir, [string[]]$OnlyDatabases = @()) @($script:f110aRegistry | Where-Object { $OnlyDatabases -contains $_.Database }) }
        Mock Reset-PostgresDatabaseFromBackup {
            [void]$script:f110aResets.Add([string]$DbName)
            if ($DbName -eq 'DbB') { throw 'unexpected stop with fixture-secret inside' }
            New-F110aNested -Database $DbName -Outcome 'SUCCEEDED'
        }
        $result = Invoke-F110aPlan -Selection (Get-F110aSelection -Plans @($planA, $planB))
        $result.Outcome | Should -BeExactly 'ACTION_REQUIRED'
        $result.ProductState | Should -BeExactly 'UNKNOWN'
        @($result.Mutation.ChangedItems) | Should -Be @('DbA')
        @($result.Mutation.FailedItems) | Should -Contain 'DbB'
        ($script:f110aLog -join "`n") | Should -Not -Match 'fixture-secret'
    }

    It 'does not report a nested result it cannot classify as a clean failure' {
        # Mutation: restore the narrow attention check (only ACTION_REQUIRED) -> a nested cleanup-residue result after a real rebuild falls through to FAILED_BEFORE_MUTATION/UNCHANGED.
        $planA = New-F110aPlan -Code 'A' -Database 'DbA'
        $script:f110aRegistry = @($planA)
        Mock Get-PostgresReinitializePlansFromProfiles { param([string]$UserProfilesDir, [string[]]$OnlyDatabases = @()) @($script:f110aRegistry) }
        Mock Reset-PostgresDatabaseFromBackup { New-F110aNested -Database $DbName -Outcome 'CLEANUP_RESIDUE' }
        $result = Invoke-F110aPlan -Selection (Get-F110aSelection -Plans @($planA))
        $result.Outcome | Should -BeExactly 'ACTION_REQUIRED'
        $result.Mutation.Started | Should -BeTrue
    }
}
