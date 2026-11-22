#Requires -Module Pester

# GitHub issue 429: "Use my bezel folder". The user points TPM at a folder of bezel images they already have; TPM matches them to
# the registered games, shows a preview, and only after approval copies the chosen image to <game folder>\reshade-shaders\Textures\bezel.png.
# These tests use fake games, fake bezels and TestDrive folders only. They prove what a user sees or loses: the right bezel is picked,
# a different sequel is never picked quietly, a bezel the user placed by hand is kept, a game without ReShade or in a shared folder is
# left alone, and Undo puts the user's own file back.
# What they CANNOT prove: that a real game shows the bezel (needs a real game; see docs\RC9-OWNER-TEST-PLAN.md), or how well the
# matcher does on a real bezel collection.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX429 tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $functionFile = Join-Path $TestDrive 'tpm-fix429-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    # The two thresholds the production script sets at its top level; the bezel matcher reuses them.
    $FuzzyAutoThreshold = 0.72
    $FuzzyTieMargin = 0.1

    function New-F429Png { param([string]$Path, [string]$Tag = 'x')
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($Path))
        [System.IO.File]::WriteAllBytes($Path, ([byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A) + [System.Text.Encoding]::ASCII.GetBytes($Tag)))
    }
    # A registered game: a profile XML plus a fake exe. ReShade is "set up" when a dxgi.dll and ReShade.ini sit beside the exe.
    function New-F429Game { param([string]$Root, [string]$Code, [string]$Title, [switch]$ReShade, [string]$Folder = '')
        $dir = if ($Folder) { $Folder } else { Join-Path $Root ('games\' + $Code) }
        [void][System.IO.Directory]::CreateDirectory($dir)
        [System.IO.File]::WriteAllText((Join-Path $dir 'game.exe'), 'not a real exe')
        if ($ReShade) { [System.IO.File]::WriteAllText((Join-Path $dir 'dxgi.dll'), 'dll'); [System.IO.File]::WriteAllText((Join-Path $dir 'ReShade.ini'), 'ini') }
        $profiles = Join-Path $Root 'UserProfiles'
        [void][System.IO.Directory]::CreateDirectory($profiles)
        [System.IO.File]::WriteAllText((Join-Path $profiles ($Code + '.xml')), ('<GameProfile><GameNameInternal>{0}</GameNameInternal><GamePath>{1}</GamePath><EmulatorType>TeknoParrot</EmulatorType></GameProfile>' -f $Title, (Join-Path $dir 'game.exe')))
        return $dir
    }
    function Get-F429Plan { param([string]$Root, [string]$StateRoot)
        $found = Find-TpmBezelFiles -Folder (Join-Path $Root 'bezels')
        $list = Get-TpmBezelGames -UserProfilesDir (Join-Path $Root 'UserProfiles')
        $cand = Get-TpmBezelCandidates -Games $list.Games -Bezels $found.Files
        $state = Read-TpmBezelState -StateRoot $StateRoot
        return [pscustomobject]@{ Rows = @(New-TpmBezelPlanRows -Games $list.Games -Candidates $cand -State $state); State = $state; Found = $found }
    }
}

Describe 'Use my bezel folder (issue 429)' {
    BeforeEach {
        Mock Write-Log {}
        Mock Write-TpmCompactExtractionProgress {}
        Mock Get-TpmRegisteredProfileFilesWithDiscoveryProgress { Get-ChildItem -LiteralPath $UserProfilesDir -Filter '*.xml' -File }
        $script:root = Join-Path $TestDrive ('f429-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:stateRoot = Join-Path $script:root 'state'
    }

    It 'matches messy bezel names to the right game, with a confidence level and a plain "no bezel" for the rest' {
        # Mutation: skip the noise strip (underscores, the word bezel) -> the House of the Dead 4 bezel scores below High.
        $null = New-F429Game -Root $script:root -Code 'HOTD4' -Title 'The House of the Dead 4' -ReShade
        $null = New-F429Game -Root $script:root -Code 'Raiden4' -Title 'Raiden IV' -ReShade
        $null = New-F429Game -Root $script:root -Code 'Other' -Title 'Totally Different Game' -ReShade
        New-F429Png (Join-Path $script:root 'bezels\House_of_the_Dead_4_(USA)_bezel.png')
        New-F429Png (Join-Path $script:root 'bezels\sub\Raiden IV [v1.03] overlay.png')
        $plan = Get-F429Plan -Root $script:root -StateRoot $script:stateRoot
        $hotd = $plan.Rows | Where-Object { $_.Game.ProfileId -eq 'HOTD4' }
        $hotd.Chosen.Name | Should -Be 'House_of_the_Dead_4_(USA)_bezel.png'
        $hotd.Confidence | Should -BeIn @('High', 'Medium')
        $hotd.Status | Should -Be 'Apply'
        ($plan.Rows | Where-Object { $_.Game.ProfileId -eq 'Raiden4' }).Chosen.Name | Should -Be 'sub\Raiden IV [v1.03] overlay.png'
        $other = $plan.Rows | Where-Object { $_.Game.ProfileId -eq 'Other' }
        $other.Status | Should -Be 'NoBezel'
        $other.Chosen | Should -BeNullOrEmpty
    }

    It 'never quietly gives a game the bezel of a different sequel' {
        # Mutation: drop the sequel-number check -> "House of the Dead 3" scores about 0.95 for the 4 and is applied.
        $null = New-F429Game -Root $script:root -Code 'HOTD4' -Title 'The House of the Dead 4' -ReShade
        New-F429Png (Join-Path $script:root 'bezels\The House of the Dead 3.png')
        $row = (Get-F429Plan -Root $script:root -StateRoot $script:stateRoot).Rows[0]
        $row.Status | Should -Be 'NeedsChoice'
        $row.Chosen | Should -BeNullOrEmpty
    }

    It 'ignores files that only end in .png, and leaves games without ReShade or in a shared folder alone' {
        # Mutation: apply to a game with no ReShade, or to a shared folder -> a bezel that nobody can see, or one that shows on other games.
        $null = New-F429Game -Root $script:root -Code 'NoReShade' -Title 'Aliens Extermination'
        $shared = Join-Path $script:root 'shared'
        $null = New-F429Game -Root $script:root -Code 'SharedA' -Title 'Terminator Salvation' -ReShade -Folder $shared
        $null = New-F429Game -Root $script:root -Code 'SharedB' -Title 'Walking Dead' -ReShade -Folder $shared
        New-F429Png (Join-Path $script:root 'bezels\Aliens Extermination.png')
        New-F429Png (Join-Path $script:root 'bezels\Terminator Salvation.png')
        [System.IO.File]::WriteAllText((Join-Path $script:root 'bezels\Walking Dead.png'), 'this is not a PNG')
        [System.IO.File]::WriteAllText((Join-Path $script:root 'bezels\Aliens Extermination - Bezel.jpg'), 'a jpg is not used either')
        $plan = Get-F429Plan -Root $script:root -StateRoot $script:stateRoot
        $plan.Found.NotPng | Should -Be 2
        ($plan.Rows | Where-Object { $_.Game.ProfileId -eq 'NoReShade' }).Status | Should -Be 'NeedsReShade'
        ($plan.Rows | Where-Object { $_.Game.ProfileId -eq 'SharedA' }).Status | Should -Be 'Shared'
        $result = Invoke-TpmBezelApply -Rows $plan.Rows -StateRoot $script:stateRoot
        $result.Outcome | Should -Be 'NO_OP'
        Test-Path -LiteralPath (Join-Path $script:root 'games\NoReShade\reshade-shaders') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $shared 'reshade-shaders') | Should -BeFalse
    }

    It 'understands short arcade names exactly, and never matches one by similarity or to the wrong sequel' {
        # Mutation: compare the profile code by similarity -> daytona.png is also given to Daytona3; a number in the title ("II") vetoes soulclb2.png.
        $null = New-F429Game -Root $script:root -Code 'daytona' -Title 'Daytona USA (Revision A)' -ReShade
        $null = New-F429Game -Root $script:root -Code 'Daytona3' -Title 'Daytona Championship USA' -ReShade
        $null = New-F429Game -Root $script:root -Code 'teknonaomi_dybb99' -Title "Dynamite Baseball '99 (Japan, Rev B)" -ReShade
        $null = New-F429Game -Root $script:root -Code 'soulclb2' -Title 'Soul Calibur II Arcade Edition' -ReShade
        foreach ($n in @('daytona', 'dybb99', 'soulclb2')) { New-F429Png (Join-Path $script:root ('bezels\' + $n + '.png')) }
        $rows = (Get-F429Plan -Root $script:root -StateRoot $script:stateRoot).Rows
        foreach ($pair in @(@('daytona', 'daytona.png'), @('teknonaomi_dybb99', 'dybb99.png'), @('soulclb2', 'soulclb2.png'))) {
            $row = $rows | Where-Object { $_.Game.ProfileId -eq $pair[0] }
            $row.Chosen.Name | Should -Be $pair[1]
            $row.Status | Should -Be 'Apply'
        }
        ($rows | Where-Object { $_.Game.ProfileId -eq 'Daytona3' }).Chosen | Should -BeNullOrEmpty
    }

    It 'does not call it a sure match when two bezels fit one game equally well, and the preview can name the other one' {
        # Mutation: ignore the tie -> a coin flip between the two files is reported as High.
        $null = New-F429Game -Root $script:root -Code 'prdgp03' -Title 'Pride GP 2003' -ReShade
        New-F429Png (Join-Path $script:root 'bezels\Pride GP 2003.png')
        New-F429Png (Join-Path $script:root 'bezels\prdgp03.png')
        $row = (Get-F429Plan -Root $script:root -StateRoot $script:stateRoot).Rows[0]
        $row.Confidence | Should -Be 'Medium'
        $row.Chosen | Should -Not -BeNullOrEmpty
        $row.Ranked.Count | Should -Be 2
    }

    It 'takes the game name from TeknoParrot metadata when the profile has no name of its own' {
        # Mutation: use the profile code as the name -> "Time Crisis 4.png" finds nothing for a profile named abc.
        $null = New-F429Game -Root $script:root -Code 'abc' -Title '' -ReShade
        [void][System.IO.Directory]::CreateDirectory((Join-Path $script:root 'Metadata'))
        [System.IO.File]::WriteAllText((Join-Path $script:root 'Metadata\abc.json'), '{"game_name":"Time Crisis 4"}')
        New-F429Png (Join-Path $script:root 'bezels\Time Crisis 4.png')
        $row = (Get-F429Plan -Root $script:root -StateRoot $script:stateRoot).Rows[0]
        $row.Chosen.Name | Should -Be 'Time Crisis 4.png'
        $row.Game.Name | Should -Be 'Time Crisis 4'
    }

    It 'copies the bezel to the game, and Undo removes it again' {
        # Mutation: record nothing for undo -> the copied bezel stays after Undo.
        $dir = New-F429Game -Root $script:root -Code 'HOTD4' -Title 'The House of the Dead 4' -ReShade
        New-F429Png (Join-Path $script:root 'bezels\The House of the Dead 4.png') 'mine'
        $plan = Get-F429Plan -Root $script:root -StateRoot $script:stateRoot
        $result = Invoke-TpmBezelApply -Rows $plan.Rows -StateRoot $script:stateRoot
        $result.Outcome | Should -Be 'SUCCEEDED'
        $dest = Join-Path $dir 'reshade-shaders\Textures\bezel.png'
        (Get-FileHash -LiteralPath $dest).Hash | Should -Be (Get-FileHash -LiteralPath (Join-Path $script:root 'bezels\The House of the Dead 4.png')).Hash
        (Get-F429Plan -Root $script:root -StateRoot $script:stateRoot).Rows[0].Status | Should -Be 'Same'
        $undo = Invoke-TpmBezelUndo -StateRoot $script:stateRoot
        $undo.Outcome | Should -BeIn @('SUCCEEDED', 'NO_OP')
        Test-Path -LiteralPath $dest | Should -BeFalse
        (Read-TpmBezelState -StateRoot $script:stateRoot).Applied.Count | Should -Be 0
    }

    It 'keeps a bezel the user placed by hand unless they choose to replace it, and Undo puts that file back' {
        # Mutation: replace the user's file without asking, or without saving a copy -> their own bezel is lost for good.
        $dir = New-F429Game -Root $script:root -Code 'HOTD4' -Title 'The House of the Dead 4' -ReShade
        $dest = Join-Path $dir 'reshade-shaders\Textures\bezel.png'
        New-F429Png $dest 'users-own'
        $original = (Get-FileHash -LiteralPath $dest).Hash
        New-F429Png (Join-Path $script:root 'bezels\The House of the Dead 4.png') 'from-folder'
        $plan = Get-F429Plan -Root $script:root -StateRoot $script:stateRoot
        $plan.Rows[0].Status | Should -Be 'UserBezel'
        (Invoke-TpmBezelApply -Rows $plan.Rows -StateRoot $script:stateRoot).Outcome | Should -Be 'NO_OP'
        (Get-FileHash -LiteralPath $dest).Hash | Should -Be $original
        (Invoke-TpmBezelApply -Rows $plan.Rows -ReplaceUserBezels -StateRoot $script:stateRoot).Outcome | Should -Be 'SUCCEEDED'
        (Get-FileHash -LiteralPath $dest).Hash | Should -Not -Be $original
        $null = Invoke-TpmBezelUndo -StateRoot $script:stateRoot
        (Get-FileHash -LiteralPath $dest).Hash | Should -Be $original
    }

    It 'leaves a bezel alone on Undo when the user changed it after TPM copied it' {
        # Mutation: undo deletes whatever is there -> the user's newer file is lost.
        $dir = New-F429Game -Root $script:root -Code 'HOTD4' -Title 'The House of the Dead 4' -ReShade
        New-F429Png (Join-Path $script:root 'bezels\The House of the Dead 4.png') 'from-folder'
        $null = Invoke-TpmBezelApply -Rows (Get-F429Plan -Root $script:root -StateRoot $script:stateRoot).Rows -StateRoot $script:stateRoot
        $dest = Join-Path $dir 'reshade-shaders\Textures\bezel.png'
        New-F429Png $dest 'changed-later'
        $undo = Invoke-TpmBezelUndo -StateRoot $script:stateRoot
        $undo.LeftAlone | Should -Contain 'HOTD4'
        Test-Path -LiteralPath $dest | Should -BeTrue
    }

    It 'remembers a pick, including "no bezel for this game", so the game is not asked about again' {
        # Mutation: do not read the saved picks -> a game the user said "none" for gets a bezel anyway.
        $null = New-F429Game -Root $script:root -Code 'HOTD4' -Title 'The House of the Dead 4' -ReShade
        New-F429Png (Join-Path $script:root 'bezels\The House of the Dead 4.png')
        $state = Read-TpmBezelState -StateRoot $script:stateRoot
        $state.Picks['HOTD4'] = ''
        Write-TpmBezelState -State $state -StateRoot $script:stateRoot
        $row = (Get-F429Plan -Root $script:root -StateRoot $script:stateRoot).Rows[0]
        $row.Status | Should -Be 'Skipped'
        $row.Chosen | Should -BeNullOrEmpty
    }

    It 'writes nothing until the user approves the preview, then copies after A' {
        # Mutation: apply before the approval prompt -> the file exists after answering Cancel.
        $dir = New-F429Game -Root $script:root -Code 'HOTD4' -Title 'The House of the Dead 4' -ReShade
        New-F429Png (Join-Path $script:root 'bezels\The House of the Dead 4.png')
        $dest = Join-Path $dir 'reshade-shaders\Textures\bezel.png'
        Mock Write-TpmText {}
        Mock Read-PathWithBrowse { return (Join-Path $script:root 'bezels') }
        $script:answers = New-Object System.Collections.Generic.Queue[string]
        Mock Read-TpmChoice { return $script:answers.Dequeue() }
        foreach ($a in @('F', 'C')) { $script:answers.Enqueue($a) }
        Invoke-TpmBezelSetup -UserProfilesDir (Join-Path $script:root 'UserProfiles') -StateRoot $script:stateRoot
        Test-Path -LiteralPath $dest | Should -BeFalse
        foreach ($a in @('F', 'A')) { $script:answers.Enqueue($a) }
        Invoke-TpmBezelSetup -UserProfilesDir (Join-Path $script:root 'UserProfiles') -StateRoot $script:stateRoot
        Test-Path -LiteralPath $dest | Should -BeTrue
    }
}
