Describe 'A second problem after the status screen is closed does not crash setup' {
    BeforeAll {
        $src = Join-Path (Split-Path -Parent $PSScriptRoot) 'TeknoParrot-Manager.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
        $funcs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in @('Resolve-TpmWorkflowFailure','Get-TpmTransactionField','Get-TpmPostgresDataSafetyText','Get-TpmPostgresServiceRestoreSafetyText') }, $true)
        foreach ($f in $funcs) { . ([scriptblock]::Create($f.Extent.Text)) }
        function Write-Log { param($m) $script:LogLines += [string]$m }
        function Write-TpmDetailBlocksLog { param($Blocks, $Prefix) }
        function Read-HostSafe { param($p) $script:Prompts += [string]$p; return '' }
        function Set-TpmWorkflowFailure { param($Context, $FailureId, $Message, $DataSafety, $RecoveryActions) throw 'Workflow is already closed.' }
        function Acknowledge-TpmWorkflowFailure { param($Context, $FailureId) throw 'Workflow is already closed.' }
        function Stop-TpmWorkflowStatus { param($Context, $Reason) throw 'Workflow is already closed.' }
        function Close-TpmWorkflowStatus { param($Context) }
        function Write-Host { param([Parameter(ValueFromRemainingArguments)]$a) }
    }
    BeforeEach { $script:LogLines = @(); $script:Prompts = @() }

    It 'shows the result and waits for Enter instead of throwing when the workflow is already closed' {
        $ctx = [pscustomobject]@{ Closed = $true; Failure = $null }
        { Resolve-TpmWorkflowFailure -Context $ctx -FailureId 'postgres-service-restore' -Message 'PostgreSQL could not be put back.' -DataSafety 'Setup is not finished.' -Acknowledge } | Should -Not -Throw
        $script:Prompts.Count | Should -Be 1
        ($script:LogLines -join "`n") | Should -Match 'already closed'
    }
    It 'still raises the failure normally while the workflow is open' {
        $ctx = [pscustomobject]@{ Closed = $false; Failure = $null }
        { Resolve-TpmWorkflowFailure -Context $ctx -FailureId 'postgres-service-restore' -Message 'm' -DataSafety 'd' } | Should -Throw
    }
    It 'keeps the database result and the service problem apart' {
        $rolledBack = [pscustomobject]@{ Outcome = 'ROLLED_BACK_VERIFIED'; ProductState = 'UNCHANGED' }
        $text = Get-TpmPostgresServiceRestoreSafetyText -Result $rolledBack
        $text | Should -Match 'back the way it was'
        $text | Should -Match 'service, not your databases'
        $unknown = Get-TpmPostgresServiceRestoreSafetyText -Result $null
        $unknown | Should -Not -Match 'back the way it was'
        $unknown | Should -Match 'not finished'
    }
}
