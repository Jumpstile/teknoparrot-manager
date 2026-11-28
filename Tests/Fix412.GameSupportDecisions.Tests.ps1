#Requires -Module Pester

# scripts\TpmGameSupportDecisions.json holds one decision per guide game for the loaders that run a program (not a ROM set).
# The coverage tool reads it. These tests keep it honest: the rules are re-applied to the stored signals, the patch catalog and
# the graphics card warning table must agree with it, and a CPU or unclear "Intel" wording never becomes a graphics card condition.
# The Game Notes tests cover what a player sees: the extra archives the guide names and a linked profile.
BeforeAll {
    $sourcePath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null; $parseErrors = $null
    $script:f412Ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Fix412 bootstrap could not parse TPM.' }
    $functionsPath = Join-Path $TestDrive 'fix412-functions.ps1'
    ($script:f412Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
        ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionsPath
    . $functionsPath
    function Write-Log { param([Parameter(ValueFromRemainingArguments)]$Message) }

    $assignment = @($script:f412Ast.FindAll({
        $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $args[0].Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $args[0].Left.VariablePath.UserPath -eq 'GpuIncompatibleGames' }, $true))
    if ($assignment.Count -ne 1) { throw 'Fix412 could not find the graphics card warning table.' }
    $script:f412GpuTable = & ([scriptblock]::Create($assignment[0].Right.Extent.Text))

    $script:f412Decisions = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmGameSupportDecisions.json') -Raw | ConvertFrom-Json
    $script:f412Recipes = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmRequiredPatchRecipes.json') -Raw | ConvertFrom-Json

    # The rules, written out again here on purpose: a hand edit of Disposition or Also that the signals do not support fails the test.
    function Get-F412Dispositions {
        param([string[]]$Signals)
        $tags = New-Object System.Collections.Generic.List[string]
        if (@($Signals | Where-Object { $_ -in @('unsupported', 'ignored-entry', 'broken') }).Count -gt 0) { $tags.Add('not-supported') }
        if ($Signals -contains 'recipe') { $tags.Add('tpm-applies-patch') }
        if ($Signals -contains 'emulator-files') { $tags.Add('tpm-checks-files') }
        if (@($Signals | Where-Object { $_ -in @('supp_archives', 'additional_archives') }).Count -gt 0) { $tags.Add('needs-own-archive') }
        if (@($Signals | Where-Object { $_ -in @('gpu-warning', 'path-limit', 'file-version') }).Count -gt 0) { $tags.Add('tpm-warns') }
        if (@($Signals | Where-Object { $_ -in @('notes', 'general_issues', 'setup_exe2', 'test_exe', 'linked_profile', 'gpu-text') }).Count -gt 0) { $tags.Add('guided') }
        return $tags.ToArray()
    }
}

Describe 'Game support decisions file' {
    It 'has one row per profile, every field filled and only known dispositions' {
        $allowed = @($script:f412Decisions.Dispositions.PSObject.Properties.Name)
        $allowed | Should -Contain 'register-only'
        $rows = @($script:f412Decisions.Profiles)
        $rows.Count | Should -BeGreaterThan 500
        @($rows | ForEach-Object { $_.Profile } | Sort-Object -Unique).Count | Should -Be $rows.Count
        foreach ($row in $rows) {
            $row.Profile | Should -Not -BeNullOrEmpty
            $row.Loader | Should -Not -BeNullOrEmpty
            $row.Reason | Should -Not -BeNullOrEmpty
            $allowed | Should -Contain $row.Disposition
            foreach ($other in @($row.Also)) { $allowed | Should -Contain $other }
        }
    }

    It 'keeps no ROM-set loader in these rows' {
        $excluded = @($script:f412Decisions.Scope.ExcludedLoaders)
        $excluded.Count | Should -BeGreaterThan 10
        @($script:f412Decisions.Profiles | Where-Object { $excluded -contains $_.Loader }).Count | Should -Be 0
    }

    It 'matches the rules applied to each row''s signals' {
        foreach ($row in @($script:f412Decisions.Profiles)) {
            $tags = @(Get-F412Dispositions -Signals @($row.Signals))
            $expectedPrimary = if ($tags.Count -gt 0) { $tags[0] } else { 'register-only' }
            $expectedAlso = if ($tags.Count -gt 1) { @($tags[1..($tags.Count - 1)]) } else { @() }
            $row.Disposition | Should -BeExactly $expectedPrimary -Because ('profile ' + $row.Profile)
            (@($row.Also) -join ',') | Should -BeExactly ($expectedAlso -join ',') -Because ('profile ' + $row.Profile)
        }
    }

    It 'lists exactly the profiles of the reviewed patch catalog as patch decisions' {
        $recipeProfiles = @($script:f412Recipes.Entries | Where-Object { $_.Operations[0].Type -cne 'CopyFolder' } | ForEach-Object { $_.ProfileId } | Sort-Object -Unique)
        $decided = @($script:f412Decisions.Profiles | Where-Object { @($_.Signals) -contains 'recipe' } | ForEach-Object { $_.Profile } | Sort-Object)
        ($decided -join ',') | Should -BeExactly ($recipeProfiles -join ',')
        foreach ($row in @($script:f412Decisions.Profiles | Where-Object { @($_.Signals) -contains 'recipe' })) {
            (@($row.Disposition) + @($row.Also)) | Should -Contain 'tpm-applies-patch'
        }
    }

    It 'says "emulator files" only for the loaders whose startup files TPM checks' {
        $checked = @('pcsx2x6', 'cxbxr', 'RPCS3', 'Play')
        foreach ($row in @($script:f412Decisions.Profiles | Where-Object { @($_.Signals) -contains 'emulator-files' })) { $checked | Should -Contain $row.Loader }
        foreach ($row in @($script:f412Decisions.Profiles | Where-Object { $checked -contains $_.Loader })) { @($row.Signals) | Should -Contain 'emulator-files' }
    }
}

Describe 'Third-party items for the guided games' {
    BeforeAll {
        $script:f412Checks = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmThirdPartyChecks.json') -Raw | ConvertFrom-Json
    }

    It 'covers exactly the 15 external games, each a guided row, with a message in plain words' {
        $names = @($script:f412Checks.Entries | ForEach-Object { $_.Profile } | Sort-Object)
        $names.Count | Should -Be 15
        @($names | Sort-Object -Unique).Count | Should -Be 15
        foreach ($entry in @($script:f412Checks.Entries)) {
            $row = @($script:f412Decisions.Profiles | Where-Object { $_.Profile -eq $entry.Profile })
            $row.Count | Should -Be 1 -Because $entry.Profile
            # A game whose file part has a recipe (Dragon Dance iDmacDrv32.dll) is a patch row that is still guided for the rest.
            if ($entry.Profile -ceq 'DragonDanceNesica') { $row[0].Disposition | Should -BeExactly 'tpm-applies-patch'; @($row[0].Also) | Should -Contain 'guided'; $row[0].Reason | Should -Match 'catalog' } else { $row[0].Disposition | Should -BeExactly 'guided'; $row[0].Reason | Should -Match 'never downloads' }
            $entry.Message | Should -Match 'never (downloads|installs|replaces|runs)' -Because $entry.Profile
        }
    }

    It 'checks only relative files (in the game folder, or at the top of the drive when the entry says so) and gives a link only when the guide does' {
        foreach ($entry in @($script:f412Checks.Entries)) {
            $entry.CanCheck | Should -Be (@($entry.Checks).Count -gt 0)
            if ($entry.PSObject.Properties['CheckRoot']) { $entry.CheckRoot | Should -BeExactly 'DriveRoot' }
            foreach ($check in @($entry.Checks)) {
                $check.Type | Should -BeExactly 'File'
                $check.Path | Should -Not -Match '^[A-Za-z]:|^[\\/]|\.\.'
                $check.Id | Should -Not -BeNullOrEmpty
                $check.Description | Should -Not -BeNullOrEmpty
            }
            if ($entry.GuideLink) { $entry.Details | Should -Match 'Get it yourself' }
        }
    }

    It 'gives every guided game a reason that says what TPM does, not the generic line' {
        foreach ($row in @($script:f412Decisions.Profiles | Where-Object { $_.Disposition -eq 'guided' })) {
            $row.Reason | Should -Not -Match 'shows the guide''s notes' -Because $row.Profile
        }
    }
}

Describe 'Graphics card decisions agree with the warning table' {
    It 'has every warning-table game that is in this file as a warning row, and every NO or explicit-text warning row in the table' {
        $profileNames = @($script:f412Decisions.Profiles | ForEach-Object { $_.Profile })
        $rows = @($script:f412Decisions.Graphics)
        foreach ($vendor in @('AMD', 'Intel')) {
            foreach ($game in @($script:f412GpuTable[$vendor] | Where-Object { $profileNames -contains $_ })) {
                @($rows | Where-Object { $_.Profile -eq $game -and $_.Vendor -eq $vendor -and $_.Action -eq 'warning' }).Count | Should -Be 1 -Because ("$game $vendor")
            }
        }
        foreach ($row in @($rows | Where-Object { $_.Action -eq 'warning' -and ($_.Status -eq 'NO' -or $_.Text -like 'notes:*') })) {
            @($script:f412GpuTable[$row.Vendor]) | Should -Contain $row.Profile -Because ($row.Profile + ' ' + $row.Vendor)
        }
    }

    It 'never turns CPU or unclear Intel wording into a graphics card condition' {
        $listed = @($script:f412Decisions.NotGpuConditions | ForEach-Object { $_.Profile })
        $listed | Should -Contain 'Akuma'
        $listed | Should -Contain 'BlockKing'
        foreach ($profile in $listed) {
            @($script:f412GpuTable['Intel']) | Should -Not -Contain $profile
            @($script:f412Decisions.Graphics | Where-Object { $_.Profile -eq $profile }).Count | Should -Be 0
        }
    }

    It 'applies a graphics fix only through the existing profile-field helper, and only for the exact text' {
        $apply = @($script:f412Decisions.Graphics | Where-Object { $_.Action -eq 'generic-fix-field' })
        $apply.Count | Should -BeGreaterThan 0
        foreach ($row in $apply) {
            $row.Text | Should -Match 'Select AMD Fix in settings'
            $row.Vendor | Should -BeExactly 'AMD'
            $row.Field | Should -BeExactly 'GPU Fix=AMD'
        }
    }
}

Describe 'Game Notes names the extra archives, the linked profile and a game that does not work' {
    BeforeEach {
        Mock Get-TpmRegisteredProfileCodes {
            $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($code in @('supp1', 'abc', 'abcELF2', 'lonely', 'broken1', 'partial1', 'working1')) { [void]$set.Add($code) }
            return ,$set
        }
        Mock Get-TpmGameNeedsLine { '' }
        Mock Get-EggmanGameData {
            @(
                [pscustomobject]@{ profile_name = 'supp1'; game_name = 'Supp Game'; setup_exe = 's.exe'; notes = ''; general_issues = ''
                    supp_archives = 'Supp Game (1.1)(2013)[PC][TP]; Supp Game Patch (2.0)[PC][TP]'; additional_archives = 'Supp Game Extra[PC][TP]' }
                [pscustomobject]@{ profile_name = 'abc'; game_name = 'After Burner (Lindbergh)'; setup_exe = 'a.elf'; notes = ''; general_issues = ''; linked_profile = 'abcELF2' }
                [pscustomobject]@{ profile_name = 'abcELF2'; game_name = 'After Burner (Elfloader2)'; setup_exe = 'a2.elf'; notes = ''; general_issues = ''; linked_profile = 'abc' }
                [pscustomobject]@{ profile_name = 'lonely'; game_name = 'Lonely'; setup_exe = 'l.exe'; notes = ''; general_issues = ''; linked_profile = 'notRegistered' }
                [pscustomobject]@{ profile_name = 'notRegistered'; game_name = 'Not Registered Game'; setup_exe = 'n.exe'; notes = '' }
                [pscustomobject]@{ profile_name = 'broken1'; game_name = 'Broken Game'; setup_exe = 'b.exe'; notes = ''; general_issues = ''; status = 'Broken' }
                [pscustomobject]@{ profile_name = 'partial1'; game_name = 'Partial Game'; setup_exe = 'p1.exe'; notes = ''; general_issues = ''; status = 'Partial' }
                [pscustomobject]@{ profile_name = 'working1'; game_name = 'Working Game'; setup_exe = 'w.exe'; notes = ''; general_issues = ''; status = 'Working' }
            )
        }
    }

    It 'lists every extra archive the guide names, split on the semicolons' {
        $notes = @(Get-GameSetupNotes -UserProfilesDir (Join-Path $TestDrive 'profiles'))
        $supp = $notes | Where-Object { $_.Code -eq 'supp1' }
        @($supp.ExtraArchives).Count | Should -Be 3
        $supp.ExtraArchives | Should -Contain 'Supp Game Patch (2.0)[PC][TP]'
        $supp.ExtraArchives | Should -Contain 'Supp Game Extra[PC][TP]'
    }

    It 'names the linked profile with its game name and says whether it is registered here' {
        $notes = @(Get-GameSetupNotes -UserProfilesDir (Join-Path $TestDrive 'profiles'))
        ($notes | Where-Object { $_.Code -eq 'abc' }).LinkedProfile | Should -Be 'After Burner (Elfloader2) (abcELF2), registered here'
        ($notes | Where-Object { $_.Code -eq 'lonely' }).LinkedProfile | Should -Be 'Not Registered Game (notRegistered), not registered here'
    }

    It 'writes both into the report in plain words and says nothing is downloaded' {
        $text = New-TpmGameNotesReportText -SetupNotes @(Get-GameSetupNotes -UserProfilesDir (Join-Path $TestDrive 'profiles'))
        $text | Should -Match 'Extra archives you need\. Use your own copy; none is downloaded for you:'
        $text | Should -Match 'Supp Game Patch \(2\.0\)\[PC\]\[TP\]'
        $text | Should -Match 'Linked profile \(the same game with another setup\): After Burner \(Elfloader2\) \(abcELF2\), registered here\.'
        $text | Should -Match 'not registered here\.'
    }

    It 'names a game the guide lists as broken or partly working and skips a working one' {
        $notes = @(Get-GameSetupNotes -UserProfilesDir (Join-Path $TestDrive 'profiles'))
        ($notes | Where-Object { $_.Code -eq 'broken1' }).GuideStatus | Should -Be 'Broken. It does not work yet.'
        ($notes | Where-Object { $_.Code -eq 'partial1' }).GuideStatus | Should -Be 'Partial. It works only in part.'
        @($notes | Where-Object { $_.Code -eq 'working1' }).Count | Should -Be 0
        $text = New-TpmGameNotesReportText -SetupNotes $notes
        $text | Should -Match 'Guide status: Broken\. It does not work yet\.'
    }

    It 'still skips a guide game that has nothing to show, and gives a registered game the guide does not list a plain entry' {
        Mock Get-EggmanGameData { @([pscustomobject]@{ profile_name = 'abc'; game_name = 'Plain'; setup_exe = 'p.exe'; notes = ''; general_issues = '' }) }
        $notes = @(Get-GameSetupNotes -UserProfilesDir (Join-Path $TestDrive 'profiles'))
        @($notes | Where-Object { $_.Code -eq 'abc' }).Count | Should -Be 0
        @($notes | Where-Object { -not $_.Generic }).Count | Should -Be 0
        @($notes | Where-Object { $_.Code -eq 'lonely' }).Count | Should -Be 1
    }
}
