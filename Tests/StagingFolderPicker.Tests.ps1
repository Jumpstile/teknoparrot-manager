#Requires -Module Pester
# Canceling the folder picker at the staging-folder prompt must ask again. It must not take the suggested folder.
# The real Read-TpmStagingFolder runs; only the typed answer and the picker window are faked.

BeforeAll {
    $sourcePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'TeknoParrot-Manager.ps1'
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw ($errors -join '; ') }
    $text = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    . ([scriptblock]::Create($text))
    function Write-Log { param([string]$Message) }
    function Read-HostSafe { param([string]$Prompt, [string]$Default = $null) }
    function Read-PathWithBrowse { param([string]$Prompt, [string]$InitialDirectory = '') }
}

Describe 'Staging folder prompt' {
    BeforeEach {
        $root = Join-Path $TestDrive ('pick-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:TpRoot = Join-Path $root 'TeknoParrot'
        $script:Zips = Join-Path $root 'Zips'
        $script:Suggested = Join-Path $root 'Suggested'
        $script:Chosen = Join-Path $root 'Chosen'
        foreach ($d in @($script:TpRoot, $script:Zips, $script:Suggested, $script:Chosen)) { [void][System.IO.Directory]::CreateDirectory($d) }
        $script:Answers = New-Object System.Collections.Generic.Queue[string]
        $script:AskCount = 0
        Mock Write-Host {}
        Mock Read-HostSafe {
            $script:AskCount++
            $answer = $script:Answers.Dequeue()
            if ($answer -eq '' -and $null -ne $Default) { return $Default }
            return $answer
        }
    }

    It 'asks again after the picker is canceled and uses the folder chosen next, not the suggested one' {
        # Mutation: treat a canceled picker like Enter -> the suggested folder is returned after one question.
        foreach ($a in @('B', $script:Chosen)) { $script:Answers.Enqueue($a) }
        Mock Read-PathWithBrowse { '' }
        $result = Read-TpmStagingFolder -RecommendedPath $script:Suggested -TeknoParrotRoot $script:TpRoot -ZipSource $script:Zips
        $script:AskCount | Should -Be 2
        $result | Should -Be $script:Chosen
    }

    It 'still takes the suggested folder when the player just presses Enter' {
        $script:Answers.Enqueue('')
        $result = Read-TpmStagingFolder -RecommendedPath $script:Suggested -TeknoParrotRoot $script:TpRoot -ZipSource $script:Zips
        $result | Should -Be $script:Suggested
    }

    It 'goes back with nothing chosen when the player types Q (recovery question)' {
        $script:Answers.Enqueue('Q')
        $result = Read-TpmStagingFolder -RecommendedPath $script:Suggested -TeknoParrotRoot $script:TpRoot -ZipSource $script:Zips -AllowBack
        $result | Should -BeNullOrEmpty
        $script:AskCount | Should -Be 1
    }

    It 'keeps asking, with a hint, after a closed browse window, and Q then goes back' {
        foreach ($a in @('B', 'B', 'q')) { $script:Answers.Enqueue($a) }
        Mock Read-PathWithBrowse { '' }
        $result = Read-TpmStagingFolder -RecommendedPath '' -TeknoParrotRoot $script:TpRoot -ZipSource $script:Zips -AllowBack
        $result | Should -BeNullOrEmpty
        $script:AskCount | Should -Be 3
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*No folder was chosen*Q to go back*' } -Times 2 -Exactly
    }

    It 'still refuses Q where going back is not possible (first-run question)' {
        foreach ($a in @('Q', $script:Chosen)) { $script:Answers.Enqueue($a) }
        $result = Read-TpmStagingFolder -RecommendedPath '' -TeknoParrotRoot $script:TpRoot -ZipSource $script:Zips
        $result | Should -Be $script:Chosen
        $script:AskCount | Should -Be 2
    }
}
