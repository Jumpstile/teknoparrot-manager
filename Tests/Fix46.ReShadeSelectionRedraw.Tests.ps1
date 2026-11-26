#Requires -Module Pester
# FIX46: the ReShade profile chooser after a selection change made in the preview window or the terminal. The owner's Windows Terminal
# showed a black window with only the rewritten "Current selection" line, and (second report, S1) a "ReShade setup: Starting" progress
# row inside the chooser area with the profile list gone. Fake-only: a character-cell console surface drives the real chooser, the real
# input loop and the real in-place / full-redraw code. "WindowsTerminal" surfaces have buffer height == window height (rows scroll off
# the top, the window top is always 0); "Conhost" surfaces have a tall buffer and a moving window. No real console, no TeknoParrot, no
# network, no game folder. Each It names the product change that makes it fail.
# What this CANNOT prove: how a real Windows Terminal / ConPTY repaints; FIX46-RealConsoleProbe.ps1 (coordinator, real window) does.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX46 bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'fix46-functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    # No progress module in this file: the chooser must work without one, and the hold tests supply their own stand-ins.
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:DisplayVersion = 'v1.0 RC8'
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false
    $script:logPath = Join-Path $TestDrive 'fix46.log'
    $script:logWarnShown = $false

    function New-Fix46Surface {
        param([int]$Width = 110, [int]$Height = 30, [ValidateSet('WindowsTerminal', 'Conhost')][string]$Kind = 'WindowsTerminal', [int]$BufferHeight = 400)
        $rowsInBuffer = if ($Kind -eq 'WindowsTerminal') { $Height } else { [Math]::Max($Height, $BufferHeight) }
        $rows = New-Object 'string[]' $rowsInBuffer
        for ($i = 0; $i -lt $rowsInBuffer; $i++) { $rows[$i] = '' }
        return @{ Kind = $Kind; Width = $Width; Height = $Height; BufferHeight = $rowsInBuffer; Rows = $rows; History = (New-Object 'System.Collections.Generic.List[string]'); Row = 0; Col = 0; Top = 0 }
    }
    function Move-Fix46NextRow {
        $s = $script:surface
        $s.Col = 0
        if ($s.Row -lt $s.BufferHeight - 1) {
            $s.Row++
        } else {
            # the buffer is full: its top row leaves for the scrollback, exactly like a Windows Terminal viewport
            [void]$s.History.Add([string]$s.Rows[0])
            for ($i = 1; $i -lt $s.BufferHeight; $i++) { $s.Rows[$i - 1] = $s.Rows[$i] }
            $s.Rows[$s.BufferHeight - 1] = ''
        }
        if ($s.Row -gt $s.Top + $s.Height - 1) { $s.Top = $s.Row - $s.Height + 1 }
    }
    function Add-Fix46Text {
        param([AllowEmptyString()][string]$Text)
        $s = $script:surface
        foreach ($ch in $Text.ToCharArray()) {
            if ($ch -eq [char]13) { $s.Col = 0; continue }
            if ($ch -eq [char]10) { Move-Fix46NextRow; continue }
            if ($ch -eq [char]8) { if ($s.Col -gt 0) { $s.Col-- }; continue }
            if ($s.Col -ge $s.Width) { Move-Fix46NextRow }
            $line = ([string]$s.Rows[$s.Row]).PadRight($s.Width)
            $s.Rows[$s.Row] = $line.Substring(0, $s.Col) + [string]$ch + $line.Substring($s.Col + 1)
            $s.Col++
        }
    }
    function Get-Fix46Window {
        $s = $script:surface
        return @(for ($r = $s.Top; $r -lt $s.Top + $s.Height; $r++) { ([string]$s.Rows[$r]).TrimEnd() })
    }
    function Get-Fix46AllRows {
        $s = $script:surface
        return @(@($s.History | ForEach-Object { ([string]$_).TrimEnd() }) + @($s.Rows | ForEach-Object { ([string]$_).TrimEnd() }))
    }
    function Save-Fix46Snapshot {
        param([string]$Name)
        $s = $script:surface
        $script:snap[$Name] = [pscustomobject]@{
            Window = @(Get-Fix46Window); Top = $s.Top; CursorLeft = $s.Col; CursorRow = $s.Row
            AllRows = @(Get-Fix46AllRows); RowsUsed = ($s.History.Count + $s.Row)
        }
    }
    function Install-Fix46SurfaceMocks {
        Mock Write-TpmConsoleText { Add-Fix46Text -Text $Text }
        Mock Write-Host { Add-Fix46Text -Text ([string]$Object + $(if ($NoNewline) { '' } else { "`n" })) }
        Mock Get-TpmConsoleCursorPosition { [pscustomobject]@{ Left = $script:surface.Col; Top = $script:surface.Row } }
        Mock Set-TpmConsoleCursorPosition {
            $s = $script:surface
            if ($Left -lt 0 -or $Left -ge $s.Width -or $Top -lt 0 -or $Top -ge $s.BufferHeight) { throw 'cursor outside the console buffer' }
            $s.Col = $Left
            $s.Row = $Top
            if ($s.Row -lt $s.Top) { $s.Top = $s.Row } elseif ($s.Row -gt $s.Top + $s.Height - 1) { $s.Top = $s.Row - $s.Height + 1 }
        }
        Mock Get-TpmConsoleMetrics { $s = $script:surface; [pscustomobject]@{ Width = $s.Width; Left = 0; Top = $s.Top; Height = $s.Height; BufferWidth = $s.Width; BufferHeight = $s.BufferHeight } }
        Mock Read-TpmConsoleRowText {
            $s = $script:surface
            if ($Row -lt 0 -or $Row -ge $s.BufferHeight) { throw 'row outside the console buffer' }
            ([string]$s.Rows[$Row]).PadRight($Left + $Width).Substring($Left, $Width)
        }
        Mock Test-TpmConsoleInputRedirected { $false }
        Mock Start-Sleep {}
        Mock Write-Log {}
        # If the scripted keys run out the input loop falls back to Read-HostSafe; end the chooser cleanly and let AfterEach see it.
        Mock Read-HostSafe { $script:exhausted = $true; 'B' }
        Mock Get-TpmReShadeHdrGate { [pscustomobject]@{ State = 'HIDDEN'; Visible = $false; Enabled = $false; Reason = 'test'; Fingerprint = '' } }
        # FIX52 (#384): after a resize the chooser clears the window (like the menus) before it draws the whole screen again; this
        # models Clear-Host on the surface: every buffer row blank, cursor and window top at the origin.
        Mock Clear-TpmReShadeChooserScreen {
            $s = $script:surface
            for ($r = 0; $r -lt $s.BufferHeight; $r++) { $s.Rows[$r] = '' }
            $s.Row = 0; $s.Col = 0; $s.Top = 0
        }
    }
    # Steps: $null = idle poll, 'text' = typed characters, 'ENTER', 'BS' = backspace, scriptblock = run it (the preview window changes the
    # selection, something foreign happens to the screen, a snapshot is taken), then the input loop polls.
    function Set-Fix46Script {
        param([object[]]$Steps)
        $script:steps = New-Object 'System.Collections.Generic.Queue[object]'
        foreach ($step in $Steps) { $script:steps.Enqueue($step) }
        $script:pendingKeys = New-Object 'System.Collections.Generic.Queue[object]'
        Mock Test-TpmConsoleKeyAvailable {
            if ($script:pendingKeys.Count -gt 0) { return $true }
            if ($script:steps.Count -eq 0) { throw 'FIX46 console script exhausted' }
            $next = $script:steps.Dequeue()
            if ($next -is [scriptblock]) { & $next; return $false }
            if ($null -eq $next) { return $false }
            if ($next -eq 'ENTER') { $script:pendingKeys.Enqueue([pscustomobject]@{ Key = [ConsoleKey]::Enter; KeyChar = [char]13 }); return $true }
            if ($next -eq 'BS') { $script:pendingKeys.Enqueue([pscustomobject]@{ Key = [ConsoleKey]::Backspace; KeyChar = [char]8 }); return $true }
            foreach ($ch in ([string]$next).ToCharArray()) { $script:pendingKeys.Enqueue([pscustomobject]@{ Key = [ConsoleKey]::D1; KeyChar = $ch }) }
            return $true
        }
        Mock Read-TpmConsoleKey { $script:pendingKeys.Dequeue() }
    }
    function New-Fix46Session {
        $profiles = @(Get-TpmReShadeProfiles | Where-Object { -not $_.RequiresHdr })
        return [hashtable]::Synchronized(@{ Initialized = $true; Closed = $false; PreviewEnabled = $true; SelectedProfileId = 'Original'; Profiles = $profiles; ProfileSelector = $null; ProfileSelectorUpdating = $false; Refresh = { $true } })
    }
    # The bottom of a correct chooser screen, read from the window: the prompt on the cursor row, directly above it the Choose rows, above
    # them the Current selection line, and above that visible numbered profile rows with exactly one marker.
    function Assert-Fix46ChooserScreen {
        param($Snapshot, [string]$CurrentText, [string]$StarPattern, [string]$PromptText, [string[]]$ChooseRows)
        $window = @($Snapshot.Window)
        $promptIndex = [int]$Snapshot.CursorRow - [int]$Snapshot.Top
        $promptIndex | Should -BeGreaterOrEqual ($ChooseRows.Count + 6) -Because 'the prompt must have the menu above it inside the window'
        # PromptText is the prompt plus the typed text exactly as written ('  Choice: ' or '  Choice: 1'); rows are compared trimmed.
        $window[$promptIndex] | Should -BeExactly $PromptText.TrimEnd()
        $Snapshot.CursorLeft | Should -Be $PromptText.Length -Because 'typing continues right after the prompt and the typed text'
        for ($i = 0; $i -lt $ChooseRows.Count; $i++) {
            $window[$promptIndex - $ChooseRows.Count + $i] | Should -BeExactly $ChooseRows[$i]
        }
        $window[$promptIndex - $ChooseRows.Count - 1] | Should -BeExactly $CurrentText
        $above = @($window[0..($promptIndex - $ChooseRows.Count - 2)])
        @($above | Where-Object { $_ -match '^\s*\[\d+\] ' }).Count | Should -BeGreaterOrEqual 3 -Because 'the profile list must be visible while the prompt waits'
        $stars = @($above | Where-Object { $_ -match '^\s*\[\d+\] \*' })
        $stars.Count | Should -Be 1
        $stars[0] | Should -Match $StarPattern
        @($window | Where-Object { $_ -ne '' }).Count | Should -BeGreaterThan ([int]($window.Count / 2)) -Because 'the window is never left mostly blank'
        @($Snapshot.AllRows | Where-Object { $_ -match 'Preview selection changed' }).Count | Should -Be 0 -Because 'a full redraw, not a one-line announcement, replaces a failed in-place update'
    }
    # The arcade catalog (FIX46 owner decision, extended by FIX51): Original plus sixteen profiles, so the chooser offers [1-17]; the target of the preview
    # selection changes below is the last profile, [17] Black/White Point Adjustment [Levels].
    $script:Fix46Choose110 = @(
        '  Choose: [1-17] Select profile  [U] Use selected profile  [S] Custom preset  [N] Skip ReShade -- no changes',
        '          [R] Reopen preview  [B] Back  [D] Details'
    )
    $script:Fix46TargetId = 'Levels'
    $script:Fix46CurrentTarget = '  Current selection: Black/White Point Adjustment [Levels]'
    $script:Fix46StarTarget = '^\s*\[17\] \* Black/White Point Adjustment \[Levels\]$'
}

