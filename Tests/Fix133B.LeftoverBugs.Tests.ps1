#Requires -Module Pester

# FIX133B: real user-breaking bugs from the independent review that were left open by FIX133.
#   Each It names the product mutation that makes it fail and the user who is hurt.

BeforeAll {
    $script:F133BProductionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $script:F133BSource = [System.IO.File]::ReadAllText($script:F133BProductionPath)
    $script:F133BLines = $script:F133BSource -split "`r?`n"
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($script:F133BSource, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX133B tests could not parse the production script.' }
    $script:F133BAst = $ast
    $wanted = @('Get-TpmUserProfilesBackupInfo', 'Get-TpmSavedCopyKindText', 'Format-TpmFriendlyTime', 'Get-TpmActionRequiredPlainLines')
    $definitions = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $wanted -contains $args[0].Name }, $true))
    $functionFile = Join-Path $TestDrive 'tpm-fix133b-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, (@($definitions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"), (New-Object System.Text.UTF8Encoding $false))
    . $functionFile
}

Describe 'FIX133B backup names: one clock (UTC) and a kind for AutoSync copies' {
    # Who gets hurt: a user choosing a copy in the Restore menu. A local-time name read as UTC puts the copy in the wrong place
    # in the "newest first" list, and a name with no kind has no readable time at all (it sorts last).
    It 'reads an AutoSync copy name as kind AutoSync with a UTC time' {
        # Mutation: remove the AutoSync_ prefix from the AutoSync backup name or the AutoSync entry from Get-TpmSavedCopyKindText.
        $info = Get-TpmUserProfilesBackupInfo -Name 'AutoSync_2026-11-05_10-30-15_123_a1b2c3d4'
        $info.WhenUtc.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ', [System.Globalization.CultureInfo]::InvariantCulture) | Should -BeExactly '2026-11-05T10:30:15.123Z'
        $info.Text | Should -BeLike 'Before syncing games, *'
    }

    It 'reads a force feedback switch copy name with its time, so it sorts by date and has a plain name' {
        $info = Get-TpmUserProfilesBackupInfo -Name 'FFBOverlapSwitch_2026-11-05_10-30-15_123_0123456789abcdef0123456789abcdef'
        $info.WhenUtc | Should -Not -BeNullOrEmpty
        $info.Text | Should -BeLike 'Before the force feedback switch, *'
    }

    It 'writes every UserProfiles backup name in UTC' -ForEach @(
        @{ Prefix = "'AutoSync_" }, @{ Prefix = "'FFBOverlapSwitch_" }, @{ Prefix = "'FFBPluginCleanup_" }
    ) {
        # Mutation: take ToUniversalTime() out of the timestamp that feeds the backup name (the parser reads every name as UTC).
        $lines = $script:F133BLines
        $at = @(0..($lines.Count - 1) | Where-Object { $lines[$_].Contains($Prefix) -and $lines[$_] -match 'Join-Path' })
        $at.Count | Should -Be 1
        $nearby = ($lines[([Math]::Max(0, $at[0] - 6))..$at[0]] -join "`n")
        $nearby | Should -Match "\(Get-Date\)\.ToUniversalTime\(\)\.ToString\('yyyy-MM-dd_HH-mm-ss(_fff)?'|\(Get-Date\)\.ToUniversalTime\(\)\.ToString\(""yyyy-MM-dd_HH-mm-ss_fff"""
        $nearby | Should -Match 'InvariantCulture'
    }
}

Describe 'FIX133B config.json and the overrides file are read as UTF-8' {
    # Who gets hurt: a user whose saved folder (or game) name has a letter outside plain ASCII. The files are written as UTF-8
    #   without a byte-order mark; Windows PowerShell 5.1 reads such a file as ANSI unless told otherwise, so the path comes back
    #   garbled and the startup root check fails or a wrong folder is saved again.
    It 'reads the exact product statement for <Name> back unchanged' -ForEach @(
        @{ Name = 'config.json'; Variable = '$configPath'; Target = '$cfg' },
        @{ Name = 'the overrides file'; Variable = '$overridesPath'; Target = '$ov' }
    ) {
        # Mutation: remove -Encoding UTF8 from that Get-Content in the product (fails on Windows PowerShell 5.1).
        $statement = @($script:F133BLines | Where-Object { $_.Trim().StartsWith($Target + ' = Get-Content -LiteralPath ' + $Variable + ' -Raw') })
        $statement.Count | Should -Be 1
        $expression = $statement[0].Trim().Substring($Target.Length + 3)
        $special = 'C:\Games\' + [char]0x00E9 + [char]0x4E2D + [char]0x00DF + '%#'
        $file = Join-Path $TestDrive ('f133b-' + [guid]::NewGuid().ToString('N') + '.json')
        [System.IO.File]::WriteAllText($file, (([ordered]@{ TeknoParrotRoot = $special } | ConvertTo-Json)), (New-Object System.Text.UTF8Encoding $false))
        Set-Variable -Name ($Variable.TrimStart('$')) -Value $file
        $read = Invoke-Expression $expression
        [string]$read.TeknoParrotRoot | Should -BeExactly $special
    }

    It 'reads every sync-state and manifest JSON as UTF-8' {
        # Mutation: remove -Encoding UTF8 from a Get-Content that reads the AutoSync sync-state or the ReShade/FFB manifests.
        $bad = @($script:F133BLines | Where-Object { $_ -match 'Get-Content -LiteralPath \$(stateFull|candidatePath|configPath|overridesPath|StatePath|crosshairStatePath) -Raw' -and $_ -notmatch '-Encoding UTF8' })
        $bad | Should -BeNullOrEmpty
    }
}

