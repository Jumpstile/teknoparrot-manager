#Requires -Module Pester

# FIX90: start-up must never wait for a new question.
#
#  Item 1  The custom rules notice prints one line and asks nothing; the full list goes to the log.
#  Item 3  The two Details question helpers cannot loop when the input has ended or the answer is empty.
#
# The production script is parsed and only its function definitions are dot-sourced. Nothing here touches a
# real install, the registry or the network. Each It names the product mutation that makes it fail.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $source = [System.IO.File]::ReadAllText($productionPath)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX90 tests could not parse the production script.' }
    $script:F90Ast = $ast
    $definitions = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    $functionFile = Join-Path $TestDrive 'tpm-fix90-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, (@($definitions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"), (New-Object System.Text.UTF8Encoding $false))
    . $functionFile

    $script:F90SomeCounts = [ordered]@{ noSync = 2; onlySync = 0; noPropagate = 1; forceArchetype = 0; familyOverride = 0; canonicalArchetype = 0; subFolderMap = 3 }
    $script:F90NoCounts = [ordered]@{ noSync = 0; onlySync = 0; noPropagate = 0; forceArchetype = 0; familyOverride = 0; canonicalArchetype = 0; subFolderMap = 0 }

    # A console that would answer any question: every way of asking one throws, so a question can never hang a test.
    function Install-F90NoQuestionMocks {
        param([bool]$Interactive = $true)
        $script:F90Screen = New-Object System.Collections.Generic.List[string]
        $script:F90Log = New-Object System.Collections.Generic.List[string]
        $script:F90Interactive = $Interactive
        Mock Write-Host { [void]$script:F90Screen.Add([string]($Object -join ' ')) }
        Mock Write-Log { [void]$script:F90Log.Add([string]$msg) }
        # Wide enough that the 89-character notice stays on one line whatever the harness console width is.
        Mock Get-ConsoleContentWidth { return 120 }
        Mock Test-TpmInteractiveInput { return [bool]$script:F90Interactive }
        Mock Read-HostSafe { throw ("UNEXPECTED QUESTION '{0}'" -f $Prompt) }
        Mock Read-Host { throw ("UNEXPECTED QUESTION '{0}'" -f $Prompt) }
        Mock Read-TpmAnswerWithDetails { throw ("UNEXPECTED QUESTION '{0}'" -f $Prompt) }
        Mock Read-TpmYesNo { throw ("UNEXPECTED QUESTION '{0}'" -f $Prompt) }
        Mock Read-TpmChoice { throw ("UNEXPECTED QUESTION '{0}'" -f $Prompt) }
    }
}

Describe 'FIX90 custom rules notice asks nothing' {
    It 'asks no question of any kind on an interactive console, and still prints its line' {
        # Mutation: ask "[D] Details, or press Enter to continue" again (Read-TpmAnswerWithDetails / Read-HostSafe) -> a start-up that waits for a key.
        Install-F90NoQuestionMocks -Interactive $true
        { Show-TpmOverridesNotice -Counts $script:F90SomeCounts -FilePath 'C:\TPM\TeknoParrot-Manager.overrides.json' } | Should -Not -Throw
        Should -Invoke Read-HostSafe -Times 0 -Exactly
        Should -Invoke Read-Host -Times 0 -Exactly
        Should -Invoke Read-TpmAnswerWithDetails -Times 0 -Exactly
        Should -Invoke Read-TpmYesNo -Times 0 -Exactly
        Should -Invoke Read-TpmChoice -Times 0 -Exactly
        @($script:F90Screen | Where-Object { $_ -match '\S' }) | Should -Be @('  You have custom rules in TeknoParrot-Manager.overrides.json. The full list is in the log.')
    }

    It 'asks no question and prints nothing when the file holds no rules' {
        # Mutation: print the line or ask for a key when every count is zero -> a line or a wait on every start-up.
        Install-F90NoQuestionMocks -Interactive $true
        Show-TpmOverridesNotice -Counts $script:F90NoCounts -FilePath 'C:\TPM\TeknoParrot-Manager.overrides.json'
        Should -Invoke Read-HostSafe -Times 0 -Exactly
        @($script:F90Screen).Count | Should -Be 0
        @($script:F90Log).Count | Should -Be 0
    }

    It 'writes every rule block and the note to the log, so nothing the old Details view showed is lost' {
        # Mutation: drop the Write-TpmDetailBlocksLog call or the note -> the rules are no longer anywhere after start-up.
        Install-F90NoQuestionMocks
        Show-TpmOverridesNotice -Counts $script:F90SomeCounts -FilePath 'C:\TPM\TeknoParrot-Manager.overrides.json'
        $log = $script:F90Log -join "`n"
        $log | Should -Match 'Custom rules \[The file\]: Name: TeknoParrot-Manager\.overrides\.json'
        $log | Should -Match 'Custom rules \[The file\]: Path: C:\\TPM\\TeknoParrot-Manager\.overrides\.json'
        $log | Should -Match 'Custom rules \[Games with their own folder\]: How many: 3'
        $log | Should -Match 'Custom rules \[Games that never get copied controls\]: Setting: noPropagate'
        $log | Should -Match 'Custom rules note: If you did not make this file yourself, there is nothing to do\.'
    }
}