Describe 'FIX46 chooser screen after a selection change (fake console surface)' {
    BeforeEach {
        $script:exhausted = $false
        $script:snap = @{}
        $script:surface = New-Fix46Surface
        Install-Fix46SurfaceMocks
        $script:session = New-Fix46Session
    }
    AfterEach { $script:exhausted | Should -BeFalse -Because 'the scripted console must not run out of steps' }

    It 'updates the marker and Current selection in place on a <Kind> surface and the window still shows the list, Current selection, Choose rows and prompt' -ForEach @(
        @{ Kind = 'WindowsTerminal' }
        @{ Kind = 'Conhost' }
    ) {
        # Mutation: delete the marker write ('foreach ($edit in $edits) { & $writeAt ...') in Update-TpmReShadeTerminalSelectionInPlace ->
        # no marker on the selected profile. Mutation: make it return before writing the Current selection row -> the Current line still says Original.
        $script:surface = New-Fix46Surface -Kind $Kind
        Set-Fix46Script -Steps @($null, { Save-Fix46Snapshot 'Before' }, { $script:session['SelectedProfileId'] = $script:Fix46TargetId }, $null, { Save-Fix46Snapshot 'After' }, 'U', 'ENTER')
        $result = Read-TpmReShadeTerminalProfile -Profiles @($script:session['Profiles']) -DefaultProfileId 'Original' -PreviewSession $script:session
        Assert-Fix46ChooserScreen -Snapshot $script:snap['After'] -CurrentText $script:Fix46CurrentTarget -StarPattern $script:Fix46StarTarget -PromptText '  Choice: ' -ChooseRows $script:Fix46Choose110
        $script:snap['After'].RowsUsed | Should -Be $script:snap['Before'].RowsUsed -Because 'an in-place update prints no new rows'
        $result.SelectedProfile.ProfileId | Should -Be $script:Fix46TargetId
    }

    It 'redraws the whole chooser when the window no longer shows the recorded rows (the owner black screen), keeping the typed text' {
        # Reproduces the owner's black window: everything except the prompt row is gone when the preview selection arrives.
        # Mutation: remove the read-back checks before the write in Update-TpmReShadeTerminalSelectionInPlace (the pre-FIX46 code) -> it
        # writes only the Current selection line (and a marker) onto the blank window, which then holds two or three text rows.
        Set-Fix46Script -Steps @($null, '1', {
            $s = $script:surface
            for ($r = 0; $r -lt $s.BufferHeight; $r++) { if ($r -ne $s.Row) { $s.Rows[$r] = '' } }
        }, { $script:session['SelectedProfileId'] = $script:Fix46TargetId }, $null, { Save-Fix46Snapshot 'After' }, 'BS', 'U', 'ENTER')
        $result = Read-TpmReShadeTerminalProfile -Profiles @($script:session['Profiles']) -DefaultProfileId 'Original' -PreviewSession $script:session
        Assert-Fix46ChooserScreen -Snapshot $script:snap['After'] -CurrentText $script:Fix46CurrentTarget -StarPattern $script:Fix46StarTarget -PromptText '  Choice: 1' -ChooseRows $script:Fix46Choose110
        $result.SelectedProfile.ProfileId | Should -Be $script:Fix46TargetId
    }

    It 'redraws the whole chooser instead of writing onto the wrong rows when a foreign row sits between the Choose rows and the prompt (owner S1)' {
        # A progress row like the owner's "ReShade setup: Starting" bar is printed where the prompt was, and the prompt moves one row down,
        # so every row the layout computes from the prompt is one row off.
        # Mutation: remove the read-back checks (pre-FIX46 code) -> the Current selection text overwrites the first Choose row and the bar
        # row stays directly above the prompt.
        Set-Fix46Script -Steps @($null, {
            $s = $script:surface
            $s.Col = 0
            Add-Fix46Text ('ReShade setup: Starting |        >>>>>>>>>>>>>        |   0   in 6.1s (0.00/s)'.PadRight($s.Width - 1))
            Add-Fix46Text "`n"
            Add-Fix46Text '  Choice: '
        }, { $script:session['SelectedProfileId'] = $script:Fix46TargetId }, $null, { Save-Fix46Snapshot 'After' }, 'U', 'ENTER')
        $result = Read-TpmReShadeTerminalProfile -Profiles @($script:session['Profiles']) -DefaultProfileId 'Original' -PreviewSession $script:session
        Assert-Fix46ChooserScreen -Snapshot $script:snap['After'] -CurrentText $script:Fix46CurrentTarget -StarPattern $script:Fix46StarTarget -PromptText '  Choice: ' -ChooseRows $script:Fix46Choose110
        # the first, untouched block still carries its own Choose rows: nothing was written over them
        @($script:snap['After'].AllRows | Where-Object { $_ -ceq $script:Fix46Choose110[0] }).Count | Should -Be 2
        $result.SelectedProfile.ProfileId | Should -Be $script:Fix46TargetId
    }

    It 'redraws at the new width with the Choose options wrapped at option boundaries after the window was narrowed to 80 columns' {
        # Mutation: make Get-TpmReShadeChooseLines ignore TextWidth (one 128-character row) -> the row is cut inside "[N] Skip ReShade".
        Set-Fix46Script -Steps @($null, '1', { $script:surface.Width = 80; $script:session['SelectedProfileId'] = $script:Fix46TargetId }, $null, { Save-Fix46Snapshot 'After' }, 'BS', 'U', 'ENTER')
        $result = Read-TpmReShadeTerminalProfile -Profiles @($script:session['Profiles']) -DefaultProfileId 'Original' -PreviewSession $script:session
        $choose80 = @(
            '  Choose: [1-17] Select profile  [U] Use selected profile  [S] Custom preset',
            '          [N] Skip ReShade -- no changes  [R] Reopen preview  [B] Back',
            '          [D] Details'
        )
        Assert-Fix46ChooserScreen -Snapshot $script:snap['After'] -CurrentText $script:Fix46CurrentTarget -StarPattern $script:Fix46StarTarget -PromptText '  Choice: 1' -ChooseRows $choose80
        $result.SelectedProfile.ProfileId | Should -Be $script:Fix46TargetId
    }

    It 'redraws the whole chooser when the console buffer cannot be read back' {
        # Mutation: treat SCREEN_UNREADABLE as verified (continue to the write) -> the change is written in place unproven and only one
        # Current selection line ever exists.
        Mock Read-TpmConsoleRowText { throw 'this host cannot read its buffer' }
        Set-Fix46Script -Steps @($null, '1', { $script:session['SelectedProfileId'] = $script:Fix46TargetId }, $null, { Save-Fix46Snapshot 'After' }, 'BS', 'U', 'ENTER')
        $result = Read-TpmReShadeTerminalProfile -Profiles @($script:session['Profiles']) -DefaultProfileId 'Original' -PreviewSession $script:session
        Assert-Fix46ChooserScreen -Snapshot $script:snap['After'] -CurrentText $script:Fix46CurrentTarget -StarPattern $script:Fix46StarTarget -PromptText '  Choice: 1' -ChooseRows $script:Fix46Choose110
        @($script:snap['After'].AllRows | Where-Object { $_ -match '^\s*Current selection:' }).Count | Should -Be 2
        $result.SelectedProfile.ProfileId | Should -Be $script:Fix46TargetId
    }

    It 'shows the rough cost in the terminal menu and Details for a profile with effects and none for Original' {
        # Mutation: delete the cost line in the chooser's Details (D) output, or the ' Cost: ' suffix of the menu description row.
        $script:hostLines = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-Host { [void]$script:hostLines.Add([string]$Object) }
        Set-Fix46Script -Steps @('D', 'ENTER', 'B', 'ENTER')
        $null = Read-TpmReShadeTerminalProfile -Profiles @($script:session['Profiles']) -DefaultProfileId 'Original' -PreviewSession $script:session
        $lines = @($script:hostLines)
        $entryOf = {
            param([string]$Label)
            $start = -1
            for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -ceq ('    ' + $Label)) { $start = $i; break } }
            $start | Should -BeGreaterOrEqual 0 -Because ($Label + ' is listed in Details')
            $end = $lines.Count
            for ($i = $start + 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^    \S') { $end = $i; break } }
            return @($lines[$start..($end - 1)])
        }
        @(& $entryOf 'Classic Arcade CRT [CRT Lottes]' | Where-Object { $_ -ceq '      Cost: heavy (rough estimate, not measured).' }).Count | Should -Be 1
        @(& $entryOf 'Lightweight CRT [CRT-Pi]' | Where-Object { $_ -ceq '      Cost: light (rough estimate, not measured).' }).Count | Should -Be 1
        # Mutation: drop the cost line of a FIX51 CRT profile in the Details output (or give it another class) -> its cost line is missing or different.
        @(& $entryOf 'Curved Arcade Monitor [CRT-Geom]' | Where-Object { $_ -ceq '      Cost: medium (rough estimate, not measured).' }).Count | Should -Be 1
        @(& $entryOf 'Fast CRT [CRT-ZFast]' | Where-Object { $_ -ceq '      Cost: light (rough estimate, not measured).' }).Count | Should -Be 1
        @(& $entryOf 'Original' | Where-Object { $_ -match 'Cost:' }).Count | Should -Be 0
        $menu = @(Get-TpmReShadeTerminalMenuLines -Selectable @($script:session['Profiles']) -Selected $null | ForEach-Object { [string]$_.Text })
        $menu | Should -Contain '      Makes the game look like a classic arcade CRT screen: visible scanlines and a soft shadow-mask pattern. Cost: heavy.'
        $menu | Should -Contain '      No visual processing.'
    }
}

