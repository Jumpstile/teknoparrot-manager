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
# $TestDrive. Deterministic: the update boundary is a test-only seam and
# Read-Host is mocked with a fixed scripted answer, never live input or a real
# release.
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
    $functionSource = ($functionAsts | ForEach-Object {
        $source = $_.Extent.Text
        # These two decision functions are the only VBT paths under test that
        # reach the update boundary.  Give them unique test-only calls in the
        # extracted source so another Pester file's mock table cannot divert
        # them to the live GitHub cmdlet in a full multi-file run.
        if ($_.Name -in @('Invoke-CheckForUpdates', 'Invoke-StartupUpdateCheck')) {
            $source = $source.Replace('Get-ManagerUpdateRelease', 'Get-VbtUpdateRelease')
            $source = $source.Replace('Get-ManagerUpdateReleaseSummary', 'Get-VbtUpdateReleaseSummary')
            $source = $source.Replace('Invoke-ManagerUpdateInstall', 'Invoke-VbtUpdateInstall')
        }
        $source
    }) -join "`n`n"
    $originalInstallerAst = $functionAsts | Where-Object Name -eq 'Invoke-ManagerUpdateInstall' | Select-Object -First 1
    if (-not $originalInstallerAst) {
        throw 'Could not locate Invoke-ManagerUpdateInstall for the VBT read-only control path.'
    }
    $originalInstallerSource = $originalInstallerAst.Extent.Text.Replace('function Invoke-ManagerUpdateInstall', 'function Invoke-VbtOriginalManagerUpdateInstall')
    $functionSource += "`n`n" + $originalInstallerSource

    # Update tests invoke functions defined in the extracted file.  A Pester
    # Mock declared in the surrounding It/BeforeEach scope is not a reliable
    # interception point for that separate execution scope, and a missed
    # interception falls through to the real GitHub request. Install unique,
    # deliberately test-only seams in the extracted scope instead. Production
    # functions and their live fallback behavior are not changed.
    $updateBoundarySource = @'
$script:vbtUpdateWebResponse = $null
$script:vbtUpdateInstallResult = $null
$script:vbtUpdateInstallCalls = 0

function Set-VbtUpdateWebResponse {
    param([Parameter(Mandatory)][object]$Response)
    $script:vbtUpdateWebResponse = $Response
}

function Set-VbtUpdateInstallResult {
    param([bool]$Result)
    $script:vbtUpdateInstallResult = $Result
    $script:vbtUpdateInstallCalls = 0
}

function Get-VbtUpdateInstallCallCount {
    return $script:vbtUpdateInstallCalls
}

function Get-VbtUpdateReleaseSummary {
    param([string]$Body)
    return Get-ManagerUpdateReleaseSummary -Body $Body
}

function Get-VbtUpdateRelease {
    param(
        [int]$MaxAttempts = 3,
        [int]$TimeoutSec = 20
    )
    if ($null -eq $script:vbtUpdateWebResponse) {
        throw 'VBT update release seam was not configured.'
    }
    $payload = $script:vbtUpdateWebResponse.Content | ConvertFrom-Json
    $asset = @($payload.assets | Where-Object { $_.name -match '^TeknoParrot\.Manager\.v.*\.zip$' }) | Select-Object -First 1
    if (-not $asset) {
        return $null
    }
    $releaseName = if ($payload.PSObject.Properties.Name -contains 'name') { $payload.name } else { $null }
    $releaseBody = if ($payload.PSObject.Properties.Name -contains 'body') { $payload.body } else { $null }
    $sizeBytes = if ($asset.PSObject.Properties.Name -contains 'size' -and $null -ne $asset.size) { [int64]$asset.size } else { [int64]0 }
    return [pscustomobject]@{
        TagName     = $payload.tag_name
        Name        = $releaseName
        Body        = $releaseBody
        AssetName   = $asset.name
        DownloadUrl = $asset.browser_download_url
        SizeBytes   = $sizeBytes
    }
}

