#Requires -Module Pester
# Issue: https://github.com/Jumpstile/teknoparrot-manager/issues/339
# Audit: <audit-folder>/ISSUES-AUDIT-RESULT.md (#339, PARTIAL).
# AST-extract only the target and its real helper dependency closure. Never load startup.
BeforeAll {
    $sourcePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'TeknoParrot-Manager.ps1'
    $tokens = $null; $errors = $null
    $script:issueAst = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw ($errors -join '; ') }
    $definitions = @{}
    foreach ($node in $script:issueAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        if (-not $definitions.ContainsKey($node.Name)) { $definitions[$node.Name] = @() }
        $definitions[$node.Name] += $node
    }
    $external = @('Write-Log','Write-TpmCompactExtractionProgress','Write-Host')
    $selected = @{}
    $pending = New-Object 'System.Collections.Generic.Queue[string]'
    $pending.Enqueue('Save-Config')
    while ($pending.Count) {
        $name = $pending.Dequeue()
        if ($selected.ContainsKey($name) -or $external -contains $name) { continue }
        if (-not $definitions.ContainsKey($name)) { throw "Missing production helper: $name" }
        if (@($definitions[$name]).Count -ne 1) { throw "Ambiguous production helper: $name" }
        $node = $definitions[$name][0]; $selected[$name] = $node
        foreach ($command in $node.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
            $called = $command.GetCommandName()
            if ($called -and $definitions.ContainsKey($called) -and $external -notcontains $called) { $pending.Enqueue($called) }
        }
    }
    $functionPath = Join-Path $TestDrive 'issue-339-functions.ps1'
    ($selected.Values | Sort-Object { $_.Extent.StartOffset } | ForEach-Object { $_.Extent.Text }) -join "

" | Set-Content -LiteralPath $functionPath -Encoding UTF8
    . $functionPath
    function Write-Log { param([string]$Message) [void]$script:messages.Add($Message) }
    function Write-TpmCompactExtractionProgress { param([Parameter(ValueFromRemainingArguments=$true)]$Arguments) }
    $script:messages = New-Object 'System.Collections.Generic.List[string]'
}

Describe 'RC8 issue #339: saved HealthCheck survives interactive saves and fresh selection' -Tag 'RC8-Issue' {
    BeforeEach {
        $script:configPath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.json')
        $script:tpRoot = $TestDrive
        $script:gamesInstallFolder = $TestDrive
        $script:unattendedModeSaved = $null
        $script:messages.Clear()
    }
    It 'Regression successive saved-config round trips and fresh bounded HealthCheck selection, invalid modes reject, interactive save does not erase supported automation.' {
        # Start from a real saved document, then perform two independent reload/save cycles.
        [System.IO.File]::WriteAllText($script:configPath, '{"TeknoParrotRoot":"fixture","UnattendedMode":"HealthCheck"}')
        foreach ($round in 1..2) {
            $loaded = [System.IO.File]::ReadAllText($script:configPath) | ConvertFrom-Json
            $script:unattendedModeSaved = [string]$loaded.UnattendedMode
            Save-Config | Should -BeTrue
            $loaded = [System.IO.File]::ReadAllText($script:configPath) | ConvertFrom-Json
            $loaded.UnattendedMode | Should -BeExactly 'HealthCheck'
        }
    }
    It 'Regression successive saved-config round trips and fresh bounded HealthCheck selection, invalid modes reject, interactive save does not erase supported automation. (structural selector)' {
        # No function seam exists for startup selection. Inspect the actual
        # guarded allowlist and assignment; do not execute top-level startup.
        $selectors = @($script:issueAst.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.IfStatementAst] -and
            $n.Clauses[0].Item1.Extent.Text -match '^\$Unattended -and \$cfgUnattendedModePropForSelect'
        }, $true))
        $selectors.Count | Should -Be 1
        $selector = $selectors[0]
        $allowlists = @($selector.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $n.Left.Extent.Text -eq '$validUnattendedModes'
        }, $true))
        $allowlists.Count | Should -Be 1
        $values = @($allowlists[0].Right.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.StringConstantExpressionAst]
        }, $true) | ForEach-Object { $_.Value })
        $values.Count | Should -Be 1
        $values[0] | Should -BeExactly 'HealthCheck'
        $modeGuards = @($selector.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.IfStatementAst] -and
            $n.Clauses[0].Item1.Extent.Text -eq '$validUnattendedModes -contains $requestedUnattendedMode'
        }, $true))
        $modeGuards.Count | Should -Be 1
        $assignments = @($modeGuards[0].Clauses[0].Item2.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $n.Left.Extent.Text -eq '$pendingApplyMode'
        }, $true))
        $assignments.Count | Should -Be 1
        $assignments[0].Right.Extent.Text | Should -BeExactly '$requestedUnattendedMode'
        @($selector.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $n.Left.Extent.Text -eq '$pendingApplyMode'
        }, $true)).Count | Should -Be 1
    }
    It 'Saving settings must retain an existing supported unattended HealthCheck selector. (absent-selector negative control)' {
        Save-Config | Should -BeTrue
        $loaded = [System.IO.File]::ReadAllText($script:configPath) | ConvertFrom-Json
        @($loaded.PSObject.Properties.Name) | Should -Not -Contain 'UnattendedMode'
    }
}