Describe 'FIX46 Choose rows fit the window and wrap only at option boundaries' {
    It 'keeps every option whole and every row inside the text width for windows 80 to 200 columns wide' {
        # Mutation: change the wrap test in Get-TpmReShadeChooseLines to never start a new row -> rows longer than the width.
        $options = @('[1-17] Select profile', '[U] Use selected profile', '[S] Custom preset', '[N] Skip ReShade -- no changes', '[R] Reopen preview', '[B] Back', '[D] Details')
        foreach ($width in @(80, 81, 90, 100, 109, 110, 111, 120, 128, 129, 140, 160, 200)) {
            $textWidth = $width - 1
            $rows = @(Get-TpmReShadeChooseLines -LastNumber 17 -TextWidth $textWidth | ForEach-Object { [string]$_.Text })
            foreach ($row in $rows) { $row.Length | Should -BeLessOrEqual $textWidth -Because "width $width" }
            $rows[0] | Should -Match '^  Choose: \[1-17\] Select profile' -Because "width $width"
            foreach ($row in @($rows | Select-Object -Skip 1)) { $row | Should -Match '^ {10}\[' -Because "continuation rows are indented under the first option (width $width)" }
            $found = @(foreach ($row in $rows) { @(($row.Trim() -replace '^Choose: ', '') -split '  ') })
            $found | Should -Be $options -Because "every option appears once, whole and in order (width $width)"
        }
        # A width that cannot be measured keeps the single legacy row.
        $single = @(Get-TpmReShadeChooseLines -LastNumber 17 -TextWidth 0)
        $single.Count | Should -Be 1
        $single[0].Text | Should -BeExactly '  Choose: [1-17] Select profile  [U] Use selected profile  [S] Custom preset  [N] Skip ReShade -- no changes  [R] Reopen preview  [B] Back  [D] Details'
        $single[0].Kind | Should -Be 'Choose'
    }
}