Describe 'FIX90 Details question helpers cannot loop on ended or empty input' {
    BeforeEach {
        $script:F90Asked = 0
        Mock Write-Host { }
        Mock Write-Log { }
        Mock Get-ConsoleContentWidth { return 80 }
    }

    It 'returns an empty answer once when the input has ended (null), instead of asking again' {
        # Mutation: loop until the answer is not empty -> a second question and the UNEXPECTED second call below.
        Mock Read-HostSafe {
            $script:F90Asked++
            if ($script:F90Asked -gt 1) { throw 'ASKED AGAIN' }
            return $null
        }
        $blocks = @(@{ Heading = 'One'; Lines = @('Label: text') })
        (Read-TpmAnswerWithDetails -Prompt 'Question' -DetailBlocks $blocks) | Should -BeExactly ''
        $script:F90Asked | Should -Be 1
    }

    It 'shows the details once per D, then returns the next answer' {
        # Mutation: return after D without showing the details, or without asking again -> the details or the real answer are lost.
        $script:F90Answers = New-Object 'System.Collections.Generic.Queue[string]'
        foreach ($answer in @('d', '')) { [void]$script:F90Answers.Enqueue($answer) }
        Mock Read-HostSafe {
            $script:F90Asked++
            if ($script:F90Answers.Count -eq 0) { throw 'ASKED AGAIN' }
            return $script:F90Answers.Dequeue()
        }
        Mock Show-TpmDetailBlocks { }
        $blocks = @(@{ Heading = 'One'; Lines = @('Label: text') })
        (Read-TpmAnswerWithDetails -Prompt 'Question' -DetailBlocks $blocks) | Should -BeExactly ''
        $script:F90Asked | Should -Be 2
        Should -Invoke Show-TpmDetailBlocks -Times 1 -Exactly
    }

    It 'goes back (-1) after one question when Enter is pressed on a numbered list that has details' {
        # Mutation: remove the default B from the numbered-list question -> Enter is rejected and the question repeats (ASKED AGAIN).
        Mock Read-HostSafe {
            $script:F90Asked++
            if ($script:F90Asked -gt 1) { throw 'ASKED AGAIN' }
            # Like the real Read-HostSafe: an empty line gives the default.
            return $Default
        }
        $blocks = @(@{ Heading = 'One'; Lines = @('Label: text') })
        (Read-TpmNumberedListChoice -Rows @('First game', 'Second game') -Prompt '  Choose a number, or B to go back' -DetailBlocks $blocks) | Should -Be -1
        $script:F90Asked | Should -Be 1
    }
}

Describe 'FIX90 the end of a registration run adds no question of its own' {
    # The registration flow is top-level script code, so it cannot be called. Its result screens are checked by structure,
    # the same way the FIX80 tests check the order of the recap calls.
    # FIX98: the screens now pass the REAL unattended state (-Unattended:$Unattended) and -DeferDetails, so an interactive run still
    # asks nothing in the middle; the details wait for the final return prompt (Read-TpmReturnToMenu).
    It 'passes -DeferDetails and the real unattended state to every top-level Write-TpmOutcome call, so no Details question is added before "Press Enter to return to menu"' {
        # Mutation: drop -DeferDetails from the recap or the next-steps screen -> an extra Enter on every interactive registration run.
        # Mutation: pass a bare -Unattended again -> Details can never be offered in an interactive run.
        $calls = @($script:F90Ast.FindAll({
            param($node)
            if ($node -isnot [System.Management.Automation.Language.CommandAst] -or $node.GetCommandName() -cne 'Write-TpmOutcome') { return $false }
            for ($parent = $node.Parent; $null -ne $parent; $parent = $parent.Parent) {
                if ($parent -is [System.Management.Automation.Language.FunctionDefinitionAst]) { return $false }
            }
            return $true
        }, $true))
        $calls.Count | Should -Be 2
        foreach ($call in $calls) {
            $defer = @($call.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -ceq 'DeferDetails' -and $null -eq $_.Argument })
            $defer.Count | Should -Be 1
            $real = @($call.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -ceq 'Unattended' -and $null -ne $_.Argument -and $_.Argument.Extent.Text -ceq '$Unattended' })
            $real.Count | Should -Be 1
        }
    }

    It 'passes -DeferDetails and the real unattended state to both control propagation results of the registration run (the calls that have -DryRun)' {
        # The registration run has exactly two such calls, in mutually exclusive branches: "no reference profiles, nothing to copy" and
        # "controls were copied". Every other Write-ControlPropagationResults call belongs to the menu and has no -DryRun.
        # Mutation: drop -DeferDetails from either call -> an extra Enter in the middle of every interactive registration run.
        # Mutation: pass a bare -Unattended again -> the control details can never be shown in an interactive run.
        # Mutation: add a third registration call that forgets either parameter -> the count fails.
        $calls = @($script:F90Ast.FindAll({
            param($node)
            if ($node -isnot [System.Management.Automation.Language.CommandAst] -or $node.GetCommandName() -cne 'Write-ControlPropagationResults') { return $false }
            # The menu preview of Propagate Controls (#411) passes a fixed "-DryRun $true" and is a menu screen, not part of the registration run.
            $dry = @($node.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -ceq 'DryRun' })
            return ($dry.Count -eq 1 -and $null -ne $dry[0].Argument -and $dry[0].Argument.Extent.Text -cne '$true')
        }, $true))
        $calls.Count | Should -Be 2
        foreach ($call in $calls) {
            @($call.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -ceq 'DeferDetails' -and $null -eq $_.Argument }).Count | Should -Be 1
            @($call.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -ceq 'Unattended' -and $null -ne $_.Argument -and $_.Argument.Extent.Text -ceq '$Unattended' }).Count | Should -Be 1
        }
    }
}
