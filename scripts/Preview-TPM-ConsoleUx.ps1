#Requires -Version 5.1

param(
    [ValidateSet('ReferenceNeon', 'BlockMarquee', 'ArcadeFrame', 'CenteredTerminal', 'CompactReadable', 'All')]
    [string]$Variant = 'ReferenceNeon',
    [switch]$AttemptMaximize,
    [switch]$Diagnostics,
    [switch]$Watch,
    [int]$RefreshMs = 250,
    [switch]$List
)

$ErrorActionPreference = 'Stop'

$script:DisplayVersion = 'v1.0 RC8'

function Get-ViewportInfo {
    $rawWindowWidth = $null
    $rawWindowHeight = $null
    $rawBufferWidth = $null
    $rawBufferHeight = $null
    $consoleWidth = $null
    $consoleHeight = $null
    $hostName = $null
    $rawUiType = $null

    try { $hostName = $Host.Name } catch {}
    try { $rawUiType = $Host.UI.RawUI.GetType().FullName } catch {}
    try { $rawWindowWidth = [int]$Host.UI.RawUI.WindowSize.Width } catch {}
    try { $rawWindowHeight = [int]$Host.UI.RawUI.WindowSize.Height } catch {}
    try { $rawBufferWidth = [int]$Host.UI.RawUI.BufferSize.Width } catch {}
    try { $rawBufferHeight = [int]$Host.UI.RawUI.BufferSize.Height } catch {}
    try { $consoleWidth = [int][Console]::WindowWidth } catch {}
    try { $consoleHeight = [int][Console]::WindowHeight } catch {}

    $width = 80
    $height = 25
    if ($rawWindowWidth -gt 0) { $width = $rawWindowWidth }
    if ($rawWindowHeight -gt 0) { $height = $rawWindowHeight }
    if ($consoleWidth -gt 0) { $width = $consoleWidth }
    if ($consoleHeight -gt 0) { $height = $consoleHeight }

    return [pscustomobject]@{
        HostName = $hostName
        RawUiType = $rawUiType
        RawWindowWidth = $rawWindowWidth
        RawWindowHeight = $rawWindowHeight
        RawBufferWidth = $rawBufferWidth
        RawBufferHeight = $rawBufferHeight
        ConsoleWidth = $consoleWidth
        ConsoleHeight = $consoleHeight
        Width = $width
        Height = $height
    }
}

function Invoke-PrototypeMaximize {
    $before = Get-ViewportInfo
    $attempted = $true
    $succeeded = $false
    $skipped = $false
    $message = ''

    try {
        $rawUi = $Host.UI.RawUI
        $max = $rawUi.MaxPhysicalWindowSize
        if (-not $max -or $max.Width -le 0 -or $max.Height -le 0) {
            $skipped = $true
            $message = 'MaxPhysicalWindowSize unavailable.'
        } else {
            $rawUi.BufferSize = New-Object -TypeName System.Management.Automation.Host.Size -ArgumentList @(
                [Math]::Max($rawUi.BufferSize.Width, $max.Width),
                [Math]::Max($rawUi.BufferSize.Height, $max.Height)
            )
            $rawUi.WindowSize = New-Object -TypeName System.Management.Automation.Host.Size -ArgumentList @($max.Width, $max.Height)
            Start-Sleep -Milliseconds 150
            $afterProbe = Get-ViewportInfo
            $succeeded = ($afterProbe.Width -ge ([Math]::Max(1, $max.Width - 2)))
            if ($succeeded) {
                $message = ("requested {0}x{1}; measured {2}x{3}" -f $max.Width, $max.Height, $afterProbe.Width, $afterProbe.Height)
            } else {
                $message = ("requested {0}x{1}; measured {2}x{3}" -f $max.Width, $max.Height, $afterProbe.Width, $afterProbe.Height)
            }
        }
    } catch {
        $skipped = $true
        $message = $_.Exception.Message
    }

    $after = Get-ViewportInfo
    return [pscustomobject]@{
        Attempted = $attempted
        Succeeded = $succeeded
        Skipped = $skipped
        Message = $message
        BeforeWidth = $before.Width
        BeforeHeight = $before.Height
        AfterWidth = $after.Width
        AfterHeight = $after.Height
    }
}

function Write-Centered {
    param(
        [string]$Text,
        [int]$Width,
        [string]$Color = 'White'
    )
    $pad = [Math]::Max(0, [Math]::Floor(($Width - $Text.Length) / 2))
    Write-Host ((' ' * $pad) + $Text) -ForegroundColor $Color
}