Describe 'FIX46 arcade catalog text: rough cost and honest preview notes' {
    It 'states the rough cost in the preview text of every profile with effects and none for Original' {
        # Mutation: delete the 'Performance cost' line in Get-TpmReShadeDescriptionText, or map HIGH to another word in Get-TpmReShadePerformanceBadge.
        $expected = @{ CurvedArcadeMonitor = 'medium'; ClassicCrt = 'heavy'; SharpApertureGrille = 'medium'; EasymodeCrt = 'medium'; HyllianCrt = 'medium'; CrtGlow = 'heavy'; DetailedCrt = 'heavy'; FastCrt = 'light'; LightweightCrt = 'light'; ScanlineGlow = 'medium'; BrightScanlines = 'light'; ArcadeGlow = 'medium'; Crisp3d = 'medium'; Crisp3dGlow = 'medium'; ContrastCurves = 'medium'; Levels = 'light' }
        foreach ($id in $expected.Keys) {
            $text = Get-TpmReShadeDescriptionText -ProfileDefinition (Get-TpmReShadeProfile -ProfileId $id)
            $text | Should -Match ('(?m)^Performance cost: {0} \(rough estimate, not measured\)\.\r?$' -f $expected[$id]) -Because $id
            $text | Should -Not -Match '\bTPM\b' -Because 'user-visible text names TeknoParrot Manager'
        }
        (Get-TpmReShadeDescriptionText -ProfileDefinition (Get-TpmReShadeProfile -ProfileId 'Original')) | Should -Not -Match 'Performance cost'
    }
    It 'says in the preview that the anti-aliasing part of the 3D profiles is not visible on the still picture' {
        # Mutation: drop the PreviewNote of Crisp3d or Crisp3dGlow -> the preview would imply the edge smoothing is shown.
        foreach ($id in @('Crisp3d', 'Crisp3dGlow')) {
            (Get-TpmReShadeDescriptionText -ProfileDefinition (Get-TpmReShadeProfile -ProfileId $id)) | Should -Match 'the still preview picture has none' -Because $id
        }
        (Get-TpmReShadeDescriptionText -ProfileDefinition (Get-TpmReShadeProfile -ProfileId 'ClassicCrt')) | Should -Not -Match 'still preview picture has none'
        # Mutation: copy the anti-aliasing preview note onto a CRT profile -> its preview text would claim an edge smoothing part that it does not have.
        foreach ($id in @('CurvedArcadeMonitor', 'SharpApertureGrille', 'EasymodeCrt', 'HyllianCrt', 'FastCrt')) {
            (Get-TpmReShadeDescriptionText -ProfileDefinition (Get-TpmReShadeProfile -ProfileId $id)) | Should -Not -Match 'still preview picture has none' -Because $id
        }
    }
    It 'logs a description that does not fit once per text, not on every selection and layout pass' {
        # Mutation: remove the DescriptionFitLogged check in Set-TpmReShadeDescriptionHeight -> the same text is logged twice.
        Mock Write-Log {}
        $label = [pscustomobject]@{ Text = ''; Height = 84; ClientSize = [pscustomobject]@{ Width = 300 }; Padding = [pscustomobject]@{ Horizontal = 0; Vertical = 0 }; Font = $null; DeviceDpi = 96; Parent = $null }
        $label | Add-Member -MemberType ScriptMethod -Name Refresh -Value {}
        $state = [hashtable]::Synchronized(@{ DescriptionLabel = $label; DescriptionToolTip = $null; Closed = $false })
        $measure = { param($t, $f, $w) [pscustomobject]@{ Height = 900 } }
        Set-TpmReShadeDescriptionLabel -Label $label -Text 'first description' -Measure $measure -State $state
        [void](Update-TpmReShadeDescriptionLayout -State $state -Measure $measure -Force)
        Set-TpmReShadeDescriptionLabel -Label $label -Text 'first description' -Measure $measure -State $state
        Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $msg -like '*may not fit*' }
        Set-TpmReShadeDescriptionLabel -Label $label -Text 'second description' -Measure $measure -State $state
        Should -Invoke Write-Log -Times 2 -Exactly -ParameterFilter { $msg -like '*may not fit*' }
        $state['DescriptionClipped'] | Should -BeTrue -Because 'the clipped state and tooltip handling are unchanged'
    }
}