function Invoke-VbtUpdateInstall {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][pscustomobject]$Release
    )
    if ($null -eq $script:vbtUpdateInstallResult) {
        return Invoke-VbtOriginalManagerUpdateInstall -ScriptPath $ScriptPath -Release $Release
    }
    $script:vbtUpdateInstallCalls++
    return $script:vbtUpdateInstallResult
}
'@
    Set-Content -LiteralPath $extractedFunctionsPath -Value ($functionSource + "`n`n" + $updateBoundarySource) -Encoding utf8
    . $extractedFunctionsPath

    # Top-level script-scope values the extracted functions read directly
    # (not captured by function-body extraction) -- mirrors production.
    # $DisplayVersion in particular backs Get-ManagerDisplayVersion, which
    # the main menu's banner (Get-ManagerVersionLine -> Show-MainMenu) reads
    # unqualified; without it here, the main-menu Describe below fails with
    # "$DisplayVersion cannot be retrieved" the moment the menu renders.
    $ScriptVersion = "1.0"
    $ReleaseCandidateLabel = "RC5"
    $DisplayVersion = "v$ScriptVersion $ReleaseCandidateLabel"
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
        param([string]$TagName = 'v1.1', [string]$AssetName = 'TeknoParrot.Manager.v1.1.zip')
        return (@{
            tag_name = $TagName
            name     = $TagName
            body     = 'Test release notes.'
            assets   = @(@{
                name                  = $AssetName
                browser_download_url = "https://github.com/Jumpstile/teknoparrot-manager/releases/download/$TagName/$AssetName"
                size                  = 1
            })
        } | ConvertTo-Json -Depth 5)
    }
}

