#Requires -Module Pester

# FIX143: the registration run (AutoSync / Register only) sets up controls with the controller layout system,
# the same one as Controls choice 1. It no longer asks for a "recommended binding plan".
#
# The production script is parsed and only its function definitions are dot-sourced. Nothing here touches a real
# install, the registry or the network. Each It names the product mutation that makes it fail.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $source = [System.IO.File]::ReadAllText($productionPath)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX143 tests could not parse the production script.' }
    $script:F143Ast = $ast
    $script:F143Source = $source
    $definitions = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    $functionFile = Join-Path $TestDrive 'tpm-fix143-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, (@($definitions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"), (New-Object System.Text.UTF8Encoding $false))
    . $functionFile

    # Every way of asking a question throws, so a question can never hang a test or pass unnoticed.
    function Read-TpmYesNo { throw 'A question was asked.' }
    function Read-TpmChoice { throw 'A question was asked.' }
    function Read-HostSafe { throw 'A question was asked.' }
}

Describe 'FIX143 the registration run calls the controller layout step and not the old copy step' {
    BeforeAll {
        # The registration run's controls section is the top-level code between its SECTION 10 header and the "Done" header.
        $start = $script:F143Source.IndexOf('# SECTION 10 -- Controller layout')
        $end = $script:F143Source.IndexOf('# Done', $start)
        $script:F143Section = if ($start -ge 0 -and $end -gt $start) { $script:F143Source.Substring($start, $end - $start) } else { '' }
        $sectionAst = [System.Management.Automation.Language.Parser]::ParseInput($script:F143Section, [ref]$null, [ref]$null)
        $script:F143Commands = @($sectionAst.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() })
    }

    It 'has the controller layout section and calls the new step with the run''s preview and unattended state' {
        # Mutation: remove the controller layout section -> the section header is missing.
        $script:F143Section | Should -Not -BeNullOrEmpty
        $script:F143Commands | Should -Contain 'Invoke-TpmAutoSyncLayoutStep'
        $script:F143Section | Should -Match '-DryRun \$dryRunActive'
        $script:F143Section | Should -Match '-Unattended \(\[bool\]\$Unattended\)'
    }

    It 'asks no device questions in the registration run' {
        # Mutation: bring back the old survey call or any yes/no question -> the matching name is found in the section.
        foreach ($old in @('Invoke-DeviceSurvey', 'Read-TpmYesNo')) {
            $script:F143Commands | Should -Not -Contain $old
        }
    }
}

