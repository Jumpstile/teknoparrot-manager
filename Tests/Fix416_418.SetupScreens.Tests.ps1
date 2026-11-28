Describe 'Setup screens account for every game and offer a way back' {
    BeforeAll {
        $src = Join-Path (Split-Path -Parent $PSScriptRoot) 'TeknoParrot-Manager.ps1'
        $script:SourceText = Get-Content -LiteralPath $src -Raw
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
        $want = @('Get-TpmDgVoodoo2ResultView', 'Get-TpmDgVoodoo2GameOutcomes', 'Get-TpmStepCountsLine', 'Get-TpmBackupFolderLine', 'Get-TpmDriveSkipNext', 'Format-TpmNameList', 'Get-TpmGameTitle', 'Join-TpmPostgresSetupNames', 'Read-TpmOptionalStepChoice', 'Get-TpmOptionalStepName', 'Get-TpmOptionalStepHelpBlocks')
        $funcs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $want -contains $n.Name }, $true)
        foreach ($f in $funcs) { . ([scriptblock]::Create($f.Extent.Text)) }
        function Get-TpmTransactionField { param($Object, $Name, $Default) if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) { return $Object.$Name } return $Default }
        function Format-TpmGameCount { param([int]$Count) if ($Count -eq 1) { '1 game' } else { "$Count games" } }
        function Get-TpmDgVoodoo2DetailBlocks { param($Result) @() }
        function Show-TpmDetailBlocks { param($Blocks) }
        function Write-Host { param([Parameter(ValueFromRemainingArguments)]$a) }
        $script:Answers = New-Object System.Collections.Queue
        function Read-HostSafe { param($p, $Default) return [string]$script:Answers.Dequeue() }
    }

    It 'names the selected game that already had every dgVoodoo2 file' {
        $result = [pscustomobject]@{ DeploymentDetails = @([pscustomobject]@{ Game = 'a' }, [pscustomobject]@{ Game = 'b' }, [pscustomobject]@{ Game = 'c' }); SkipDetails = @(); NoOp = $false; PresetOverrides = 0; AlreadyConfigured = @('blitz99') }
        $view = Get-TpmDgVoodoo2ResultView -Result $result
        $view.Title | Should -Match 'added to 3 games'
        $view.Title | Should -Match '1 game already had every dgVoodoo2 file'
        $view.Title | Should -Match 'blitz99'
    }
    It 'says nothing extra when every selected game was changed' {
        $result = [pscustomobject]@{ DeploymentDetails = @([pscustomobject]@{ Game = 'a' }); SkipDetails = @(); NoOp = $false; PresetOverrides = 0; AlreadyConfigured = @() }
        (Get-TpmDgVoodoo2ResultView -Result $result).Title | Should -Not -Match 'already had'
    }
    It 'lets the user go back from an optional-step question with B' {
        $script:Answers.Clear(); $script:Answers.Enqueue('b')
        Read-TpmOptionalStepChoice -Step GpuFix -Default '' -AllowBack | Should -Be 'B'
    }
    It 'asks again after an answer that is not Y, N or B' {
        $script:Answers.Clear(); $script:Answers.Enqueue('x'); $script:Answers.Enqueue('n')
        Read-TpmOptionalStepChoice -Step DgVoodoo2 -Default 'N' -AllowBack | Should -Be 'N'
    }
    It 'asks about one game at a time with a Back choice and skips games that cannot be changed' {
        $script:SourceText | Should -Match 'Install for \{0\}\? \[Y\] Yes  \[N\] No  \[B\] Back'
        $script:SourceText | Should -Match 'Asking only about the \{0\} that can be changed'
    }
    It 'walks the optional setup questions back instead of repeating Please choose Y or N' {
        $script:SourceText | Should -Match 'Read-TpmOptionalStepChoice -Step GpuFix -Default '''' -AllowBack'
        $script:SourceText | Should -Match 'Read-TpmOptionalStepChoice -Step DgVoodoo2 -Default ''N'' -AllowBack'
        $script:SourceText | Should -Match '\} while \(\$optionalGoBack\)'
    }
}

Describe 'ReShade one-by-one questions: Back returns to the previous game (issue 416)' {
    BeforeAll {
        $src = Join-Path (Split-Path -Parent $PSScriptRoot) 'TeknoParrot-Manager.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
        foreach ($f in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Read-TpmReShadeOneByOneAnswers' }, $true)) { . ([scriptblock]::Create($f.Extent.Text)) }
        function Get-TpmGameTitle { param($Name) return "Title $Name" }
        $script:Replies = New-Object System.Collections.Queue
        $script:Prompts = New-Object System.Collections.Generic.List[string]
        function Read-TpmChoice { param($Prompt, $Choices, $Default) [void]$script:Prompts.Add($Prompt); return [string]$script:Replies.Dequeue() }
        $script:Games = @([pscustomobject]@{ BaseName = 'one' }, [pscustomobject]@{ BaseName = 'two' }, [pscustomobject]@{ BaseName = 'three' })
        function Start-Replies { param([string[]]$Answers) $script:Replies.Clear(); $script:Prompts.Clear(); foreach ($a in $Answers) { $script:Replies.Enqueue($a) } }
    }

    It 'Back on the second game asks the first game again and keeps the new answer' {
        Start-Replies 'Y', 'B', 'N', 'Y', 'Y'
        $r = Read-TpmReShadeOneByOneAnswers -Games $script:Games
        $r.BackedOut | Should -BeFalse
        $r.Answers['one'] | Should -BeFalse
        $r.Answers['two'] | Should -BeTrue
        $r.Answers['three'] | Should -BeTrue
        $script:Prompts.Count | Should -Be 5
        $script:Prompts[2] | Should -Be '  Install for Title one? [Y] Yes  [N] No  [B] Back  (game 1 of 3, default Y)'
    }
    It 'Back on the first game leaves the questions without any answers' {
        Start-Replies 'B'
        $r = Read-TpmReShadeOneByOneAnswers -Games $script:Games
        $r.BackedOut | Should -BeTrue
        $r.Answers.Count | Should -Be 0
    }
    It 'asks every game with the same wording and counts them' {
        Start-Replies 'Y', 'N', 'Y'
        [void](Read-TpmReShadeOneByOneAnswers -Games $script:Games)
        $script:Prompts[1] | Should -Be '  Install for Title two? [Y] Yes  [N] No  [B] Back  (game 2 of 3, default Y)'
        $script:Prompts[2] | Should -Be '  Install for Title three? [Y] Yes  [N] No  [B] Back  (game 3 of 3, default Y)'
    }
}