Describe 'FIX46 the ReShade setup progress bar is held while the user chooses' {
    BeforeAll {
        # Stand-ins for the progress module: they record what the setup asks of the bar and keep the module's prompt-depth count.
        function Suspend-TpmProgressLine { [void]$script:holdEvents.Add('suspend'); $script:holdDepth++ }
        function Resume-TpmProgressLine { [void]$script:holdEvents.Add('resume'); $script:holdDepth-- }
        function Test-TpmProgressActive { return $true }
        function Test-TpmProgressGroupOwned { return $true }
        function Set-TpmProgressStage { param([string]$Stage, [switch]$StageOnly) [void]$script:holdEvents.Add('stage:' + $Stage) }
        function New-Fix46SetupFixture {
            $root = Join-Path $TestDrive ('setup-' + [guid]::NewGuid().ToString('N'))
            $profiles = Join-Path $root 'UserProfiles'
            [void](New-Item -ItemType Directory -Path $profiles -Force)
            $sourceDll = Join-Path $root 'ReShade64.dll'
            [IO.File]::WriteAllText($sourceDll, 'fixture')
            $script:TpmOwnedLayout = [pscustomobject]@{ Assets = (Join-Path $root 'Assets') }
            return [pscustomobject]@{ Root = $root; Profiles = $profiles; SourceDll = $sourceDll }
        }
    }
    BeforeEach {
        $script:holdEvents = New-Object 'System.Collections.Generic.List[string]'
        $script:holdDepth = 0
        $script:TpmReShadeProgressHeld = $false
        Mock Write-Host {}
        Mock Write-Log {}
        Mock Test-TpmNoReparsePath { $true }
        Mock Test-ReShadeDllSignature { [pscustomobject]@{ Status = 'Unavailable'; Signer = '' } }
        Mock Invoke-ReShadeUpdateIfAvailable { param($SourceDll, $InstalledVersion) [pscustomobject]@{ Updated = $false; SourceDll = $SourceDll } }
        Mock Read-TpmReShadeState { [pscustomobject]@{ Favorites = @() } }
        Mock Get-TpmReShadeHdrGate { [pscustomobject]@{ State = 'HIDDEN'; Visible = $false; Enabled = $false; Reason = 'test'; Fingerprint = '' } }
        Mock Write-TpmCompactExtractionProgress {}
        Mock Show-TpmReShadeProfileGalleryWindow { [void]$script:holdEvents.Add('gallery:' + $script:holdDepth); [pscustomobject]@{ Available = $false; SelectedProfile = $null; Closed = $true; Reason = 'fixture' } }
    }
    AfterEach { $script:TpmOwnedLayout = $null }

    It 'suspends the bar before the gallery and the chooser appear and resumes it exactly once when the user backs out' {
        # Mutation: delete Enter-TpmReShadeInteractiveProgressHold in Invoke-ReShadeSetupLegacy -> gallery and chooser run with the bar
        # live (depth 0). Mutation: delete the finally in Invoke-ReShadeSetup -> the bar stays suspended after the canceled setup.
        $fixture = New-Fix46SetupFixture
        Mock Read-TpmReShadeTerminalProfile { [void]$script:holdEvents.Add('chooser:' + $script:holdDepth); [pscustomobject]@{ Cancelled = $true; SelectedProfile = $null } }
        $null = Invoke-ReShadeSetup -UserProfilesDir $fixture.Profiles -SourceDll $fixture.SourceDll
        @($script:holdEvents) | Should -Be @('stage:Checking the ReShade files', 'suspend', 'gallery:1', 'chooser:1', 'resume')
        $script:holdDepth | Should -Be 0
    }

    It 'keeps the bar held through the confirmation menus and resumes it, with an installation stage, before the first game is checked' {
        # Mutation: delete (or move after the deployment loop) Exit-TpmReShadeInteractiveProgressHold -Stage in Invoke-ReShadeSetupLegacy
        # -> the first game path check runs while the bar is still suspended and no installation stage is set.
        $fixture = New-Fix46SetupFixture
        $script:fix46GameFile = Join-Path $fixture.Profiles 'Game1.xml'
        [IO.File]::WriteAllText($script:fix46GameFile, '<GameProfile><GamePath>C:\Fix46\Missing\Game.exe</GamePath></GameProfile>')
        Mock Read-TpmReShadeTerminalProfile { [void]$script:holdEvents.Add('chooser:' + $script:holdDepth); [pscustomobject]@{ Cancelled = $false; SelectedProfile = (Get-TpmReShadeProfile -ProfileId 'Original'); PreviewSession = $null } }
        Mock Select-RegisteredGamesInteractive { [void]$script:holdEvents.Add('games:' + $script:holdDepth); @(Get-Item -LiteralPath $script:fix46GameFile) }
        Mock Get-TpmReShadeApplyPreflight { [void]$script:holdEvents.Add('preflight:' + $script:holdDepth); [pscustomobject]@{ Ready = 1; Protected = 0; MissingPath = 0; Unsafe = 0; Failed = 0 } }
        Mock Get-TpmReShadeChooserOptions { [pscustomobject]@{ Restore = [pscustomobject]@{ Found = $false; Valid = $false }; Remembered = [pscustomobject]@{ Found = $false; Valid = $false } } }
        Mock Test-TpmGameMutationPath { [void]$script:holdEvents.Add('path-check:' + $script:holdDepth); [pscustomobject]@{ Valid = $false; ReasonCode = 'GAME_PATH_MISSING'; Reason = 'fixture' } }
        Mock Install-TpmReShadeProfileDeployment { throw 'no game may be changed in this test' }
        # Only the hold is under test here; the result summary after the skipped game is covered elsewhere.
        try { $null = Invoke-ReShadeSetup -UserProfilesDir $fixture.Profiles -SourceDll $fixture.SourceDll } catch { Write-Verbose ('setup ended with: ' + $_.Exception.Message) }
        $events = @($script:holdEvents)
        @($events[0..3]) | Should -Be @('stage:Checking the ReShade files', 'suspend', 'gallery:1', 'chooser:1')
        $events | Should -Contain 'games:1'
        $events | Should -Contain 'preflight:1'
        $stageAt = [Array]::IndexOf($events, 'stage:Installing the selected profile')
        $resumeAt = [Array]::IndexOf($events, 'resume')
        $stageAt | Should -BeGreaterThan ([Array]::IndexOf($events, 'preflight:1'))
        $resumeAt | Should -Be ($stageAt + 1)
        [Array]::IndexOf($events, 'path-check:0') | Should -BeGreaterThan $resumeAt
        $events | Should -Not -Contain 'path-check:1'
        @($events | Where-Object { $_ -eq 'resume' }).Count | Should -Be 1
        $script:holdDepth | Should -Be 0
    }
}
