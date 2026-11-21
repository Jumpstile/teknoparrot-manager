#Requires -Module Pester

# Issue #419: after registering games, a user who takes the default [N] "New game only" used to go
# straight back to the menu and never saw the LaunchBox offer. The offer is now one function that
# runs after "New game only" and after the whole-library checks, and it is still skipped during a
# preview (dry run) and in -Unattended mode.
Describe 'LaunchBox offer after New game only' {
    BeforeAll {
        $src = Join-Path (Split-Path -Parent $PSScriptRoot) 'TeknoParrot-Manager.ps1'
        $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
        $fn = @($script:Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-TpmLaunchBoxStep' }, $true))
        if ($fn.Count -ne 1) { throw 'Expected exactly one Invoke-TpmLaunchBoxStep function.' }
        . ([scriptblock]::Create($fn[0].Extent.Text))

        $script:Calls = New-Object System.Collections.Generic.List[string]
        function Write-Log { param([string]$msg) }
        function Write-Host { param([Parameter(ValueFromRemainingArguments)]$a) }
        function Write-TpmLaunchBoxOffer { $script:Calls.Add('offer') }
        function Read-TpmChoice { param($Prompt, $Choices, $Default) $script:Calls.Add('choice'); return $script:NextChoice }
        function Export-LaunchBoxXml { param($userProfilesDir, $outputPath) $script:Calls.Add('export'); return -1 }
# The details/playlists and picture steps are separate screens with their own tests; here they only need to exist.
function Invoke-TpmLaunchBoxEnrichStep { param($UserProfilesDir, $LbRoot, $TpRoot, $DatIndex) }
function Invoke-TpmLaunchBoxChangeStep { param($Kind, $UserProfilesDir, $LbRoot, $TpRoot, $DatIndex) }
function Invoke-TpmLaunchBoxMediaStep { param($lbRoot, $userProfilesDir, [switch]$Unattended, [switch]$DryRun, $TpRoot, $DatIndex) }
        $script:TpmOwnedLayout = @{ Reports = $TestDrive }
        $script:NextChoice = 'B'
    }
    BeforeEach { $script:Calls.Clear(); $script:NextChoice = 'B' }

    It 'runs the New game only branch into the LaunchBox step before it returns to the menu' {
        $ifs = @($script:Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -match "maintenanceChoice\s+-eq\s+'N'" }, $true))
        $ifs.Count | Should -Be 1
        $branch = $ifs[0].Clauses[0].Item2
        $commands = @($branch.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true))
        $call = @($commands | Where-Object { $_.GetCommandName() -eq 'Invoke-TpmLaunchBoxStep' })
        $call.Count | Should -Be 1
        $enter = @($commands | Where-Object { $_.GetCommandName() -eq 'Read-HostSafe' -and $_.Extent.Text -match 'return to the menu' })
        $enter.Count | Should -Be 1
        $call[0].Extent.StartOffset | Should -BeLessThan $enter[0].Extent.StartOffset
    }
    It 'does not add the offer to the Back branch' {
        $ifs = @($script:Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -match "maintenanceChoice\s+-eq\s+'B'" }, $true))
        $ifs.Count | Should -Be 1
        $ifs[0].Clauses[0].Item2.Extent.Text | Should -Not -Match 'LaunchBox'
    }
    It 'keeps exactly one other call, after the whole-library checks' {
        $calls = @($script:Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Invoke-TpmLaunchBoxStep' }, $true))
        $calls.Count | Should -Be 2
    }
    It 'shows the offer and asks for a choice in a normal run' {
        $dryRunActive = $false; $Unattended = $false
        Invoke-TpmLaunchBoxStep
        $script:Calls | Should -Contain 'offer'
        $script:Calls | Should -Contain 'choice'
    }
    It 'saves a reference file when the user picks F' {
        $dryRunActive = $false; $Unattended = $false; $script:NextChoice = 'F'
        Invoke-TpmLaunchBoxStep
        $script:Calls | Should -Contain 'export'
    }
    It 'shows nothing in a preview (dry run)' {
        $dryRunActive = $true; $Unattended = $false
        Invoke-TpmLaunchBoxStep
        $script:Calls.Count | Should -Be 0
    }
    It 'shows nothing in -Unattended mode' {
        $dryRunActive = $false; $Unattended = $true
        Invoke-TpmLaunchBoxStep
        $script:Calls.Count | Should -Be 0
    }
}
