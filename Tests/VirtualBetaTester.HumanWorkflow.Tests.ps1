#Requires -Module Pester

# TPM Certification Suite Phase 1 (issue #88): wires the 5 scenarios in
# testdata/human-use-scenarios.json to real TPM behavior instead of only
# validating the dataset's own structure (that structural check lives in
# Tests/HumanUseSimulation.Tests.ps1 and stays separate). Each scenario here
# drives an actual function from TeknoParrot-Manager.ps1 with scripted
# Read-Host answers and mocked network calls, captures real console output,
# and asserts the required/forbidden phrases from the shared dataset -- the
# same dataset a human tester's checklist would be built from.
#
# No network access, no GUI, no real TeknoParrot install, no writes outside
# $TestDrive. Deterministic: every external call (Invoke-WebRequest, Read-Host)
# is mocked with a fixed scripted answer, never live input or a real release.
#
# Run with: Invoke-Pester -Path .\Tests\VirtualBetaTester.HumanWorkflow.Tests.ps1

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "..\TeknoParrot-Manager.ps1"
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Failed to parse TeknoParrot-Manager.ps1: $($parseErrors -join '; ')"
    }

    # Dot-source via a real temp file, not ". ([scriptblock]::Create($text))" --
    # see LESSONS_LEARNED.md ("TPM Certification Suite (commit bb2a160)") for
    # why: a runtime-constructed scriptblock's dot-sourcing broke a different
    # test file's module-scoped Pester mock when both ran in the same
    # invocation. Function extraction always goes through a temp file here,
    # never [scriptblock]::Create(), even though this file doesn't touch the
    # specific module-mocked file that originally reproduced the bug -- the
    # safe pattern is the standing rule, not a case-by-case judgment call.
    $functionAsts = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $extractedFunctionsPath = Join-Path $TestDrive ("vbt-human-workflow-functions-" + [guid]::NewGuid().ToString('N') + '.ps1')
    ($functionAsts | ForEach-Object { $_.Extent.Text }) -join "`n`n" | Set-Content -LiteralPath $extractedFunctionsPath -Encoding utf8
    . $extractedFunctionsPath

    # Top-level script-scope values the extracted functions read directly
    # (not captured by function-body extraction) -- mirrors production.
    $ScriptVersion = "0.99.45"
    $script:logPath = Join-Path $TestDrive "vbt-human-workflow.log"

    # Shared scenario dataset -- the same file a certification run and a
    # human tester's checklist both draw from. This test proves each
    # scenario's expectations hold against real function output; it does not
    # re-validate the dataset's own structure (Tests/HumanUseSimulation.Tests.ps1
    # already does that).
    $scenarioPath = Join-Path $PSScriptRoot "..\testdata\human-use-scenarios.json"
    $script:scenarios = Get-Content -LiteralPath $scenarioPath -Raw | ConvertFrom-Json
    function Get-Scenario {
        param([Parameter(Mandatory)][string]$Id)
        $found = $script:scenarios | Where-Object { $_.id -eq $Id }
        if (-not $found) { throw "Scenario '$Id' not found in testdata/human-use-scenarios.json" }
        return $found
    }

    # Captures real Write-Host output (the Information stream, 6) from a
    # scriptblock and asserts it against a scenario's required/forbidden
    # phrases -- case-sensitive, matching the dataset's own casing exactly
    # (e.g. "ERROR"/"WARNING" vs "failed" are deliberately different cases).
    function Assert-ScenarioOutput {
        param(
            [Parameter(Mandatory)][string]$ScenarioId,
            [Parameter(Mandatory)][scriptblock]$Action
        )
        $scenario = Get-Scenario -Id $ScenarioId
        $captured = & $Action 6>&1
        $text = ($captured | ForEach-Object { $_.ToString() }) -join "`n"

        foreach ($required in @($scenario.requiredPhrases)) {
            $text.Contains($required) | Should -Be $true -Because "scenario '$ScenarioId' requires output to contain: $required`n--- actual output ---`n$text"
        }
        foreach ($forbidden in @($scenario.forbiddenPhrases)) {
            $text.Contains($forbidden) | Should -Be $false -Because "scenario '$ScenarioId' forbids output from containing: $forbidden`n--- actual output ---`n$text"
        }
        return $text
    }

    function New-UpdateCheckReleaseJson {
        param([string]$TagName = 'v0.99.99', [string]$AssetName = 'TeknoParrot.Manager.v0.99.99.BETA.zip')
        return (@{
            tag_name = $TagName
            assets   = @(@{
                name                  = $AssetName
                browser_download_url = "https://github.com/Jumpstile/teknoparrot-manager/releases/download/$TagName/$AssetName"
            })
        } | ConvertTo-Json -Depth 5)
    }
}