Describe 'FIX133B a Preview run does not overwrite the saved Action Items report' {
    # Who gets hurt: a user who runs Preview after a real run and loses the saved to-do list (and the game notes file) of that real run.
    It 'writes the action report and the game notes only outside Preview' {
        # Mutation: remove the "if (-not $dryRunActive)" around either the Write-TpmActionRequiredReports call or the Write-TpmGameNotesReport call.
        $calls = @($script:F133BAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -in @('Write-TpmActionRequiredReports', 'Write-TpmGameNotesReport')
        }, $true) | Where-Object {
            $parent = $_.Parent
            while ($null -ne $parent -and $parent -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { $parent = $parent.Parent }
            $null -eq $parent
        })
        $calls.Count | Should -Be 2
        foreach ($call in $calls) {
            $guarded = $false
            $parent = $call.Parent
            while ($null -ne $parent) {
                if ($parent -is [System.Management.Automation.Language.IfStatementAst]) {
                    foreach ($clause in $parent.Clauses) {
                        if ($clause.Item1.Extent.Text -match '^\s*-not\s+\$dryRunActive\s*$' -and $clause.Item2.Extent.StartOffset -le $call.Extent.StartOffset -and $clause.Item2.Extent.EndOffset -ge $call.Extent.EndOffset) { $guarded = $true }
                    }
                }
                $parent = $parent.Parent
            }
            $guarded | Should -BeTrue
        }
    }

    It 'tells the user in plain words that a Preview did not save the list' {
        # Mutation: keep "The list is saved as a text file" on the Preview screen.
        $lines = @(Get-TpmActionRequiredPlainLines -For Screen -SavePath 'C:\Reports\ActionItems.txt' -Preview) -join ' '
        $lines | Should -Match 'only a preview'
        $lines | Should -Not -Match 'is saved as a text file'
        (@(Get-TpmActionRequiredPlainLines -For Screen -SavePath 'C:\Reports\ActionItems.txt') -join ' ') | Should -Match 'is saved as a text file.*ActionItems\.txt'
    }

    It 'does not promise a saved list when the last item may be cleared before the end' {
        # Who gets hurt: a user whose only item (missing firmware) was fixed on the screen was told the list is saved, then told no list was saved.
        # Mutation: restore "The list is saved as a text file" on the Screen block.
        $screen = @(Get-TpmActionRequiredPlainLines -For Screen -SavePath 'C:\Reports\ActionItems.txt') -join ' '
        $screen | Should -Match 'If anything is left on this list at the end, it is saved as a text file.*ActionItems\.txt'
        $screen | Should -Not -Match 'The list is saved'
    }
}

Describe 'FIX133B a blank ZIP-folder answer returns to the menu' {
    # Who gets hurt: a user who presses Enter at "Game ZIP folder". A blank answer was saved and then crashed AutoSync with
    #   "FATAL ERROR -- script aborted" (Test-Path -LiteralPath '' throws).
    It 'checks every ZIP-folder answer for blank before using it' {
        # Mutation: remove the IsNullOrWhiteSpace check (or its "continue") after any Read-PathWithBrowse for the ZIP folder.
        # Found in the syntax tree, so it does not depend on line numbers or on how many ZIP-folder prompts the product has.
        $answers = @($script:F133BAst.FindAll({
            $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $args[0].Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $args[0].Left.VariablePath.UserPath -match '^(zipSource|newZipSource)$' -and
            $args[0].Right.Extent.Text -match '^Read-PathWithBrowse\b'
        }, $true))
        $answers.Count | Should -BeGreaterThan 0
        foreach ($answer in $answers) {
            $statements = @($answer.Parent.Statements)
            $next = $statements[[array]::IndexOf($statements, $answer) + 1]
            $next | Should -BeOfType ([System.Management.Automation.Language.IfStatementAst])
            $next.Clauses[0].Item1.Extent.Text | Should -Match ('^\[string\]::IsNullOrWhiteSpace\(\$' + [regex]::Escape($answer.Left.VariablePath.UserPath) + '\)$')
            $next.Clauses[0].Item2.Extent.Text | Should -Match '\bcontinue\b'
        }
    }
}
