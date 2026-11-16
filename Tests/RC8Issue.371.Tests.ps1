#Requires -Module Pester
# Issue: https://github.com/Jumpstile/teknoparrot-manager/issues/371
# Audit: <audit-folder>/ISSUES-AUDIT-RESULT.md (#371, PARTIAL).
# Structural gap: option-12 dispatch is top-level. Never execute startup/menu,
# services, policy writes, or extracted top-level statements.
# FIX95 (B1): the trust-based password reset and its two restart latches are gone, so
# no TeknoParrot Manager step can leave an unrestored trust policy behind. These tests
# pin that withdrawal and the remaining option-12 outer cleanup gate.
BeforeAll {
    $sourcePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'TeknoParrot-Manager.ps1'
    $tokens = $null; $errors = $null
    $script:issue371Ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw ($errors -join '; ') }
    $outer = @($script:issue371Ast.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.TryStatementAst] -and $null -ne $n.Finally -and
        @($n.Finally.FindAll({ param($c)
            $c -is [System.Management.Automation.Language.CommandAst] -and $c.GetCommandName() -eq 'Restore-PostgresServiceState' -and
            $c.Extent.Text -eq 'Restore-PostgresServiceState -WasRunning $postgresServiceWasRunning'
        }, $true)).Count -gt 0
    }, $true))
    if ($outer.Count -ne 1) { throw 'Expected one option-12 try/finally that restores the original PostgreSQL service state.' }
    $script:outer371 = $outer[0]
}
Describe 'RC8 issue #371: option-12 cleanup cannot reactivate an unrestored trust policy (structural)' -Tag 'RC8-Issue' {
    It 'the option-12 outer finally restores the original service state through the one verified gate, with no latch clause and no direct restart' {
        # Mutation: re-adding a latch clause (e.g. `-not $script:PostgresAuthPolicyRestoreBlocked`), dropping the
        # `$null -ne $postgresServiceWasRunning` guard, reordering the -and operands, adding a direct Start-Service/Restart-Service
        # to the finally, or no longer recording `$postgresServiceRestoreFailed = $true` fails these assertions.
        $calls = @($script:outer371.Finally.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Restore-PostgresServiceState'
        }, $true))
        $calls.Count | Should -Be 1
        $guard = $calls[0].Parent
        while ($guard -and $guard -isnot [System.Management.Automation.Language.IfStatementAst]) { $guard = $guard.Parent }
        $guard | Should -Not -BeNullOrEmpty
        $guard.Clauses.Count | Should -Be 1
        $guard.Clauses[0].Item1.Extent.Text | Should -BeExactly '$null -ne $postgresServiceWasRunning -and -not (Restore-PostgresServiceState -WasRunning $postgresServiceWasRunning)'
        $guard.Clauses[0].Item2.Statements.Count | Should -Be 1
        $guard.Clauses[0].Item2.Statements[0].Extent.Text | Should -BeExactly '$postgresServiceRestoreFailed = $true'
        @($script:outer371.Finally.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -in @('Start-Service', 'Restart-Service', 'Set-Service')
        }, $true)).Count | Should -Be 0
    }
    It 'a failed or refused service restore after the outer cleanup never claims PostgreSQL setup complete' {
        # Mutation: deleting the `if ($postgresServiceRestoreFailed)` block after the try (or its `continue`, or the
        # marker-refusal explanation) lets option 12 report success while PostgreSQL was left stopped by the start gate.
        $block = $script:outer371.Parent
        $statements = @($block.Statements)
        $index = [array]::IndexOf($statements, $script:outer371)
        $index | Should -BeGreaterOrEqual 0
        $next = $statements[$index + 1]
        $next | Should -BeOfType ([System.Management.Automation.Language.IfStatementAst])
        $next.Clauses[0].Item1.Extent.Text | Should -BeExactly '$postgresServiceRestoreFailed'
        $body = $next.Clauses[0].Item2
        $body.Statements[$body.Statements.Count - 1] | Should -BeOfType ([System.Management.Automation.Language.ContinueStatementAst])
        # The Details block also reads the marker flag inside an expression; only the direct explanation counts here.
        @($body.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.IfStatementAst] -and $n.Parent -eq $body -and $n.Clauses[0].Item1.Extent.Text -eq '$script:PostgresServiceStartRefusedByMarker'
        }, $true)).Count | Should -Be 1
    }
    It 'the restart latches that guarded the withdrawn reset are gone from the whole product' {
        # Mutation: reintroducing `$script:PostgresAuthPolicyRestoreBlocked` or `$script:PostgresServiceRestartBlocked`
        # (assigned or read anywhere) fails the zero count.
        @($script:issue371Ast.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $n.VariablePath.UserPath -match '^(?i:script:)?(PostgresAuthPolicyRestoreBlocked|PostgresServiceRestartBlocked)$'
        }, $true)).Count | Should -Be 0
    }
    It 'the trust-based automatic password reset is withdrawn: no reset function is defined or called' {
        # Mutation: restoring Reset-PostgresPasswordAutomatically (or any of its trust-rule helpers) as a function
        # or a call fails the zero counts.
        $withdrawn = @('Reset-PostgresPasswordAutomatically', 'Invoke-PostgresSelectedPasswordRecovery', 'Write-PostgresTrustRuleMarker',
            'Write-PostgresTrustRuleMarkerDocument', 'Set-PostgresTrustRuleMarkerServiceUnconfirmed', 'ConvertTo-PostgresSqlPasswordLiteral',
            'Invoke-PostgresNativeProcessWithInput')
        @($script:issue371Ast.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in $withdrawn
        }, $true)).Count | Should -Be 0
        @($script:issue371Ast.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -in $withdrawn
        }, $true)).Count | Should -Be 0
    }
    It 'nothing writes the trust rule: the atomic pg_hba.conf writer is reached only from the backup restore, and no bare trust line exists' {
        # Mutation: a new call to Set-PostgresHbaPolicyAtomically outside Restore-PostgresHbaFromBackup (as the withdrawn
        # reset did with its trust bytes), or a bare 'host all postgres 127.0.0.1/32 trust' string to build such a file,
        # fails these assertions.
        $writers = @($script:issue371Ast.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Set-PostgresHbaPolicyAtomically'
        }, $true))
        $writers.Count | Should -Be 1
        $owner = $writers[0].Parent
        while ($owner -and $owner -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { $owner = $owner.Parent }
        $owner | Should -Not -BeNullOrEmpty
        $owner.Name | Should -BeExactly 'Restore-PostgresHbaFromBackup'
        @($script:issue371Ast.FindAll({ param($n)
            ($n -is [System.Management.Automation.Language.StringConstantExpressionAst] -or $n -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) -and
            $n.Value -match '^\s*host\s+all\s+postgres\s+127\.0\.0\.1/32\s+trust\s*$'
        }, $true)).Count | Should -Be 0
    }
}
