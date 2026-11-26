#Requires -Module Pester

# FIX41 P06 (dgVoodoo2 no-op screen claimed an installation) and P04 (a logical
# operator written after a command name became that command's argument).
# Parse the product; only the dgVoodoo2 result-view functions and their helpers are
# executed. Run on the test PC by the coordinator.

BeforeAll {
    $script:fix41SourcePath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $script:fix41Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:fix41SourcePath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX41 bootstrap could not parse the production script.' }

    # The functions behind the dgVoodoo2 result screen (menu 6) and the helpers they call, dot-sourced from the product's own text.
    $wanted41 = @('Get-TpmDgVoodoo2ResultView', 'Get-TpmDgVoodoo2DetailBlocks', 'Get-TpmDgVoodoo2GameOutcomes', 'Get-TpmStepCountsLine', 'Get-TpmBackupFolderLine', 'Get-TpmDriveSkipNext', 'Format-TpmNameList', 'Get-TpmGameTitle', 'Get-TpmGameTitleWithCode', 'Get-TpmGameDisplayLabel', 'Split-TpmRunTogetherGameName', 'Join-TpmPostgresSetupNames', 'Get-TpmTransactionField', 'Format-TpmGameCount', 'Format-TpmCountNoun', 'Add-TpmDetailLine')
    $functions41 = @($script:fix41Ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $wanted41 -contains $node.Name
    }, $true))
    foreach ($name41 in $wanted41) {
        if (@($functions41 | Where-Object { $_.Name -eq $name41 }).Count -ne 1) { throw "FIX41 bootstrap expected exactly one definition of $name41." }
    }
    $functionPath41 = Join-Path $TestDrive 'fix41-dg-functions.ps1'
    ($functions41 | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionPath41 -Encoding utf8
    . $functionPath41
}

Describe 'FIX41 P06 dgVoodoo2 result screen lists only real details' {
    It 'counts no installed or skipped game for a not-needed result without detail lists' {
        # Mutation: revert the result view to '@($Result.DeploymentDetails)' (and the skip list likewise) -> one $null entry,
        # so the title counts an installed game, one skipped group appears and the details get a block with an empty heading.
        $dgResult = [pscustomobject]@{ Succeeded = $true; NoOp = $true; Deployed = 0; Errors = 0; Reason = 'NOT_NEEDED' }

        $view = Get-TpmDgVoodoo2ResultView -Result $dgResult

        $view.Title | Should -BeExactly 'No game needed a new dgVoodoo2 file. Nothing was changed.'
        @($view.Needs).Count | Should -Be 0
        @($view.DetailBlocks | ForEach-Object { $_.Heading }) | Should -Be @('About this change')
    }

    It 'keeps every real detail and drops only null entries' {
        # Mutation: filter with Where-Object { $_ } on a property instead of $null -ne $_, or drop the filter.
        $dgResult = [pscustomobject]@{
            DeploymentDetails = @([pscustomobject]@{ Game = 'GameA'; LegacyApis = @('D3D8') }, $null, [pscustomobject]@{ Game = 'GameB'; LegacyApis = @() })
            SkipDetails = @($null, [pscustomobject]@{ Game = 'GameC' })
        }

        $view = Get-TpmDgVoodoo2ResultView -Result $dgResult

        $view.Title | Should -BeExactly 'dgVoodoo2 was added to 2 games.'
        @($view.Needs).Count | Should -Be 1
        @($view.Needs)[0] | Should -BeLike '1 game skipped (GameC)*'
        @($view.DetailBlocks | ForEach-Object { $_.Heading }) | Should -Be @('About this change', 'Every game you selected', 'GameA', 'GameB', 'Skipped game: GameC')
    }
}

Describe 'FIX41 P04 logical operators are never passed as command arguments' {
    It 'has no command call in the product that receives -and, -or, -xor, -not, -band, -bor or -bxor as a parameter' {
        # Mutation: revert the restore menu to 'if (Test-PostgresInstalled -and $postgresSuperPasswordEncrypted)'
        # -> the scan finds that call (the operator and the variable become ignored arguments).
        $operatorNames = @('and', 'or', 'xor', 'not', 'band', 'bor', 'bxor')
        $offenders = @($script:fix41Ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandParameterAst] -and
                $operatorNames -contains $node.ParameterName.ToLowerInvariant()
        }, $true) | ForEach-Object { 'line {0}: {1}' -f $_.Extent.StartLineNumber, $_.Parent.Extent.Text })

        $offenders | Should -BeNullOrEmpty
    }
}
