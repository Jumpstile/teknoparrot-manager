#Requires -Module Pester

# FIX88: failures of the first full run on the integrated tree.
#
#  1. A mandatory list parameter that was handed an empty list (Add-TpmDetailLine, Add-TpmPlainReasonLine) made the
#     GPU Fix and dgVoodoo2 result screens fail before they printed anything.
#  2. A PostgreSQL setup result with no per-game records was treated as one null game, which made the result log
#     (and so menu 13) fail.
#  3. A step-start log line written while the start-up log was being moved changed the log after its copy was checked,
#     so the move failed and start-up stopped.
#
# The production script is parsed and only its function definitions are dot-sourced. Every file lives under TestDrive.
# Each It names the product mutation that makes it fail.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $script:F88Ast = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX88 tests could not parse the production script.' }
    $definitions = @($script:F88Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    $script:F88FunctionText = @{}
    foreach ($definition in $definitions) {
        if (-not $script:F88FunctionText.ContainsKey($definition.Name)) { $script:F88FunctionText[$definition.Name] = $definition.Extent.Text }
    }
    $functionFile = Join-Path $TestDrive 'tpm-fix88-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, (@($definitions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"), (New-Object System.Text.UTF8Encoding $false))
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
}

Describe 'FIX88 detail helpers accept an empty list' {
    It 'Add-TpmDetailLine adds its line to an empty list' {
        # Mutation: remove [AllowEmptyCollection()] from the Lines parameter of Add-TpmDetailLine.
        $lines = New-Object System.Collections.Generic.List[string]
        Add-TpmDetailLine -Lines $lines -Label 'Step' -Text 'verified backup'
        $lines.Count | Should -Be 1
        $lines[0] | Should -BeExactly 'Step: verified backup'
    }

    It 'Add-TpmPlainReasonLine gives an empty list the plain sentence for the code' {
        # Mutation: remove [AllowEmptyCollection()] from the Lines parameter of Add-TpmPlainReasonLine.
        $lines = New-Object System.Collections.Generic.List[string]
        Add-TpmPlainReasonLine -Lines $lines -Code 'NOT_A_REAL_CODE'
        $lines.Count | Should -Be 1
        $lines[0] | Should -BeExactly ((Get-TpmPlainReason -Code 'NOT_A_REAL_CODE').Text)
    }
}

Describe 'FIX88 PostgreSQL setup result without per-game records' {
    BeforeEach {
        $script:F88Log = New-Object System.Collections.Generic.List[string]
        $script:F88Screen = New-Object System.Collections.Generic.List[string]
        Mock Write-Log { [void]$script:F88Log.Add([string]$msg) }
        Mock Write-Host { [void]$script:F88Screen.Add([string]($Object -join ' ')) }
        Mock Get-ConsoleContentWidth { return 100 }
        $script:F88NoGames = [pscustomobject]@{
            Configured = 2; DbCreated = 0; AlreadyConfigured = 2; Errors = 0; PassKeptProfiles = @()
            Summary = 'Fixture PostgreSQL setup result.'; Warnings = @(); RecoveryActions = @(); FinalVerification = $null
        }
    }

    It 'writes the result log without a game and without failing' {
        # Mutation: iterate @($Result.GameOutcomes) in Write-TpmPostgresSetupResultLog, where a missing list is one null game.
        { Write-TpmPostgresSetupResultLog -Result $script:F88NoGames } | Should -Not -Throw
        @($script:F88Log | Where-Object { $_ -like 'Postgres setup result:*' }).Count | Should -Be 0
    }

    It 'skips a null entry in the list and still logs the real game' {
        # Mutation: keep null entries in the game list.
        $result = [pscustomobject]@{
            GameOutcomes = @($null, [pscustomobject]@{ Key = 'Game1'; Name = 'Golden Tee'; DbName = 'GameDB01'; Outcome = 'CreatedFromBackup' })
            FinalVerification = $null; Warnings = @(); RecoveryActions = @()
        }
        Write-TpmPostgresSetupResultLog -Result $result
        $script:F88Log | Should -Contain 'Postgres setup result: Golden Tee [Game1] (GameDB01): CreatedFromBackup.'
        @($script:F88Log | Where-Object { $_ -like 'Postgres setup result:*' }).Count | Should -Be 1
    }

    It 'shows the finished screen and the details without a game block' {
        # Mutation: build the screen or the details from @($Result.GameOutcomes) directly.
        { Write-TpmPostgresSetupResult -Result $script:F88NoGames -OfferDetails } | Should -Not -Throw
        $script:F88Screen | Should -Contain '  PostgreSQL setup finished.'
        { Write-TpmPostgresSetupDetails -Result $script:F88NoGames } | Should -Not -Throw
        @($script:F88Screen | Where-Object { $_ -like '*What setup checked*' }).Count | Should -Be 0
    }
}