Describe 'FIX143 Invoke-TpmAutoSyncLayoutStep' {
    BeforeEach {
        $script:F143Batches = New-Object System.Collections.Generic.List[object]
        Mock Write-TpmText {}
        Mock Write-Log {}
        Mock Write-TpmBaselineBatchPreview {}
        Mock Get-TpmBaselineBatchLines { @() }
        Mock Get-TpmBaselineLayoutSource { 'test' }
        Mock Get-TpmBaselineLayout { @() }
        Mock Get-TpmBaselinePresets { @{ Xbox = @{ Title = 'Xbox controller' } } }
        Mock Invoke-TpmProgressGroup { & $Action }
        Mock Get-TpmRegisteredProfileFilesWithDiscoveryProgress { @([pscustomobject]@{ FullName = 'C:\fake\A.xml'; BaseName = 'A' }, [pscustomobject]@{ FullName = 'C:\fake\B.xml'; BaseName = 'B' }) }
        Mock Invoke-TpmBaselineBatch {
            $script:F143Batches.Add([bool]$DryRun)
            $status = if ($DryRun) { 'WouldChange' } else { 'Changed' }
            [pscustomobject]@{
                Results = @([pscustomobject]@{ Path = 'C:\fake\A.xml'; Code = 'A'; Title = 'A'; Status = $status; Signature = 'sig'; Reason = '' }, [pscustomobject]@{ Path = 'C:\fake\B.xml'; Code = 'B'; Title = 'B'; Status = 'NoChange'; Signature = ''; Reason = '' })
                Changed = 1; Unchanged = 1; Unsupported = 0; Refused = 0; Failed = 0; Backup = [pscustomobject]@{ Path = 'C:\fake\backup' }
            }
        }
        $script:F143Args = @{ UserProfilesDir = 'C:\fake\UserProfiles'; GameProfilesDir = 'C:\fake\GameProfiles'; StateDir = 'C:\fake\State' }
    }

    It 'unattended with no saved layout skips with one plain line and changes nothing' {
        # Mutation: apply a default layout when none is saved -> a batch runs.
        Mock Read-TpmBaseline { $null }
        $r = Invoke-TpmAutoSyncLayoutStep @script:F143Args -Unattended $true
        Should -Invoke Invoke-TpmBaselineBatch -Times 0 -Exactly
        $r.GamesChanged | Should -Be 0
        $r.GamesWouldChange | Should -Be 0
        Should -Invoke Write-TpmText -Times 1 -Exactly -ParameterFilter { $Text -match 'not chosen a controller layout' }
    }

    It 'unattended with a saved layout previews, then applies it once, asks nothing and reports the real count' {
        # Mutation: skip the preview check or the apply -> the batch calls differ. Mutation: ask a question -> the question mocks throw.
        Mock Read-TpmBaseline { [pscustomobject]@{ Preset = 'Xbox'; Slots = @{} } }
        $r = Invoke-TpmAutoSyncLayoutStep @script:F143Args -Unattended $true
        $got = [string]::Join(",", [string[]]@($script:F143Batches | ForEach-Object { [string]$_ }))
        $got | Should -BeExactly "True,False"
        $r.GamesChanged | Should -Be 1
        $r.GamesFailed | Should -Be 0
    }

    It 'the arcade learned layout changes nothing, even unattended' {
        # Mutation: treat the learned arcade layout like a pad layout -> a batch runs.
        Mock Read-TpmBaseline { [pscustomobject]@{ Preset = 'LearnedArcade'; Slots = @{} } }
        $r = Invoke-TpmAutoSyncLayoutStep @script:F143Args -Unattended $true
        Should -Invoke Invoke-TpmBaselineBatch -Times 0 -Exactly
        $r.GamesChanged | Should -Be 0
    }

    It 'preview shows what would change and writes nothing' {
        # Mutation: run the real apply in preview -> the batch list contains $false.
        Mock Read-TpmBaseline { [pscustomobject]@{ Preset = 'Xbox'; Slots = @{} } }
        $r = Invoke-TpmAutoSyncLayoutStep @script:F143Args -DryRun $true
        [string]::Join(",", [string[]]@($script:F143Batches | ForEach-Object { [string]$_ })) | Should -BeExactly "True"
        $r.GamesChanged | Should -Be 0
        $r.GamesWouldChange | Should -Be 1
    }

    It 'interactive runs the same screen as the menu and reports only what the screen set up' {
        # Mutation: report games as set up when the screen set up none -> the recap claims work that was not done.
        Mock Invoke-TpmBaselineScreen { [pscustomobject]@{ TpmBaselineResult = $true; GamesChanged = 4 } }
        (Invoke-TpmAutoSyncLayoutStep @script:F143Args).GamesChanged | Should -Be 4
        Mock Invoke-TpmBaselineScreen { }
        (Invoke-TpmAutoSyncLayoutStep @script:F143Args).GamesChanged | Should -Be 0
        Should -Invoke Invoke-TpmBaselineBatch -Times 0 -Exactly
    }
}

Describe 'FIX143 the recap does not claim controls were set up when the step did nothing' {
    It 'says nothing about the controller layout when no game was set up' {
        # Mutation: always add the line -> the Done list names a layout step that did nothing.
        $recap = Get-TpmRegistrationRecap -AutoSyncRan $false -NewlyRegistered 2
        (@($recap.Done) -join ' ') | Should -Not -Match 'controller layout'
        (@($recap.Done) -join ' ') | Should -Not -Match 'copied'
    }

    It 'says how many games were set up, or would be in a preview' {
        # Mutation: swap the preview and real wording -> a preview claims it changed games.
        $real = Get-TpmRegistrationRecap -AutoSyncRan $false -NewlyRegistered 2 -ControlsLayoutSetUp 3 -ControlsLayoutWouldSetUp 9
        @($real.Done) | Should -Contain '3 games set up with your controller layout.'
        $preview = Get-TpmRegistrationRecap -AutoSyncRan $false -NewlyRegistered 2 -Preview $true -ControlsLayoutSetUp 3 -ControlsLayoutWouldSetUp 5
        @($preview.Done) | Should -Contain '5 games would be set up with your controller layout.'
        (@($preview.Done) -join ' ') | Should -Not -Match '3 games set up'
    }
}
