Describe 'Setup screens account for every game and offer a way back' {
    BeforeAll {
        $src = Join-Path (Split-Path -Parent $PSScriptRoot) 'TeknoParrot-Manager.ps1'
        $script:SourceText = Get-Content -LiteralPath $src -Raw
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
        $want = @('Get-TpmDgVoodoo2ResultView', 'Get-TpmDgVoodoo2GameOutcomes', 'Get-TpmStepCountsLine', 'Get-TpmBackupFolderLine', 'Get-TpmDriveSkipNext', 'Format-TpmNameList', 'Join-TpmPostgresSetupNames', 'Read-TpmOptionalStepChoice', 'Get-TpmOptionalStepName', 'Get-TpmOptionalStepHelpBlocks')
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