Describe 'FIX88 start-up log stays unchanged while it is moved' {
    BeforeAll {
        # Recording stand-ins for the progress module; the real wrapper and the real migration are the units under test.
        function Import-TpmProgressModule {}
        function Test-TpmProgressActive { return $false }
        function Test-TpmProgressGroupOwned { return $false }
        function Get-TpmProgressTitle { return '' }
        function Register-TpmProgressOutcome { param($State) }
        function Start-TpmProgressOperation { param($Title, $Stage, $Total, $Width, [switch]$Group, $Unit = 'Items') }
        function Set-TpmProgressStage { param([string]$Stage, [long]$Current, [long]$Total, [switch]$StageOnly, $Unit = 'Items', [switch]$SameStage) }
        function Complete-TpmProgressOperation { param($State = 'Final', $Message = '', [switch]$Superseded) }
        function Format-TpmProgressLine { param($Title, $Stage, $Current, $Total, $ElapsedSeconds, $Width, $Unit = 'Items') return ('{0}/{1}' -f $Current, $Total) }
        . ([scriptblock]::Create($script:F88FunctionText['Write-TpmCompactExtractionProgress']))
    }
    BeforeEach {
        $script:TpmLastLoggedProgressLabel = $null
        $script:TpmStartupLogFrozen = $false
        $script:F88StepLog = New-Object System.Collections.Generic.List[string]
    }

    It 'logs a step start while the log is free and not while it is frozen' {
        # Mutation: drop the TpmStartupLogFrozen test from the step-start log line in Write-TpmCompactExtractionProgress.
        Mock Write-Log { [void]$script:F88StepLog.Add([string]$msg) }
        $script:TpmStartupLogFrozen = $true
        Write-TpmCompactExtractionProgress -Phase Repairing -Label 'Owned-state migration' -Current 1 -Total 2
        @($script:F88StepLog | Where-Object { $_ -like 'Progress step:*' }).Count | Should -Be 0
        $script:TpmStartupLogFrozen = $false
        Write-TpmCompactExtractionProgress -Phase Repairing -Label 'Owned-state migration' -Current 1 -Total 2
        $script:F88StepLog | Should -Contain 'Progress step: Owned-state migration (shown as "Updating TeknoParrot Manager files")'
    }

    It 'moves the live start-up log with the config unchanged and frees the log afterwards' {
        # Mutation: remove the freeze around the backup and move in Invoke-TpmOwnedMigration; the step-start log line then
        # changes the log after its copy was checked and the migration rolls back.
        $root = Join-Path $TestDrive 'fix88-migration'
        $scriptRoot = Join-Path $root 'program'
        $tpRoot = Join-Path $root 'TeknoParrot'
        New-Item -ItemType Directory -Path $scriptRoot, $tpRoot -Force | Out-Null
        $liveLog = Join-Path $scriptRoot 'TeknoParrot-Manager.log'
        $firstLine = '[2026-11-03 10:00:00] [RunId=00000000000000000000000000000000] start' + [Environment]::NewLine
        [System.IO.File]::WriteAllText($liveLog, $firstLine)
        [System.IO.File]::WriteAllText((Join-Path $scriptRoot 'TeknoParrot-Manager.config.json'), '{}')
        $layout = Initialize-TpmOwnedLayout -Layout (Get-TpmOwnedLayout -TeknoParrotRoot $tpRoot)

        $previousLogPath = $script:logPath
        $script:logPath = $liveLog
        try {
            Mock Read-TpmYesNo { 'Y' }
            $result = Invoke-TpmOwnedMigration -ScriptRoot $scriptRoot -Layout $layout
        } finally {
            $script:logPath = $previousLogPath
        }

        $result.Outcome | Should -Be 'SUCCEEDED'
        # The plan lines the question writes before the move come along; nothing is logged after the copy was checked (the freeze).
        $movedLog = [System.IO.File]::ReadAllText((Join-Path $layout.Logs 'TeknoParrot-Manager.log'))
        $movedLog.StartsWith($firstLine) | Should -BeTrue
        $movedLog | Should -Not -Match 'Progress step:'
        Test-Path -LiteralPath $liveLog | Should -BeFalse
        $script:TpmStartupLogFrozen | Should -BeFalse
    }
}