function Write-Rule {
    param(
        [int]$Width,
        [string]$Color = 'DarkCyan',
        [string]$Char = '-'
    )
    Write-Host ($Char * [Math]::Max(1, $Width)) -ForegroundColor $Color
}

function Write-BoxLine {
    param(
        [string]$Text,
        [int]$Width,
        [string]$Color = 'Cyan',
        [string]$TextColor = 'Cyan'
    )
    $inner = [Math]::Max(2, $Width - 2)
    $value = $Text
    if ($value.Length -gt $inner) { $value = $value.Substring(0, $inner) }
    $padLeft = [Math]::Max(0, [Math]::Floor(($inner - $value.Length) / 2))
    $padRight = [Math]::Max(0, $inner - $value.Length - $padLeft)
    Write-Host '|' -ForegroundColor $Color -NoNewline
    Write-Host ((' ' * $padLeft) + $value + (' ' * $padRight)) -ForegroundColor $TextColor -NoNewline
    Write-Host '|' -ForegroundColor $Color
}

function Split-PreviewText {
    param(
        [string]$Text,
        [int]$Width
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $Width = [Math]::Max(20, $Width)
    $words = @($Text -split '\s+' | Where-Object { $_ })
    $lines = New-Object System.Collections.Generic.List[string]
    $current = ''
    foreach ($word in $words) {
        if ($current.Length -eq 0) {
            $current = $word
        } elseif (($current.Length + 1 + $word.Length) -le $Width) {
            $current = "$current $word"
        } else {
            [void]$lines.Add($current)
            $current = $word
        }
    }
    if ($current.Length -gt 0) { [void]$lines.Add($current) }
    return $lines.ToArray()
}

function Get-PreviewSections {
    return @(
        [pscustomobject]@{
            Header = 'LIBRARY MANAGEMENT'
            Color = 'Cyan'
            Items = @(
                [pscustomobject]@{ Number = 1; Label = 'AutoSync'; Desc = 'Extract ZIPs (NAS or local) to a local folder, register games, repair metadata, and preserve backups automatically.' }
                [pscustomobject]@{ Number = 2; Label = 'Register Existing Games'; Desc = 'Register games that are already extracted without copying or moving any files.' }
                [pscustomobject]@{ Number = 3; Label = 'Propagate Controls'; Desc = 'Re-copy control bindings from reference games to other compatible games without running AutoSync.' }
            )
        }
        [pscustomobject]@{
            Header = 'GAME ENHANCEMENTS (OPTIONAL)'
            Color = 'Green'
            Items = @(
                [pscustomobject]@{ Number = 4; Label = 'Crosshair Setup'; Desc = 'Pick and deploy custom crosshairs to registered lightgun games.' }
                [pscustomobject]@{ Number = 5; Label = 'ReShade Setup'; Desc = 'Add visual enhancements such as sharper image, better colours, scanlines, and borders.' }
                [pscustomobject]@{ Number = 6; Label = 'dgVoodoo2 Setup'; Desc = 'Fix old DX8, DirectDraw, and Glide games that crash to black screens.' }
                [pscustomobject]@{ Number = 7; Label = 'GPU Fix Setup'; Desc = 'Auto-detect AMD, NVIDIA, or Intel GPU and apply matching compatibility fixes.' }
                [pscustomobject]@{ Number = 8; Label = 'Force Feedback Setup'; Desc = 'Wheel and stick rumble plus force feedback through TeknoParrot or a third-party plugin.' }
                [pscustomobject]@{ Number = 9; Label = 'BepInEx Update Check'; Desc = 'Check games with BepInEx already installed and offer a safe update when appropriate.' }
            )
        }
        [pscustomobject]@{
            Header = 'MAINTENANCE & RECOVERY'
            Color = 'Magenta'
            Items = @(
                [pscustomobject]@{ Number = 10; Label = 'Library Health Check'; Desc = 'Read-only status for registrations, broken paths, coverage, and installed enhancements.' }
                [pscustomobject]@{ Number = 11; Label = 'Restore Backup'; Desc = 'Roll UserProfiles, LaunchBox files, or Postgres databases back to a previous backup.' }
                [pscustomobject]@{ Number = 12; Label = 'Postgres Setup'; Desc = 'Install and configure local PostgreSQL for selected Incredible Technologies games.' }
            )
        }
        [pscustomobject]@{
            Header = 'APPLICATION'
            Color = 'Yellow'
            Items = @(
                [pscustomobject]@{ Number = 13; Label = 'Check For Updates'; Desc = 'Manual backup-first check against the latest GitHub release.' }
                [pscustomobject]@{ Number = 14; Label = 'Exit'; Desc = 'Exit TeknoParrot Manager.' }
            )
        }
    )
}

function Get-WordmarkReference {
    return @(
        '  _______     __            ____                       __     __  ___'
        ' /_  __/__   / /__ ___  ___/ __ \____ _ ___________   / /_   /  |/  /____ _ ____  ____ _ ____ _ ___  _____'
        '  / / / _ \ / //_// _ \/ _ \ /_/ / __ `// ___// ___/  / __/  / /|_/ // __ `// __ \/ __ `// __ `// _ \/ ___/'
        ' / / /  __// ,<  /  __/  __/ ____/ /_/ // /   / /     / /_   / /  / // /_/ // / / / /_/ // /_/ //  __/ /'
        '/_/  \___//_/|_| \___/\___/_/    \__,_//_/   /_/      \__/  /_/  /_/ \__,_//_/ /_/\__,_/ \__, / \___/_/'
        '                                                                                         /____/'
    )
}

function Get-WordmarkBlock {
    return @(
        'TTTTTTT EEEEE K   K N   N  OOO  PPPP   AAA  RRRR  RRRR   OOO  TTTTTTT     M   M  AAA  N   N  AAA   GGG  EEEEE RRRR'
        '   T    E     K  K  NN  N O   O P   P A   A R   R R   R O   O    T        MM MM A   A NN  N A   A G     E     R   R'
        '   T    EEEE  KKK   N N N O   O PPPP  AAAAA RRRR  RRRR  O   O    T        M M M AAAAA N N N AAAAA G  GG EEEE  RRRR'
        '   T    E     K  K  N  NN O   O P     A   A R  R  R  R  O   O    T        M   M A   A N  NN A   A G   G E     R  R'
        '   T    EEEEE K   K N   N  OOO  P     A   A R   R R   R  OOO     T        M   M A   A N   N A   A  GGG  EEEEE R   R'
    )
}

function Get-WordmarkCompact {
    return @(
        ' _______        __             ____                       __     __  ___'
        '/_  __/__  ____/ /__ ___  ___ / __ \____ _ ___________   / /_   /  |/  /____ _ ____  ____ _ ____ _ _____'
        ' / / / _ \/ __  //_// _ \/ _ \ /_/ / __ `// ___// ___/  / __/  / /|_/ // __ `// __ \/ __ `// __ `// ___/'
        '/_/  \___/\__,_//_/ \___/\___/ .___/\__,_//_/   /_/      \__/  /_/  /_/ \__,_//_/ /_/\__,_/ \__, //_/    '
        '                            /_/                                                          /____/        '
    )
}

function Get-WordmarkPlate {
    return @(
        ' ####### ####### #    # #    #  ####  ######  ####  ######  ####   ####  #######'
        '    #    #       #   #  ##   # #    # #     # #    # #     # #    #    #    #   '
        '    #    #####   ####   # #  # #    # ######  ###### ######  #    #    #    #   '
        '    #    #       #  #   #  # # #    # #       #    # #   #   #    #    #    #   '
        '    #    ####### #    # #    #  ####  #       #    # #    #  ####  ####     #   '
        '                         M  A  N  A  G  E  R'
    )
}

function Write-Wordmark {
    param(
        [string[]]$Lines,
        [int]$Width,
        [string]$Color = 'Cyan'
    )
    foreach ($line in $Lines) {
        Write-Centered -Text $line -Width $Width -Color $Color
    }
}

function Get-SectionRows {
    param(
        [object]$Section,
        [int]$Width,
        [switch]$Dense
    )
    $rows = New-Object System.Collections.Generic.List[object]
    $rule = [Math]::Max(8, $Width - $Section.Header.Length - 3)
    [void]$rows.Add([pscustomobject]@{ Text = (' {0} {1}' -f $Section.Header, ('-' * $rule)); Color = $Section.Color })
    foreach ($item in $Section.Items) {
        [void]$rows.Add([pscustomobject]@{ Text = (' {0}) {1}' -f $item.Number, $item.Label); Color = $Section.Color })
        $descWidth = [Math]::Max(24, $Width - 6)
        foreach ($desc in (Split-PreviewText -Text $item.Desc -Width $descWidth)) {
            [void]$rows.Add([pscustomobject]@{ Text = ('    {0}' -f $desc); Color = 'White' })
        }
        if (-not $Dense) { [void]$rows.Add([pscustomobject]@{ Text = ''; Color = 'White' }) }
    }
    return $rows.ToArray()
}

function Write-Row {
    param([object]$Row)
    Write-Host $Row.Text -ForegroundColor $Row.Color
}

function Write-TwoColumnRows {
    param(
        [object[]]$Left,
        [object[]]$Right,
        [int]$LeftWidth,
        [int]$Gap = 4
    )
    $count = [Math]::Max($Left.Count, $Right.Count)
    for ($i = 0; $i -lt $count; $i++) {
        $left = if ($i -lt $Left.Count) { $Left[$i] } else { [pscustomobject]@{ Text = ''; Color = 'White' } }
        $right = if ($i -lt $Right.Count) { $Right[$i] } else { [pscustomobject]@{ Text = ''; Color = 'White' } }
        Write-Host ($left.Text.PadRight($LeftWidth)) -ForegroundColor $left.Color -NoNewline
        Write-Host (' ' * $Gap) -NoNewline
        Write-Host $right.Text -ForegroundColor $right.Color
    }
}

function Write-Footer {
    param([int]$Width)
    $text = 'Enter number and press Enter  |  H = Help  |  U = Unattended Mode  |  L = View Log  |  Q = Quit'
    Write-Rule -Width $Width -Color 'DarkCyan'
    Write-Centered -Text $text -Width $Width -Color 'White'
}

function Clear-PreviewHost {
    try {
        Clear-Host
        return
    } catch {}

    try {
        [Console]::Clear()
        return
    } catch {}

    Write-Host ''
}

function Write-ReferenceNeon {
    param([int]$Width, [int]$Height)
    $renderWidth = [Math]::Min($Width - 2, 176)
    $renderWidth = [Math]::Max(100, $renderWidth)
    Write-Rule -Width $renderWidth -Color 'DarkCyan' -Char '='
    Write-Wordmark -Lines (Get-WordmarkBlock) -Width $renderWidth -Color 'Cyan'
    Write-Centered -Text 'Developed and maintained by Jumpstile' -Width $renderWidth -Color 'White'
    Write-Centered -Text ("Version {0}" -f ($script:DisplayVersion -replace '^v', '')) -Width $renderWidth -Color 'Yellow'
    Write-Rule -Width $renderWidth -Color 'DarkCyan' -Char '='
    Write-Host ''

    $sections = @(Get-PreviewSections)
    $gap = 4
    $columnWidth = [Math]::Floor(($renderWidth - $gap) / 2)
    $leftRows = @()
    $rightRows = @()
    foreach ($section in @($sections[0], $sections[2])) { $leftRows += Get-SectionRows -Section $section -Width $columnWidth -Dense }
    foreach ($section in @($sections[1], $sections[3])) { $rightRows += Get-SectionRows -Section $section -Width $columnWidth -Dense }
    Write-TwoColumnRows -Left $leftRows -Right $rightRows -LeftWidth $columnWidth -Gap $gap
    Write-Footer -Width $renderWidth
}

function Write-BlockMarquee {
    param([int]$Width, [int]$Height)
    $renderWidth = [Math]::Min($Width - 4, 150)
    $renderWidth = [Math]::Max(100, $renderWidth)
    Write-Rule -Width $renderWidth -Color 'Cyan' -Char '#'
    Write-Wordmark -Lines (Get-WordmarkPlate) -Width $renderWidth -Color 'Yellow'
    Write-Centered -Text 'Developed and maintained by Jumpstile' -Width $renderWidth -Color 'White'
    Write-Centered -Text ("Version {0}" -f ($script:DisplayVersion -replace '^v', '')) -Width $renderWidth -Color 'Cyan'
    Write-Rule -Width $renderWidth -Color 'Cyan' -Char '#'
    Write-Host ''
    $sections = @(Get-PreviewSections)
    foreach ($section in $sections) {
        foreach ($row in (Get-SectionRows -Section $section -Width $renderWidth -Dense)) { Write-Row -Row $row }
    }
    Write-Footer -Width $renderWidth
}

function Write-ArcadeFrame {
    param([int]$Width, [int]$Height)
    $renderWidth = [Math]::Min($Width - 2, 170)
    $renderWidth = [Math]::Max(100, $renderWidth)
    Write-Host ('+' + ('=' * ($renderWidth - 2)) + '+') -ForegroundColor 'DarkCyan'
    foreach ($line in (Get-WordmarkReference)) { Write-BoxLine -Text $line -Width $renderWidth -Color 'DarkCyan' -TextColor 'Cyan' }
    Write-BoxLine -Text 'Developed and maintained by Jumpstile' -Width $renderWidth -Color 'DarkCyan' -TextColor 'White'
    Write-BoxLine -Text ("Version {0}" -f ($script:DisplayVersion -replace '^v', '')) -Width $renderWidth -Color 'DarkCyan' -TextColor 'Yellow'
    Write-Host ('+' + ('=' * ($renderWidth - 2)) + '+') -ForegroundColor 'DarkCyan'
    Write-Host ''
    $sections = @(Get-PreviewSections)
    $gap = 5
    $columnWidth = [Math]::Floor(($renderWidth - $gap) / 2)
    $leftRows = @()
    $rightRows = @()
    foreach ($section in @($sections[0], $sections[2])) { $leftRows += Get-SectionRows -Section $section -Width $columnWidth }
    foreach ($section in @($sections[1], $sections[3])) { $rightRows += Get-SectionRows -Section $section -Width $columnWidth }
    Write-TwoColumnRows -Left $leftRows -Right $rightRows -LeftWidth $columnWidth -Gap $gap
    Write-Footer -Width $renderWidth
}

function Write-CenteredTerminal {
    param([int]$Width, [int]$Height)
    $renderWidth = [Math]::Min($Width - 2, 132)
    $renderWidth = [Math]::Max(96, $renderWidth)
    $pad = [Math]::Max(0, [Math]::Floor(($Width - $renderWidth) / 2))
    $prefix = ' ' * $pad
    function Write-Padded([string]$Text, [string]$Color) { Write-Host ($prefix + $Text) -ForegroundColor $Color }
    Write-Padded ('=' * $renderWidth) 'DarkCyan'
    foreach ($line in (Get-WordmarkCompact)) {
        $left = [Math]::Max(0, [Math]::Floor(($renderWidth - $line.Length) / 2))
        Write-Padded ((' ' * $left) + $line) 'Cyan'
    }
    Write-Padded ((' ' * [Math]::Max(0, [Math]::Floor(($renderWidth - 36) / 2))) + 'Developed and maintained by Jumpstile') 'White'
    Write-Padded ((' ' * [Math]::Max(0, [Math]::Floor(($renderWidth - 15) / 2))) + 'Version 1.0 RC2') 'Yellow'
    Write-Padded ('=' * $renderWidth) 'DarkCyan'
    $sections = @(Get-PreviewSections)
    foreach ($section in $sections) {
        foreach ($row in (Get-SectionRows -Section $section -Width $renderWidth -Dense)) {
            Write-Padded $row.Text $row.Color
        }
    }
    Write-Padded ('-' * $renderWidth) 'DarkCyan'
    Write-Padded 'Enter number and press Enter  |  H = Help  |  U = Unattended Mode  |  L = View Log  |  Q = Quit' 'White'
}

function Write-CompactReadable {
    param([int]$Width, [int]$Height)
    $renderWidth = [Math]::Max(60, [Math]::Min($Width - 2, 100))
    Write-Rule -Width $renderWidth -Color 'DarkCyan'
    Write-Centered -Text ("TeknoParrot Manager  {0}" -f $script:DisplayVersion) -Width $renderWidth -Color 'Cyan'
    Write-Centered -Text 'Developed and maintained by Jumpstile' -Width $renderWidth -Color 'White'
    Write-Rule -Width $renderWidth -Color 'DarkCyan'
    $sections = @(Get-PreviewSections)
    foreach ($section in $sections) {
        Write-Host (" {0}" -f $section.Header) -ForegroundColor $section.Color
        foreach ($item in $section.Items) {
            Write-Host ("   {0,2}) {1}" -f $item.Number, $item.Label) -ForegroundColor $section.Color
        }
        Write-Host ''
    }
    Write-Footer -Width $renderWidth
}

function Write-PrototypeDiagnostics {
    param(
        [object]$Info,
        [object]$MaximizeStatus,
        [string]$VariantName
    )
    Write-Host 'Prototype diagnostics' -ForegroundColor 'DarkGray'
    Write-Host ('  Variant                 : {0}' -f $VariantName) -ForegroundColor 'DarkGray'
    Write-Host ('  Host type               : {0}' -f $Info.HostName) -ForegroundColor 'DarkGray'
    Write-Host ('  RawUI type              : {0}' -f $Info.RawUiType) -ForegroundColor 'DarkGray'
    Write-Host ('  RawUI window            : {0}x{1}' -f $Info.RawWindowWidth, $Info.RawWindowHeight) -ForegroundColor 'DarkGray'
    Write-Host ('  RawUI buffer            : {0}x{1}' -f $Info.RawBufferWidth, $Info.RawBufferHeight) -ForegroundColor 'DarkGray'
    Write-Host ('  Console window          : {0}x{1}' -f $Info.ConsoleWidth, $Info.ConsoleHeight) -ForegroundColor 'DarkGray'
    Write-Host ('  Effective viewport      : {0}x{1}' -f $Info.Width, $Info.Height) -ForegroundColor 'DarkGray'
    if ($MaximizeStatus) {
        Write-Host ('  Maximize attempted      : {0}' -f $MaximizeStatus.Attempted) -ForegroundColor 'DarkGray'
        Write-Host ('  Maximize succeeded      : {0}' -f $MaximizeStatus.Succeeded) -ForegroundColor 'DarkGray'
        Write-Host ('  Maximize skipped        : {0}' -f $MaximizeStatus.Skipped) -ForegroundColor 'DarkGray'
        Write-Host ('  Maximize detail         : {0}' -f $MaximizeStatus.Message) -ForegroundColor 'DarkGray'
    }
    Write-Host ''
}

function Show-Prototype {
    param([string]$Name)
    $info = Get-ViewportInfo
    Clear-PreviewHost
    if ($Diagnostics) { Write-PrototypeDiagnostics -Info $info -MaximizeStatus $script:MaximizeStatus -VariantName $Name }
    switch ($Name) {
        'ReferenceNeon' { Write-ReferenceNeon -Width $info.Width -Height $info.Height }
        'BlockMarquee' { Write-BlockMarquee -Width $info.Width -Height $info.Height }
        'ArcadeFrame' { Write-ArcadeFrame -Width $info.Width -Height $info.Height }
        'CenteredTerminal' { Write-CenteredTerminal -Width $info.Width -Height $info.Height }
        'CompactReadable' { Write-CompactReadable -Width $info.Width -Height $info.Height }
    }
}

function Watch-Prototype {
    param([string]$Name)

    $lastKey = ''
    while ($true) {
        $info = Get-ViewportInfo
        $key = '{0}x{1}' -f $info.Width, $info.Height
        if ($key -ne $lastKey) {
            Show-Prototype -Name $Name
            Write-Host ''
            Write-Host 'Resize the window to test reflow. Press Q to quit preview.' -ForegroundColor 'DarkGray'
            $lastKey = $key
        }

        try {
            if ([Console]::KeyAvailable) {
                $pressed = [Console]::ReadKey($true)
                if ($pressed.Key -eq 'Q' -or $pressed.Key -eq 'Escape') { break }
                if ($pressed.Key -eq 'R') {
                    Show-Prototype -Name $Name
                    Write-Host ''
                    Write-Host 'Resize the window to test reflow. Press Q to quit preview.' -ForegroundColor 'DarkGray'
                    $lastKey = '{0}x{1}' -f (Get-ViewportInfo).Width, (Get-ViewportInfo).Height
                }
            }
        } catch {}

        Start-Sleep -Milliseconds ([Math]::Max(50, $RefreshMs))
    }
}

$variants = @('ReferenceNeon', 'BlockMarquee', 'ArcadeFrame', 'CenteredTerminal', 'CompactReadable')
if ($List) {
    $variants | ForEach-Object { Write-Host $_ }
    return
}

$script:MaximizeStatus = $null
if ($AttemptMaximize) {
    $script:MaximizeStatus = Invoke-PrototypeMaximize
}

if ($Watch) {
    if ($Variant -eq 'All') {
        throw 'Watch mode previews one variant at a time. Choose a specific -Variant.'
    }
    Watch-Prototype -Name $Variant
} elseif ($Variant -eq 'All') {
    foreach ($name in $variants) {
        Show-Prototype -Name $name
        Write-Host ''
        Write-Host ("Variant: {0}. Press Enter for next preview..." -f $name) -ForegroundColor 'DarkGray'
        [void](Read-Host)
    }
} else {
    Show-Prototype -Name $Variant
}