Describe "Virtual Beta Tester: human workflow simulation (issue #88 phase 1)" {

    It "startup-calm-current-version: reports already current, no error/warning noise" {
        Set-VbtUpdateWebResponse -Response ([pscustomobject]@{ Content = (New-UpdateCheckReleaseJson -TagName $ScriptVersion) })
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
        Set-VbtUpdateWebResponse -Response ([pscustomobject]@{ Content = (New-UpdateCheckReleaseJson) })
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
        Set-VbtUpdateWebResponse -Response ([pscustomobject]@{ Content = (New-UpdateCheckReleaseJson) })
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
        Set-VbtUpdateWebResponse -Response ([pscustomobject]@{ Content = (New-UpdateCheckReleaseJson) })
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
        # "Show-MainMenu" call unique to that block (issue #104 -- the menu
        # display itself moved into a data-driven function, so the literal
        # "Library Management" header text this marker used to look for no
        # longer appears inline here at all; it lives in Get-MainMenuSections
        # now) (not by line number, which drifts). Wrapped in this test's own
        # while loop so break/continue inside the extracted switch behave
        # exactly as they do in production (both governed by an enclosing
        # while loop) -- dot-sourced from a real temp file, never
        # [scriptblock]::Create(), same as above.
        $ifStatementAsts = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.IfStatementAst] }, $true)
        $menuIfAst = $ifStatementAsts | Where-Object { $_.Extent.Text -like '*Show-MainMenu*' } | Select-Object -First 1
        if (-not $menuIfAst) {
            throw "Could not locate the main menu's if/else block in TeknoParrot-Manager.ps1 (looked for an if-statement containing 'Show-MainMenu'). The menu structure may have changed -- update this test's extraction marker to match."
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
# Issue #136: the main menu's actual input path is Read-MainMenuChoiceResponsive
# (issue #104's responsive menu), not Read-Host directly -- it only falls back
# to Read-Host when [Console]::IsInputRedirected is true. A real interactive
# console (exactly what a double-clicked certification .bat has) takes its
# other branch instead: a raw [Console]::KeyAvailable/ReadKey polling loop
# waiting for an actual keystroke that never comes under automated
# certification, hanging forever. This harness's Read-Host fake above never
# intercepted that branch at all, so a certification run always hung here
# once the responsive-menu code shipped, even though this same test suite
# passed cleanly on any machine whose console happened to be redirected
# (confirmed by direct reproduction -- see LESSONS_LEARNED.md). Faking
# Read-MainMenuChoiceResponsive locally in this harness script, same
# nearest-scope-wins pattern as the Read-Host fake above, makes the answer
# queue drive the real input path instead of a coincidental fallback.
function Read-MainMenuChoiceResponsive {
    param([string]`$Prompt, [int]`$InitialWidth, [int]`$InitialHeight)
    if (`$script:answerIndex -ge `$AnswerQueue.Count) {
        throw "Main menu harness ran out of scripted answers (asked for answer #`$(`$script:answerIndex + 1), only `$(`$AnswerQueue.Count) provided)."
    }
    `$answer = `$AnswerQueue[`$script:answerIndex]
    `$script:answerIndex++
    return [pscustomobject]@{ Redraw = `$false; Value = `$answer }
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

    It "recovers from several consecutive invalid choices before a valid one succeeds" {
        # Phase 1.5 priority 1: "repeated invalid choices before success" -- a
        # real tester fat-fingering the prompt more than once, not just a
        # single typo. Replaces the assumption that recovery only needs to
        # work on the FIRST retry.
        $captured = Invoke-MainMenuHarness -AnswerQueue @('abc', '99', '-1', '2') 6>&1
        $text = ($captured | ForEach-Object { $_.ToString() }) -join "`n"
        (@(([regex]::Matches($text, 'Invalid choice')) | ForEach-Object { $_ }).Count) | Should -Be 3 -Because "three invalid answers were given before the valid one, so the recovery message must appear exactly three times, not stop early or loop forever"
        $text.Contains('Exception') | Should -Be $false
    }

    It "issue #136: the harness fakes Read-MainMenuChoiceResponsive, not just Read-Host" {
        # Regression guard for the actual root cause of the certification
        # hang: the real menu reads input via Read-MainMenuChoiceResponsive
        # (issue #104's responsive menu), which only falls back to Read-Host
        # when the console is redirected. A real interactive console (what a
        # double-clicked certification .bat has) takes the other branch --
        # a raw Console.KeyAvailable/ReadKey poll -- which the Read-Host fake
        # alone never intercepted, hanging forever waiting for a keystroke.
        # If this fake is ever removed (e.g. during a future refactor of this
        # harness), the four tests above would silently start relying on the
        # real function again -- this fails fast with a clear message instead
        # of a multi-hour CI/certification hang.
        $harnessSource = Get-Content -LiteralPath $menuHarnessPath -Raw
        $harnessSource | Should -Match 'function\s+Read-MainMenuChoiceResponsive\s*\{'
        $harnessSource | Should -Match 'Redraw\s*=\s*\$false;\s*Value\s*=\s*\$answer'
    }
}

Describe "Virtual Beta Tester: startup update-check decision paths (issue #88 phase 1.5)" {
    BeforeAll {
        function New-StartupCheckReleaseJson {
            param([string]$Body = "Fixes a thing.")
            return (@{
                tag_name = 'v1.1'
                name     = 'v1.1'
                body     = $Body
                assets   = @(@{
                    name                  = 'TeknoParrot.Manager.v1.1.zip'
                    browser_download_url = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v1.1/TeknoParrot.Manager.v1.1.zip'
                    size                  = 1
                })
            } | ConvertTo-Json -Depth 5)
        }

        # PS 5.1's method-overload resolution for
        # [Queue[string]]::new(@(...)) is unreliable from an array literal --
        # a plain index-based queue avoids it and is equally deterministic.
        function New-ScriptedAnswerQueue {
            param([string[]]$Answers)
            [pscustomobject]@{ Answers = $Answers; Index = 0 }
        }
        function Get-NextScriptedAnswer {
            param($Queue)
            if ($Queue.Index -ge $Queue.Answers.Count) {
                throw "Scripted answer queue exhausted after $($Queue.Index) answers."
            }
            $value = $Queue.Answers[$Queue.Index]
            $Queue.Index++
            return $value
        }
    }

    BeforeEach {
        Set-VbtUpdateWebResponse -Response ([pscustomobject]@{ Content = (New-StartupCheckReleaseJson) })
        # Behavioral invariant, not wording: the ONLY signal that a destructive
        # install started is this function being called. The seam is installed
        # in the extracted execution scope, while the destructive installer
        # itself remains covered by Tests/TpmAutoUpdate.DestructivePath.Tests.ps1.
        Set-VbtUpdateInstallResult -Result $true
    }

    It "View notes, then decline: notes are shown and no install is ever attempted" {
        $answers = New-ScriptedAnswerQueue -Answers @('V', 'N')
        Mock Read-Host { Get-NextScriptedAnswer -Queue $answers }

        $fixturePath = Join-Path $TestDrive 'startup-view-decline.ps1'
        Set-Content -LiteralPath $fixturePath -Value '$ScriptVersion = "0.0.1"' -Encoding ascii

        $captured = & { Invoke-StartupUpdateCheck -ScriptPath $fixturePath | Out-Null } 6>&1
        $text = ($captured | ForEach-Object { $_.ToString() }) -join "`n"

        $text.Contains('Fixes a thing.') | Should -Be $true -Because "choosing V must actually show the release notes body"
        Get-VbtUpdateInstallCallCount | Should -Be 0 -Because "declining after viewing notes must never reach the install step -- confirmation required before any destructive action"
    }

    It "Accept, then confirm: reaches the install step exactly once (backup begins there, mocked)" {
        $answers = New-ScriptedAnswerQueue -Answers @('Y', 'Y')
        Mock Read-Host { Get-NextScriptedAnswer -Queue $answers }

        $fixturePath = Join-Path $TestDrive 'startup-accept-confirm.ps1'
        Set-Content -LiteralPath $fixturePath -Value '$ScriptVersion = "0.0.1"' -Encoding ascii

        Invoke-StartupUpdateCheck -ScriptPath $fixturePath | Out-Null
        Get-VbtUpdateInstallCallCount | Should -Be 1 -Because "accepting and confirming must reach the backup-first install step exactly once"
    }

    It "Accept, then decline the second confirmation: no install is attempted (double confirmation required)" {
        $answers = New-ScriptedAnswerQueue -Answers @('Y', 'N')
        Mock Read-Host { Get-NextScriptedAnswer -Queue $answers }

        $fixturePath = Join-Path $TestDrive 'startup-accept-then-decline.ps1'
        Set-Content -LiteralPath $fixturePath -Value '$ScriptVersion = "0.0.1"' -Encoding ascii
        $originalContent = Get-Content -LiteralPath $fixturePath -Raw

        Invoke-StartupUpdateCheck -ScriptPath $fixturePath | Out-Null
        Get-VbtUpdateInstallCallCount | Should -Be 0 -Because "the first Y only offers the update -- a second explicit confirmation is required before anything destructive happens"
        (Get-Content -LiteralPath $fixturePath -Raw) | Should -Be $originalContent
    }

    It "Empty input (pressing Enter) is treated as a safe decline, not an error or a crash" {
        Mock Read-Host { "" }
        $fixturePath = Join-Path $TestDrive 'startup-empty-input.ps1'
        Set-Content -LiteralPath $fixturePath -Value '$ScriptVersion = "0.0.1"' -Encoding ascii

        { Invoke-StartupUpdateCheck -ScriptPath $fixturePath | Out-Null } | Should -Not -Throw
        Get-VbtUpdateInstallCallCount | Should -Be 0 -Because "an unrecognized/empty answer must default to the safe path (remind later), never to an install"
    }

    It "Mixed-case 'y' is accepted the same as 'Y' (case-insensitive yes)" {
        $answers = New-ScriptedAnswerQueue -Answers @('y', 'y')
        Mock Read-Host { Get-NextScriptedAnswer -Queue $answers }
        $fixturePath = Join-Path $TestDrive 'startup-lowercase-yes.ps1'
        Set-Content -LiteralPath $fixturePath -Value '$ScriptVersion = "0.0.1"' -Encoding ascii

        Invoke-StartupUpdateCheck -ScriptPath $fixturePath | Out-Null
        Get-VbtUpdateInstallCallCount | Should -Be 1 -Because "a human typing lowercase y expects the same result as uppercase Y"
    }

    It "Whitespace-padded input ('  Y  ') is trimmed and accepted" {
        $answers = New-ScriptedAnswerQueue -Answers @('  Y  ', '  Y  ')
        Mock Read-Host { Get-NextScriptedAnswer -Queue $answers }
        $fixturePath = Join-Path $TestDrive 'startup-padded-yes.ps1'
        Set-Content -LiteralPath $fixturePath -Value '$ScriptVersion = "0.0.1"' -Encoding ascii

        Invoke-StartupUpdateCheck -ScriptPath $fixturePath | Out-Null
        Get-VbtUpdateInstallCallCount | Should -Be 1 -Because "a human's stray leading/trailing space when typing Y must not be treated as an invalid answer"
    }

    It "Repeated 'view notes' answers before declining never gets stuck or attempts an install" {
        $answers = New-ScriptedAnswerQueue -Answers @('V', 'V', 'V', 'N')
        Mock Read-Host { Get-NextScriptedAnswer -Queue $answers }
        $fixturePath = Join-Path $TestDrive 'startup-repeated-view.ps1'
        Set-Content -LiteralPath $fixturePath -Value '$ScriptVersion = "0.0.1"' -Encoding ascii

        { Invoke-StartupUpdateCheck -ScriptPath $fixturePath | Out-Null } | Should -Not -Throw
        Get-VbtUpdateInstallCallCount | Should -Be 0
    }
}