Describe "Virtual Beta Tester: human workflow simulation (issue #88 phase 1)" {

    It "startup-calm-current-version: reports already current, no error/warning noise" {
        Mock Invoke-WebRequest { [pscustomobject]@{ Content = (New-UpdateCheckReleaseJson -TagName $ScriptVersion) } }
        Mock Read-Host { throw "Read-Host should not be called when already current" }

        $fixturePath = Join-Path $TestDrive 'startup-calm.ps1'
        Set-Content -LiteralPath $fixturePath -Value "`$ScriptVersion = `"$ScriptVersion`"" -Encoding ascii

        $before = Get-ChildItem -LiteralPath $TestDrive -Recurse | Select-Object -ExpandProperty FullName | Sort-Object

        Assert-ScenarioOutput -ScenarioId 'startup-calm-current-version' -Action {
            Invoke-CheckForUpdates -ScriptPath $fixturePath | Out-Null
        }

        $after = Get-ChildItem -LiteralPath $TestDrive -Recurse | Select-Object -ExpandProperty FullName | Sort-Object
        # expectedStateChange: false in the scenario dataset -- assert it for real,
        # not just record the field. Log file writes are expected (Write-Log always
        # appends); everything else under $TestDrive must be unchanged.
        $unexpectedChanges = Compare-Object $before $after | Where-Object { $_.InputObject -notlike '*vbt-human-workflow.log' }
        $unexpectedChanges | Should -BeNullOrEmpty -Because "scenario declares expectedStateChange: false"
    }

    It "update-available-explains-safety: explains what an update will do before asking" {
        Mock Invoke-WebRequest { [pscustomobject]@{ Content = (New-UpdateCheckReleaseJson) } }
        Mock Read-Host { "N" }

        $fixturePath = Join-Path $TestDrive 'update-offer.ps1'
        Set-Content -LiteralPath $fixturePath -Value '$ScriptVersion = "0.0.1"' -Encoding ascii
        $originalContent = Get-Content -LiteralPath $fixturePath -Raw

        Assert-ScenarioOutput -ScenarioId 'update-available-explains-safety' -Action {
            Invoke-CheckForUpdates -ScriptPath $fixturePath | Out-Null
        }

        (Get-Content -LiteralPath $fixturePath -Raw) | Should -Be $originalContent
    }

    It "read-only-update-failure-actionable: read-only failure tells the user how to recover" {
        Mock Invoke-WebRequest { [pscustomobject]@{ Content = (New-UpdateCheckReleaseJson) } }
        Mock Read-Host { "Y" }

        $root = Join-Path $TestDrive ("readonly-scenario-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $fixturePath = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $fixturePath -Value '$ScriptVersion = "0.0.1"' -Encoding ascii
        Set-ItemProperty -LiteralPath $fixturePath -Name IsReadOnly -Value $true

        try {
            Assert-ScenarioOutput -ScenarioId 'read-only-update-failure-actionable' -Action {
                Invoke-CheckForUpdates -ScriptPath $fixturePath | Out-Null
            }
            Test-Path -LiteralPath (Join-Path $root 'UpdateBackups') | Should -BeFalse -Because "a read-only target must fail before any backup is attempted"
        } finally {
            Set-ItemProperty -LiteralPath $fixturePath -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
        }
    }

    It "cancel-path-no-change: declining leaves files unchanged and says so, without destructive-action language" {
        Mock Invoke-WebRequest { [pscustomobject]@{ Content = (New-UpdateCheckReleaseJson) } }
        Mock Read-Host { "N" }

        $fixturePath = Join-Path $TestDrive 'cancel-path.ps1'
        Set-Content -LiteralPath $fixturePath -Value '$ScriptVersion = "0.0.1"' -Encoding ascii
        $originalContent = Get-Content -LiteralPath $fixturePath -Raw

        Assert-ScenarioOutput -ScenarioId 'cancel-path-no-change' -Action {
            Invoke-CheckForUpdates -ScriptPath $fixturePath | Out-Null
        }

        (Get-Content -LiteralPath $fixturePath -Raw) | Should -Be $originalContent
    }
}

Describe "Virtual Beta Tester: main menu recovers from invalid input (issue #88 phase 1)" {
    BeforeAll {
        # The main menu is top-level executable code (a "while ($true) { ... }"
        # spanning most of the script, mixing menu display with mode dispatch),
        # not a function -- FunctionDefinitionAst extraction above never touches
        # it. Extract only the bounded if/else statement that prints the menu,
        # reads one choice, and validates it, identified structurally via the
        # "Library Management" header text unique to that block (not by line
        # number, which drifts). Wrapped in this test's own while loop so
        # break/continue inside the extracted switch behave exactly as they do
        # in production (both governed by an enclosing while loop) -- dot-sourced
        # from a real temp file, never [scriptblock]::Create(), same as above.
        $ifStatementAsts = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.IfStatementAst] }, $true)
        $menuIfAst = $ifStatementAsts | Where-Object { $_.Extent.Text -like '*Library Management*' } | Select-Object -First 1
        if (-not $menuIfAst) {
            throw "Could not locate the main menu's if/else block in TeknoParrot-Manager.ps1 (looked for an if-statement containing 'Library Management'). The menu structure may have changed -- update this test's extraction marker to match."
        }

        $menuHarnessPath = Join-Path $TestDrive ("vbt-main-menu-" + [guid]::NewGuid().ToString('N') + '.ps1')
        @"
param([string[]]`$AnswerQueue)
`$script:answerIndex = 0
function Read-Host {
    param([string]`$Prompt)
    if (`$script:answerIndex -ge `$AnswerQueue.Count) {
        throw "Main menu harness ran out of scripted answers (asked for answer #`$(`$script:answerIndex + 1), only `$(`$AnswerQueue.Count) provided)."
    }
    `$answer = `$AnswerQueue[`$script:answerIndex]
    `$script:answerIndex++
    return `$answer
}
`$pendingApplyMode = `$null
`$forceRealApply = `$false
`$Unattended = `$false
`$iterations = 0
while (`$true) {
    `$iterations++
    if (`$iterations -gt 10) { throw "Main menu harness exceeded 10 iterations -- likely an infinite loop, not real menu behavior." }
    `$mode = `$null
$($menuIfAst.Extent.Text)
    if (`$mode) { return `$mode }
}
"@ | Set-Content -LiteralPath $menuHarnessPath -Encoding utf8

        function Invoke-MainMenuHarness {
            param([string[]]$AnswerQueue)
            & $menuHarnessPath -AnswerQueue $AnswerQueue
        }
    }

    It "main-menu-invalid-option-recovers: an invalid choice prints a clear message and the menu asks again" {
        $captured = Invoke-MainMenuHarness -AnswerQueue @('99', '14') 6>&1
        $text = ($captured | ForEach-Object { $_.ToString() }) -join "`n"

        $scenario = Get-Scenario -Id 'main-menu-invalid-option-recovers'
        foreach ($required in @($scenario.requiredPhrases)) {
            $text.Contains($required) | Should -Be $true -Because "scenario 'main-menu-invalid-option-recovers' requires output to contain: $required`n--- actual output ---`n$text"
        }
        foreach ($forbidden in @($scenario.forbiddenPhrases)) {
            $text.Contains($forbidden) | Should -Be $false -Because "scenario 'main-menu-invalid-option-recovers' forbids output from containing: $forbidden`n--- actual output ---`n$text"
        }
    }

    It "recognizes a valid choice and returns the matching mode without ever hitting the invalid path" {
        $captured = Invoke-MainMenuHarness -AnswerQueue @('2') 6>&1
        $text = ($captured | ForEach-Object { $_.ToString() }) -join "`n"
        $text.Contains('Invalid choice') | Should -Be $false
    }

    It "exiting (choice 14) returns without printing an invalid-choice message" {
        $captured = Invoke-MainMenuHarness -AnswerQueue @('14') 6>&1
        $text = ($captured | ForEach-Object { $_.ToString() }) -join "`n"
        $text.Contains('Invalid choice') | Should -Be $false
    }
}
