#Requires -Module Pester

# The last finished workflow is kept in a small cleaned file so a support package made after a restart still shows it.
BeforeAll {
    $sourcePath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Fix409 bootstrap could not parse the manager.' }
    $functionsPath = Join-Path $TestDrive 'fix409-functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
        ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionsPath
    . $functionsPath
    function Write-Log { param([Parameter(ValueFromRemainingArguments)]$Message) }
    function New-F409Snapshot {
        [pscustomobject]@{
            WorkflowId = 'wf-1'; RunId = 'run-1'; WorkflowKey = 'DgVoodoo2Setup'; Title = 'Set up dgVoodoo2'; Lifecycle = 'Aborted'; State = 'Skipped'
            Sequence = 7; Activity = 'Stopped'; NextStep = 'Run it again'
            Completed = @([pscustomobject]@{ Summary = 'Could not write C:\Users\Someone\Games\a.dll'; Outcome = 'Failed' })
        }
    }
}

Describe 'The last finished workflow survives a restart for the support package' {
    BeforeEach {
        $script:state = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($script:state)
        $script:TpmOwnedLayout = [pscustomobject]@{ State = $script:state }
    }

    It 'keeps what happened and how it ended, with personal folders removed' {
        Save-TpmLastWorkflowRecord -Snapshot (New-F409Snapshot)
        $record = Read-TpmLastWorkflowRecord -StateDirectory $script:state
        $record.WorkflowKey | Should -Be 'DgVoodoo2Setup'
        $record.State | Should -Be 'Skipped'
        $record.RunId | Should -Be 'run-1'
        @($record.Completed)[0].Outcome | Should -Be 'Failed'
        @($record.Completed)[0].Summary | Should -Not -Match 'Someone'
        @($record.Completed)[0].Summary | Should -Match 'Could not write'
    }

    It 'treats a missing or damaged file as no record' {
        Read-TpmLastWorkflowRecord -StateDirectory $script:state | Should -BeNullOrEmpty
        Set-Content -LiteralPath (Join-Path $script:state 'TPM-LastWorkflow.json') -Value '{ not json'
        Read-TpmLastWorkflowRecord -StateDirectory $script:state | Should -BeNullOrEmpty
    }
}
