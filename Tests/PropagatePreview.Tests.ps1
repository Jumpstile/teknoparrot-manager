#Requires -Modules Pester
# Issue #411: Propagate Controls must show what would change before asking to save anything.

Describe 'Propagate Controls preview before approval' {
    BeforeAll {
        $script:text = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'))
        $start = $script:text.IndexOf('if ($mode -eq "PropagateControls") {')
        $end = $script:text.IndexOf('if ($mode -eq "CrosshairSetup") {')
        $script:block = $script:text.Substring($start, $end - $start)
    }

    It 'finds the Propagate Controls menu block' {
        $script:block.Length | Should -BeGreaterThan 500
    }

    It 'runs a preview (DryRun true) before the approval question' {
        $preview = $script:block.IndexOf('-DryRun $true')
        $approval = $script:block.IndexOf('Read-TpmControlCopyApproval')
        $preview | Should -BeGreaterThan -1
        $approval | Should -BeGreaterThan $preview
    }

    It 'shows the preview with the preview wording' {
        $script:block | Should -Match 'Write-ControlPropagationResults[^\r\n]*-DryRun \$true'
    }

    It 'skips the approval question when the preview has nothing to change' {
        $script:block | Should -Match "\`$goCtl = 'N'"
    }

    It 'saves only in the branch the user approved' {
        $real = $script:block.IndexOf('-DryRun $false', $script:block.IndexOf('Read-TpmControlCopyApproval'))
        $real | Should -BeGreaterThan $script:block.IndexOf('Read-TpmControlCopyApproval')
    }
}

Describe 'Propagate Controls always backs up the original settings first' {
    BeforeAll {
        $text = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'))
        $s = $text.IndexOf('function Invoke-ControlPropagationLegacy {')
        $e = $text.IndexOf('function Get-TpmControlPropagationReportLine {')
        $script:legacy = $text.Substring($s, $e - $s)
    }

    It 'saves a profile only through the guarded save' {
        $direct = [regex]::Matches($script:legacy, 'Save-XmlMaybe')
        # Exactly one direct call: the one inside the guard itself.
        $direct.Count | Should -Be 1
        $script:legacy.IndexOf('Save-XmlMaybe') | Should -BeGreaterThan $script:legacy.IndexOf('New-TpmVerifiedUserProfilesBackup')
    }

    It 'refuses to save when the backup could not be verified' {
        $script:legacy | Should -Match 'The safety backup could not be verified'
        $script:legacy | Should -Match 'if \(\$null -ne \$writeGate\.Error\) \{ throw \$writeGate\.Error \}'
    }

    It 'every real save goes through the guard' {
        ([regex]::Matches($script:legacy, '& \$saveGuarded')).Count | Should -BeGreaterOrEqual 3
    }
}

Describe 'Propagate Controls offers a one-step undo' {
    BeforeAll {
        $text = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'))
        $s = $text.IndexOf('if ($mode -eq "PropagateControls") {')
        $e = $text.IndexOf('if ($mode -eq "CrosshairSetup") {')
        $script:menu = $text.Substring($s, $e - $s)
    }

    It 'offers to undo right after the save, using the backup made for this run' {
        $script:menu | Should -Match 'Undo these changes'
        $script:menu | Should -Match 'Invoke-RestoreBackup[^\r\n]*-SelectedBackupPath \$undoFolder'
    }

    It 'defaults to No and never asks in unattended runs' {
        $script:menu | Should -Match "Undo these changes[^\r\n]*-Default 'N'"
        $script:menu | Should -Match 'if \(-not \$Unattended -and \$propTransaction\.Outcome'
    }
}