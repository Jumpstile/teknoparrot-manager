#Requires -Module Pester
# FIX99: the source-collection guard (owner rule R6) in the other game-side installers.
#   TeknoParrot Manager never writes inside the configured source collection (main source folder and supplementary source folder).
#   FIX96 did this for ReShade. FIX99 does the same for dgVoodoo2 (Invoke-DgVoodoo2Setup), Crosshair (Invoke-CrosshairSetup) and the
#   force feedback plugin (Invoke-FFBPluginSetup and its removal Remove-FFBPluginOwnedDeployment): a game folder inside a source folder is
#   refused before anything is staged, saved or written, the profile is not touched, and games outside the source folders still install.
#   The required game patch menu (Invoke-TpmRequiredPatchMenu: install for one game, install for registered games, undo) gets the same
#   check; it already protected the source folder that holds the patch ZIP, but not the other one, and Undo protected neither.
# These tests drive the real product functions with synthetic folders in $TestDrive; nothing touches TeknoParrot, LaunchBox, the registry,
# services or the network. Each It names the product change that makes it fail.
# What this CANNOT prove: that the menu bodies pass the two source folders to the installers (the menus are script body, not functions),
# how a real console paints the rows, or a real dgVoodoo2 / FFB plugin download (the downloads are replaced by small fixtures).

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $script:f99Ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX99 bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'fix99-functions.ps1'
    ($script:f99Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    . (Join-Path $PSScriptRoot 'FfbPluginTestKit.ps1')
    . (Join-Path $PSScriptRoot '..\scripts\TpmRequiredPatchEngine.ps1')
    $FuzzyAutoThreshold = 0.72
    $FuzzyTieMargin = 0.1
    $script:TitleTokenStopWords = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('the', 'of', 'a', 'an', 'and', 'vs', 'vs.', 'in', 'for', 'to'),
        [System.StringComparer]::OrdinalIgnoreCase)
    $script:DisplayVersion = 'v1.0 RC8'
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false
    $script:logPath = Join-Path $TestDrive 'fix99.log'
    $script:logWarnShown = $false
    $script:f99RefusalOne = 'Not changed: 1 game is inside your source folder (where your game collection is kept).'
    $script:f99RefusalMove = 'TeknoParrot Manager never changes your source folder. Move the game out of it, or fix the game folder in its profile.'

    # A fake console: every Write-Host row and every log line is recorded.
    function Install-F99Console {
        $script:f99Rows = New-Object System.Collections.Generic.List[string]
        $script:f99Log = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { [void]$script:f99Rows.Add([string]($Object -join ' ')) }
        Mock Write-Log { [void]$script:f99Log.Add([string]$msg) }
        Mock Get-ConsoleContentWidth { return 120 }
        Mock Write-TpmCompactExtractionProgress {}
    }
    # Everything printed, as one string with white space collapsed (a sentence that wrapped over several rows reads as one sentence).
    # A blank row (Write-TpmText -BlankBefore) collapses into a leading space, so the ends are trimmed.
    function Get-F99Text {
        return (((@($script:f99Rows | ForEach-Object { ([string]$_).Trim() }) -join ' ') -replace '\s+', ' ').Trim())
    }
    function New-F99Root {
        param([string]$Name)
        $root = Join-Path $TestDrive ($Name + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        [void][System.IO.Directory]::CreateDirectory($root)
        return $root
    }
    # One line per folder and per file (with the SHA-256 of the file) under the paths: two equal snapshots are byte-for-byte the same tree.
    function Get-F99Snapshot {
        param([string[]]$Path)
        $rows = New-Object System.Collections.Generic.List[string]
        foreach ($entry in $Path) {
            if (-not (Test-Path -LiteralPath $entry)) { [void]$rows.Add('absent|' + $entry); continue }
            foreach ($item in @(Get-Item -LiteralPath $entry -Force) + @(Get-ChildItem -LiteralPath $entry -Recurse -Force -ErrorAction SilentlyContinue)) {
                if ($item.PSIsContainer) { [void]$rows.Add('dir|' + $item.FullName) }
                else { [void]$rows.Add('file|' + $item.FullName + '|' + (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash) }
            }
        }
        return (($rows | Sort-Object) -join "`n")
    }
    # A real directory junction; Created is $false (and the test is skipped) when the machine does not allow one.
    function New-F99Junction {
        param([string]$Link, [string]$Target)
        try {
            $output = & cmd.exe /d /c ('mklink /J "{0}" "{1}"' -f $Link, $Target) 2>&1
            $exitCode = $LASTEXITCODE
            if ($exitCode -ne 0 -or -not [System.IO.Directory]::Exists($Link)) { return [pscustomobject]@{ Created = $false; Because = ('mklink /J unavailable (exit {0}): {1}' -f $exitCode, ($output -join ' ')) } }
            return [pscustomobject]@{ Created = $true; Because = '' }
        } catch { return [pscustomobject]@{ Created = $false; Because = $_.Exception.Message } }
    }
    # A library of games, each with a game file and a profile. A game is in the main source folder (Main), the supplementary source folder
    # (Supp) or in the games folder (Games); its folder is named like its code. One profile serves all three installers.
    function New-F99Library {
        param([Parameter(Mandatory)][hashtable[]]$Spec)
        $root = New-F99Root 'library'
        $library = [ordered]@{
            Root = $root; Profiles = (Join-Path $root 'UserProfiles'); TpRoot = (Join-Path $root 'TeknoParrot')
            Main = (Join-Path $root 'Collection'); Supp = (Join-Path $root 'Supplementary'); Games = (Join-Path $root 'Games')
            Exes = @{}; Dirs = @{}; ProfileFiles = @{}
        }
        foreach ($folder in @($library.Profiles, $library.TpRoot, $library.Main, $library.Supp, $library.Games)) { [void][System.IO.Directory]::CreateDirectory($folder) }
        foreach ($game in $Spec) {
            $parent = switch ([string]$game.Where) { 'Main' { Join-Path $library.Main 'Unpacked' } 'Supp' { Join-Path $library.Supp 'Unpacked' } default { $library.Games } }
            $dir = Join-Path $parent ([string]$game.Code)
            [void][System.IO.Directory]::CreateDirectory($dir)
            $exe = Join-Path $dir 'game.exe'
            [System.IO.File]::WriteAllText($exe, 'MZ-test-game')
            $profile = Join-Path $library.Profiles ([string]$game.Code + '.xml')
            [System.IO.File]::WriteAllText($profile, ('<GameProfile><GameName>Game {0}</GameName><GunGame>true</GunGame><EmulatorType>Other</EmulatorType><GamePath>{1}</GamePath></GameProfile>' -f $game.Code, $exe), (New-Object System.Text.UTF8Encoding $false))
            $library.Exes[[string]$game.Code] = $exe
            $library.Dirs[[string]$game.Code] = $dir
            $library.ProfileFiles[[string]$game.Code] = $profile
        }
        return [pscustomobject]$library
    }
    # The two things a test compares before and after: the source folders and every profile.
    function Get-F99Guarded {
        param($Library)
        return (Get-F99Snapshot -Path (@($Library.Main, $Library.Supp) + @($Library.ProfileFiles.Values)))
    }
    # The installers, driven the way their menus drive them (the source folders are passed in $ProtectedRoots).
    function Invoke-F99DgSetup {
        param($Library, [string[]]$ProtectedRoots = @())
        $source = Join-Path $Library.Root 'DgSource'
        [void][System.IO.Directory]::CreateDirectory($source)
        [System.IO.File]::WriteAllText((Join-Path $source 'D3D8.dll'), 'dll-bytes')
        $oldLayout = $script:TpmOwnedLayout
        $script:TpmOwnedLayout = [pscustomobject]@{ Assets = (Join-Path $Library.Root 'Assets') }
        try { return (Invoke-DgVoodoo2Setup -UserProfilesDir $Library.Profiles -SourceDir $source -ProtectedRoots $ProtectedRoots) }
        finally { $script:TpmOwnedLayout = $oldLayout }
    }
    function Invoke-F99CrosshairSetup {
        param($Library, [string[]]$ProtectedRoots = @())
        # The function reads its pictures from a Crosshairs folder next to the file it was loaded from (the TestDrive).
        $pictures = Join-Path $TestDrive 'Crosshairs'
        [void][System.IO.Directory]::CreateDirectory($pictures)
        [System.IO.File]::WriteAllBytes((Join-Path $pictures '001.png'), [byte[]](1, 2, 3))
        return (Invoke-CrosshairSetup -UserProfilesDir $Library.Profiles -TpRoot $Library.TpRoot -ProtectedRoots $ProtectedRoots)
    }
    function Invoke-F99FfbSetup {
        param($Library, [string[]]$ProtectedRoots = @(), [string[]]$NativeCodes = @())
        $cache = Join-Path $Library.Root 'FFBPlugin'
        [void][System.IO.Directory]::CreateDirectory($cache)
        return (Invoke-FFBPluginSetup -UserProfilesDir $Library.Profiles -CacheDir $cache -TpRoot $Library.TpRoot -NativeEnabledCodes $NativeCodes -ProtectedRoots $ProtectedRoots)
    }
}

Describe 'FIX99 the shared refusal lines' {
    BeforeEach { Install-F99Console }

    It 'says "is" for one game, "are" for several, and prints nothing for none' {
        # Mutation: always say "are", or print the two lines when the count is 0 -> a clean run tells the user about a source folder problem.
        Write-TpmSourceFolderRefusal -Count 1
        (Get-F99Text) | Should -BeExactly ($script:f99RefusalOne + ' ' + $script:f99RefusalMove)
        Install-F99Console
        Write-TpmSourceFolderRefusal -Count 3
        (Get-F99Text) | Should -BeExactly ('Not changed: 3 games are inside your source folder (where your game collection is kept). ' + $script:f99RefusalMove)
        Install-F99Console
        Write-TpmSourceFolderRefusal -Count 0
        $script:f99Rows.Count | Should -Be 0
    }
}

Describe 'FIX99 dgVoodoo2 never installs into the source collection' {
    BeforeEach {
        Install-F99Console
        Mock Get-GameLegacyApi { @('D3D8') }
        Mock Read-TpmChoice { 'A' }
    }

    It 'refuses a game inside the <Where> source folder: nothing is written, the profile is untouched, the screen says why in plain words' -ForEach @(
        @{ Where = 'Main' }
        @{ Where = 'Supp' }
    ) {
        # Mutation: do not pass -ProtectedRoots to the two Test-TpmGameMutationPath calls of Invoke-DgVoodoo2Setup -> D3D8.dll is written into the collection.
        $library = New-F99Library -Spec @(@{ Code = 'InsideGame'; Where = $Where })
        $before = Get-F99Guarded -Library $library
        $result = Invoke-F99DgSetup -Library $library -ProtectedRoots @($library.Main, $library.Supp)
        Get-F99Guarded -Library $library | Should -BeExactly $before
        Test-Path -LiteralPath (Join-Path $library.Dirs['InsideGame'] 'D3D8.dll') | Should -BeFalse
        $result.Succeeded | Should -BeFalse
        $result.Deployed | Should -Be 0
        $result.Skipped | Should -Be 1
        $result.TransactionResult.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $text = Get-F99Text
        $text | Should -Match ([regex]::Escape($script:f99RefusalOne + ' ' + $script:f99RefusalMove))
        $text | Should -Not -Match 'path safety check failed|SOURCE_COLLECTION'
    }

    It 'keeps the saved path and the technical reason for Details and the log' {
        # Mutation: drop the skip record (or its Technical / SavedPath) of the refused game -> Details and the log lose the facts.
        $library = New-F99Library -Spec @(@{ Code = 'InsideGame'; Where = 'Main' })
        $result = Invoke-F99DgSetup -Library $library -ProtectedRoots @($library.Main)
        $skip = @($result.SkipDetails)[0]
        $skip.ReasonCode | Should -BeExactly 'SOURCE_COLLECTION'
        $skip.SavedPath | Should -BeExactly $library.Exes['InsideGame']
        $skip.Technical | Should -Match 'inside the source folder'
        $details = (@(Get-TpmDgVoodoo2DetailBlocks -Result $result | ForEach-Object { $_.Lines }) -join ' ')
        $details | Should -Match ([regex]::Escape($library.Exes['InsideGame']))
        $details | Should -Match 'never changes files there'
        ($script:f99Log -join "`n") | Should -Match 'dgVoodoo2: refused InsideGame before deployment; path reason=SOURCE_COLLECTION'
    }

    It 'still installs into a game outside the source folders while it refuses the one inside' {
        # Mutation: refuse the whole run (or none) when one game is inside a source folder -> the outside game gets no file, or the inside one gets one.
        $library = New-F99Library -Spec @(@{ Code = 'InsideGame'; Where = 'Main' }, @{ Code = 'OutsideGame'; Where = 'Games' })
        $before = Get-F99Guarded -Library $library
        $result = Invoke-F99DgSetup -Library $library -ProtectedRoots @($library.Main, $library.Supp)
        Get-F99Guarded -Library $library | Should -BeExactly $before
        Test-Path -LiteralPath (Join-Path $library.Dirs['OutsideGame'] 'D3D8.dll') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $library.Dirs['InsideGame'] 'D3D8.dll') | Should -BeFalse
        $result.Deployed | Should -Be 1
        $result.Succeeded | Should -BeFalse -Because 'one game was refused, so the run is not a complete success'
        (Get-F99Text) | Should -Match ([regex]::Escape($script:f99RefusalOne))
    }

    It 'installs into the game when no source folder is configured' {
        # Mutation: refuse every game when ProtectedRoots is empty -> a user without a source folder can no longer install.
        $library = New-F99Library -Spec @(@{ Code = 'OutsideGame'; Where = 'Games' })
        $result = Invoke-F99DgSetup -Library $library -ProtectedRoots @('', $null)
        $result.Succeeded | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $library.Dirs['OutsideGame'] 'D3D8.dll') | Should -BeTrue
        (Get-F99Text) | Should -Not -Match 'inside your source folder'
    }

    It 'refuses a game that is reached through a junction to the source folder' {
        # Mutation: compare the spelled path only (no real-path check) -> a junction to the source folder hides it.
        $library = New-F99Library -Spec @(@{ Code = 'InsideGame'; Where = 'Main' })
        $link = Join-Path $library.Root 'CollectionLink'
        $junction = New-F99Junction -Link $link -Target $library.Main
        if (-not $junction.Created) { Set-ItResult -Skipped -Because $junction.Because; return }
        try {
            $before = Get-F99Guarded -Library $library
            $result = Invoke-F99DgSetup -Library $library -ProtectedRoots @($link)
            Get-F99Guarded -Library $library | Should -BeExactly $before
            $result.Deployed | Should -Be 0
            @($result.SkipDetails)[0].ReasonCode | Should -BeExactly 'SOURCE_COLLECTION'
        } finally {
            & cmd.exe /d /c ('rmdir "{0}"' -f $link) | Out-Null
        }
    }
}

Describe 'FIX99 Crosshair never installs into the source collection' {
    BeforeEach {
        Install-F99Console
        Mock Test-PngFile { $true }
        Mock Show-TpmCrosshairPreviewWindow { [pscustomobject]@{ Available = $false; Cancelled = $false; P1Index = $null; P2Index = $null; TimedOut = $false; Reason = 'FIXTURE' } }
        Mock Resolve-Pcsx2Directory { $null }
        Mock Read-HostSafe { if ($Prompt -match '(?i)Y/N') { if ($Prompt -match '(?i)hide the Windows cursor') { 'N' } else { 'Y' } } else { '0' } }
    }

    It 'refuses a game inside <Where> source folder: no picture is written, the profile is untouched, the screen says why in plain words' -ForEach @(
        @{ Where = 'the main'; Folder = 'Main' }
        @{ Where = 'the supplementary'; Folder = 'Supp' }
    ) {
        # Mutation: do not pass -ProtectedRoots to the Test-TpmGameMutationPath call of Invoke-CrosshairSetup -> P1.png and P2.png are written into the collection.
        # Mutation: run the P1/P2 transaction when every game was refused -> the saved crosshair choice file is written although nothing was installed.
        # Mutation: offer or run cursor hiding when every game was refused -> with the answer Y the profiles are changed after a refusal.
        # Mutation: print "No lightgun games were found" while games were refused -> the screen says there were no games when the source folder blocked them.
        # The user answers Y to every question, including "hide the Windows cursor".
        Mock Read-HostSafe { if ($Prompt -match '(?i)Y/N') { 'Y' } else { '0' } }
        Mock Invoke-CursorHideSetup { throw 'Cursor hiding must not run when every game was refused.' }
        $statePath = Join-Path $TestDrive 'TeknoParrot-Manager-crosshairs.json'
        Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
        $library = New-F99Library -Spec @(@{ Code = 'InsideGun'; Where = $Folder })
        $before = Get-F99Guarded -Library $library
        $result = Invoke-F99CrosshairSetup -Library $library -ProtectedRoots @($library.Main, $library.Supp)
        Get-F99Guarded -Library $library | Should -BeExactly $before
        Test-Path -LiteralPath $statePath | Should -BeFalse
        Should -Invoke Invoke-CursorHideSetup -Times 0 -Exactly
        Should -Invoke Read-HostSafe -Times 0 -Exactly -ParameterFilter { $Prompt -match '(?i)hide the Windows cursor' }
        Test-Path -LiteralPath (Join-Path $library.Dirs['InsideGun'] 'P1.png') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $library.Dirs['InsideGun'] 'P2.png') | Should -BeFalse
        $result.Succeeded | Should -BeTrue
        $result.NoOp | Should -BeTrue
        @($result.SourceFolderGames) | Should -Be @('Game InsideGun')
        # Mutation: build the result screen from NoTargets alone -> "No lightgun games were found", an active Player 1/Player 2 line and "Nothing else to do" although the games were refused.
        $view = Get-TpmCrosshairResultView -Result $result
        $view.Title | Should -BeExactly 'Your lightgun games are inside your source folder, so nothing was changed.'
        @($view.Done).Count | Should -Be 0
        $view.Next | Should -Match '^Move the game out of your source folder'
        $text = Get-F99Text
        $text | Should -Match ([regex]::Escape($script:f99RefusalOne + ' ' + $script:f99RefusalMove))
        $text | Should -Not -Match 'skipped\. The log says why|could not be safely verified|No lightgun games were found'
        ($script:f99Log -join "`n") | Should -Match ('Crosshairs: skipped InsideGun; path reason=SOURCE_COLLECTION.*saved path=' + [regex]::Escape($library.Exes['InsideGun']))
    }

    It 'with no lightgun game at all, saves the choice, writes no picture and does not crash' {
        # Mutation: take [AllowEmptyCollection()] off -Targets of Invoke-TpmCrosshairAssetTransaction -> a library with no lightgun game ends in a parameter binding error.
        $library = New-F99Library -Spec @(@{ Code = 'PlainGame'; Where = 'Games' })
        [System.IO.File]::WriteAllText($library.ProfileFiles['PlainGame'], ([System.IO.File]::ReadAllText($library.ProfileFiles['PlainGame']).Replace('<GunGame>true</GunGame>', '<GunGame>false</GunGame>')), (New-Object System.Text.UTF8Encoding $false))
        $statePath = Join-Path $TestDrive 'TeknoParrot-Manager-crosshairs.json'
        Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
        $result = Invoke-F99CrosshairSetup -Library $library -ProtectedRoots @($library.Main, $library.Supp)
        $result.NoTargets | Should -BeTrue
        $result.Succeeded | Should -BeTrue
        @($result.SourceFolderGames).Count | Should -Be 0
        Test-Path -LiteralPath $statePath | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $library.Dirs['PlainGame'] 'P1.png') | Should -BeFalse
        (Get-F99Text) | Should -Match 'No lightgun games were found'
    }

    It 'still installs into a game outside the source folders, and counts another skipped game on its own line' {
        # Mutation: count the refused game in the generic "skipped" line too, or refuse the outside game as well.
        $library = New-F99Library -Spec @(@{ Code = 'InsideGun'; Where = 'Main' }, @{ Code = 'OutsideGun'; Where = 'Games' }, @{ Code = 'LostGun'; Where = 'Games' })
        Remove-Item -LiteralPath $library.Exes['LostGun'] -Force
        $before = Get-F99Guarded -Library $library
        $result = Invoke-F99CrosshairSetup -Library $library -ProtectedRoots @($library.Main, $library.Supp)
        Get-F99Guarded -Library $library | Should -BeExactly $before
        Test-Path -LiteralPath (Join-Path $library.Dirs['OutsideGun'] 'P1.png') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $library.Dirs['OutsideGun'] 'P2.png') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $library.Dirs['InsideGun'] 'P1.png') | Should -BeFalse
        $result.DeployedGames | Should -Be @('Game OutsideGun')
        $result.Skipped | Should -Be 2
        $text = Get-F99Text
        $text | Should -Match ([regex]::Escape('1 game skipped. The log says why.'))
        $text | Should -Match ([regex]::Escape($script:f99RefusalOne))
    }

    It 'installs into the game when no source folder is configured' {
        # Mutation: refuse every game when ProtectedRoots is empty -> a user without a source folder can no longer install.
        $library = New-F99Library -Spec @(@{ Code = 'OutsideGun'; Where = 'Games' })
        $result = Invoke-F99CrosshairSetup -Library $library -ProtectedRoots @('', $null)
        $result.Succeeded | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $library.Dirs['OutsideGun'] 'P1.png') | Should -BeTrue
        @($result.SourceFolderGames).Count | Should -Be 0
    }

    It 'refuses a game that is reached through a junction to the source folder' {
        # Mutation: compare the spelled path only (no real-path check) -> a junction to the source folder hides it.
        $library = New-F99Library -Spec @(@{ Code = 'InsideGun'; Where = 'Main' })
        $link = Join-Path $library.Root 'CollectionLink'
        $junction = New-F99Junction -Link $link -Target $library.Main
        if (-not $junction.Created) { Set-ItResult -Skipped -Because $junction.Because; return }
        try {
            $before = Get-F99Guarded -Library $library
            $result = Invoke-F99CrosshairSetup -Library $library -ProtectedRoots @($link)
            Get-F99Guarded -Library $library | Should -BeExactly $before
            @($result.SourceFolderGames) | Should -Be @('Game InsideGun')
        } finally {
            & cmd.exe /d /c ('rmdir "{0}"' -f $link) | Out-Null
        }
    }
}

Describe 'FIX99 the force feedback plugin never installs into or removes from the source collection' {
    BeforeEach {
        Install-F99Console
        Mock Get-FFBPluginLatestRelease { New-FfbTestRelease }
        Mock Get-FFBPluginGameMap { [ordered]@{ InsideGame = 'd3d9.dll'; OutsideGame = 'd3d9.dll' } }
        Mock Invoke-FFBPluginDownload { param([string]$destDir, [object]$Release) New-FFBDownloadFixtureResult -destDir $destDir -Release $Release }
        Mock Get-ExeArchitecture { 'x64' }
        Mock Read-HostSafe { 'Y' }
    }

    It 'refuses a game inside <Where> source folder, installs the game outside, and keeps the accounting complete' -ForEach @(
        @{ Where = 'the main'; Folder = 'Main' }
        @{ Where = 'the supplementary'; Folder = 'Supp' }
    ) {
        # Mutation: do not pass -ProtectedRoots to the Test-TpmGameMutationPath call of the plugin planning loop -> d3d9.dll is written into the collection.
        $library = New-F99Library -Spec @(@{ Code = 'InsideGame'; Where = $Folder }, @{ Code = 'OutsideGame'; Where = 'Games' })
        $before = Get-F99Guarded -Library $library
        $result = Invoke-F99FfbSetup -Library $library -ProtectedRoots @($library.Main, $library.Supp)
        Get-F99Guarded -Library $library | Should -BeExactly $before
        Test-Path -LiteralPath (Join-Path $library.Dirs['InsideGame'] 'd3d9.dll') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $library.Dirs['OutsideGame'] 'd3d9.dll') | Should -BeTrue
        $result.Deployed | Should -Be 1
        $result.Succeeded | Should -BeFalse -Because 'one game was refused, so the run is not a complete success'
        $result.Reason | Should -BeExactly 'BLOCKED_SKIPS'
        $result.AccountingComplete | Should -BeTrue
        @($result.SourceFolderGames) | Should -Be @('Game InsideGame')
        $text = Get-F99Text
        $text | Should -Match ([regex]::Escape($script:f99RefusalOne + ' ' + $script:f99RefusalMove))
        $text | Should -Not -Match 'Skipped \(saved path\)'
        ($script:f99Log -join "`n") | Should -Match ('FFBPlugin: refused InsideGame; path reason=SOURCE_COLLECTION.*game path=' + [regex]::Escape($library.Exes['InsideGame']))
    }

    It 'installs into the game when no source folder is configured' {
        # Mutation: refuse every game when ProtectedRoots is empty -> a user without a source folder can no longer install.
        $library = New-F99Library -Spec @(@{ Code = 'OutsideGame'; Where = 'Games' })
        $result = Invoke-F99FfbSetup -Library $library -ProtectedRoots @('', $null)
        $result.Succeeded | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $library.Dirs['OutsideGame'] 'd3d9.dll') | Should -BeTrue
        @($result.SourceFolderGames).Count | Should -Be 0
    }

    It 'refuses a game that is reached through a junction to the source folder' {
        # Mutation: compare the spelled path only (no real-path check) -> a junction to the source folder hides it.
        $library = New-F99Library -Spec @(@{ Code = 'InsideGame'; Where = 'Main' }, @{ Code = 'OutsideGame'; Where = 'Games' })
        $link = Join-Path $library.Root 'CollectionLink'
        $junction = New-F99Junction -Link $link -Target $library.Main
        if (-not $junction.Created) { Set-ItResult -Skipped -Because $junction.Because; return }
        try {
            $before = Get-F99Guarded -Library $library
            $result = Invoke-F99FfbSetup -Library $library -ProtectedRoots @($link)
            Get-F99Guarded -Library $library | Should -BeExactly $before
            @($result.SourceFolderGames) | Should -Be @('Game InsideGame')
        } finally {
            & cmd.exe /d /c ('rmdir "{0}"' -f $link) | Out-Null
        }
    }

    It 'does not remove a recorded plugin file from a game folder inside the source folder, and writes nothing there' -ForEach @(
        @{ Folder = 'Main' }
        @{ Folder = 'Supp' }
    ) {
        # Mutation: do not pass -ProtectedRoots to Remove-FFBPluginOwnedDeployment (or drop its check) -> the hook is backed up into FullBackup and deleted inside the collection.
        $library = New-F99Library -Spec @(@{ Code = 'InsideGame'; Where = $Folder })
        $hook = Join-Path $library.Dirs['InsideGame'] 'd3d9.dll'
        [System.IO.File]::WriteAllText($hook, 'owned-hook')
        $hash = (Get-FileHash -LiteralPath $hook -Algorithm SHA256).Hash
        $cache = Join-Path $library.Root 'FFBPlugin'
        [void][System.IO.Directory]::CreateDirectory($cache)
        Write-FFBPluginOwnership -CacheDir $cache -Entries @([pscustomobject]@{ ProfileCode = 'InsideGame'; GameRoot = $library.Dirs['InsideGame']; Destination = $hook; SourceSha256 = $hash; DeployedSha256 = $hash; CreatedUtc = (Get-Date).ToUniversalTime().ToString('o') })
        $guarded = @($library.Main, $library.Supp) + @($library.ProfileFiles.Values) + @((Join-Path $cache 'TPM-FFB-Plugin-Ownership.json'))
        $before = Get-F99Snapshot -Path $guarded
        { Remove-FFBPluginOwnedDeployment -CacheDir $cache -ProfileCode 'InsideGame' -ProtectedRoots @($library.Main, $library.Supp) } | Should -Throw '*inside your source folder*'
        Get-F99Snapshot -Path $guarded | Should -BeExactly $before
        Test-Path -LiteralPath (Join-Path $library.Dirs['InsideGame'] 'FullBackup') | Should -BeFalse
        ($script:f99Log -join "`n") | Should -Match 'FFBPlugin ownership: refused removal of'
    }

    It 'still removes a recorded plugin file from a game folder outside the source folders' {
        # Mutation: refuse every removal as soon as a source folder is configured -> a normal cleanup no longer works.
        $library = New-F99Library -Spec @(@{ Code = 'OutsideGame'; Where = 'Games' })
        $hook = Join-Path $library.Dirs['OutsideGame'] 'd3d9.dll'
        [System.IO.File]::WriteAllText($hook, 'owned-hook')
        $hash = (Get-FileHash -LiteralPath $hook -Algorithm SHA256).Hash
        $cache = Join-Path $library.Root 'FFBPlugin'
        [void][System.IO.Directory]::CreateDirectory($cache)
        Write-FFBPluginOwnership -CacheDir $cache -Entries @([pscustomobject]@{ ProfileCode = 'OutsideGame'; GameRoot = $library.Dirs['OutsideGame']; Destination = $hook; SourceSha256 = $hash; DeployedSha256 = $hash; CreatedUtc = (Get-Date).ToUniversalTime().ToString('o') })
        (Remove-FFBPluginOwnedDeployment -CacheDir $cache -ProfileCode 'OutsideGame' -ProtectedRoots @($library.Main, $library.Supp)) | Should -BeTrue
        Test-Path -LiteralPath $hook | Should -BeFalse
    }

    It 'keeps native force feedback without touching a plugin file inside the source folder (the cleanup path of the setup)' {
        # Mutation: do not pass -ProtectedRoots from Invoke-FFBPluginSetup to Remove-FFBPluginOwnedDeployment -> choosing "keep native" deletes the old plugin file inside the collection.
        $library = New-F99Library -Spec @(@{ Code = 'InsideGame'; Where = 'Main' })
        $hook = Join-Path $library.Dirs['InsideGame'] 'd3d9.dll'
        [System.IO.File]::WriteAllText($hook, 'owned-hook')
        $hash = (Get-FileHash -LiteralPath $hook -Algorithm SHA256).Hash
        $cache = Join-Path $library.Root 'FFBPlugin'
        [void][System.IO.Directory]::CreateDirectory($cache)
        Write-FFBPluginOwnership -CacheDir $cache -Entries @([pscustomobject]@{ ProfileCode = 'InsideGame'; GameRoot = $library.Dirs['InsideGame']; Destination = $hook; SourceSha256 = $hash; DeployedSha256 = $hash; CreatedUtc = (Get-Date).ToUniversalTime().ToString('o') })
        $before = Get-F99Guarded -Library $library
        $result = Invoke-F99FfbSetup -Library $library -ProtectedRoots @($library.Main, $library.Supp) -NativeCodes @('InsideGame')
        Get-F99Guarded -Library $library | Should -BeExactly $before
        Test-Path -LiteralPath $hook | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $library.Dirs['InsideGame'] 'FullBackup') | Should -BeFalse
        $result.Succeeded | Should -BeFalse
        $result.Errors | Should -Be 1
        ($script:f99Rows -join "`n") | Should -Match 'Not removed: the optional plugin file is inside your source folder'
    }
}

Describe 'FIX99 required game patches never change a game inside the source collection' {
    BeforeEach {
        Install-F99Console
        $script:f99Lib = New-F99Library -Spec @(@{ Code = 'Alpha'; Where = 'Supp' }, @{ Code = 'Beta'; Where = 'Games' })
        $temp = Join-Path $script:f99Lib.Root 'owned\Temp'
        [void][System.IO.Directory]::CreateDirectory($temp)
        $script:TpmOwnedLayout = [pscustomobject]@{ Root = (Join-Path $script:f99Lib.Root 'owned'); Temp = $temp; Backups = (Join-Path $script:f99Lib.Root 'owned\Backups') }
        $script:gamesInstallFolder = $script:f99Lib.Games
        $script:f99Answers = New-Object 'System.Collections.Generic.Queue[string]'
        $script:f99Game = 'Alpha'
        # A real install leaves a saved undo copy (receipt.json) in Backups\GamePatches. The Undo list shows only games that have one, so the fixture leaves one for each patch the tests below use.
        foreach ($savedId in @('alpha-main-one', 'beta-one')) {
            $savedDir = Join-Path $script:TpmOwnedLayout.Backups ('GamePatches\' + ([guid]::NewGuid().ToString('N')))
            [void][System.IO.Directory]::CreateDirectory($savedDir)
            [System.IO.File]::WriteAllText((Join-Path $savedDir 'receipt.json'), (@{ PatchId = $savedId; ProfileId = 'x'; GameRoot = 'x' } | ConvertTo-Json))
        }
        Mock Test-TpmInteractiveInput { $true }
        Mock Read-HostSafe { if ($script:f99Answers.Count -gt 0) { return $script:f99Answers.Dequeue() }; return '' }
        # The menu compares the game file with the catalog hash before it plans a patch, so the entry carries the real hash of the fixture game file (all fixture games share the same bytes).
        Mock Read-TpmRequiredPatchCatalog {
            [pscustomobject]@{ Path = 'x'; Content = '{}'; CatalogSha256 = ('A' * 64); Schema = 3; Entries = @(
                [pscustomobject]@{ Id = 'alpha-main-one'; ProfileId = 'Alpha'; BuildName = 'Alpha Game (1.0)[TP]'; Executable = 'game.exe'; ExecutableSha256 = (Get-FileHash -LiteralPath $script:f99Lib.Exes['Beta'] -Algorithm SHA256).Hash; SourceSet = 'Pack.zip' }) }
        }
        Mock Read-PathWithBrowse { $script:f99Lib.Dirs[$script:f99Game] }
        Mock Resolve-TpmRequiredPatchSourceRoot { $script:f99Lib.Main }
        Mock New-TpmRequiredPatchPayloadStage {
            $stage = Join-Path $script:TpmOwnedLayout.Temp ('RequiredPatch-' + [guid]::NewGuid().ToString('N'))
            [void][System.IO.Directory]::CreateDirectory($stage)
            return [pscustomobject]@{ Root = $stage; Payload = (Join-Path $stage 'payload.bin') }
        }
        $script:f99Context = { param($Registered) [pscustomobject]@{ GamePath = $script:f99Lib.Exes[$script:f99Game]; GameRoot = $script:f99Lib.Dirs[$script:f99Game]; RecoveryRoot = (Join-Path $script:f99Lib.Root 'rec'); ProtectedRoots = @('x'); Registered = $Registered; ProfilePath = ''; ProfileSha256 = '' } }
        Mock Get-TpmManualPatchContext { & $script:f99Context $false }
        Mock Get-TpmRegisteredPatchContext { & $script:f99Context $true }
        Mock Get-TpmPatchPlan { [pscustomobject]@{ Status = 'AlreadyApplied'; Reason = '' } }
    }
    AfterEach {
        $script:TpmOwnedLayout = $null
        $script:gamesInstallFolder = $null
    }

    It 'blocks a game in the OTHER source folder before anything is staged or planned: <Case>' -ForEach @(
        @{ Case = 'install for one game (M)'; Answers = @('M', '1', '', '') }
        @{ Case = 'install for registered games (A)'; Answers = @('A', '', '') }
        @{ Case = 'undo (U)'; Answers = @('U', '1', '', '') }
    ) {
        # Mutation: take Assert-TpmPatchGameOutsideSourceFolders out of the menu (or pass only the ZIP's own source folder) -> the game in the supplementary folder is staged and planned.
        $before = Get-F99Guarded -Library $script:f99Lib
        foreach ($answer in $Answers) { [void]$script:f99Answers.Enqueue($answer) }
        Invoke-TpmRequiredPatchMenu -TpRoot $script:f99Lib.TpRoot -UserProfilesDir $script:f99Lib.Profiles -ManagerRoot $script:f99Lib.Root -ProgramRoot $script:f99Lib.Root -MainSource $script:f99Lib.Main -SupplementarySource $script:f99Lib.Supp
        Get-F99Guarded -Library $script:f99Lib | Should -BeExactly $before
        Should -Invoke New-TpmRequiredPatchPayloadStage -Times 0 -Exactly
        Should -Invoke Get-TpmPatchPlan -Times 0 -Exactly
        (Get-F99Text) | Should -Match ([regex]::Escape('This game is inside your source folder (where your game collection is kept). TeknoParrot Manager never changes your source folder. Move the game out of it, or fix the game folder in its profile.'))
        ($script:f99Log -join "`n") | Should -Match 'Required patch: refused game folder'
    }

    It 'still stages a patch for a game outside the source folders' {
        # Mutation: refuse every game once a source folder is configured -> a normal patch install is blocked.
        $script:f99Game = 'Beta'
        foreach ($answer in @('M', '1', '', '')) { [void]$script:f99Answers.Enqueue($answer) }
        Invoke-TpmRequiredPatchMenu -TpRoot $script:f99Lib.TpRoot -UserProfilesDir $script:f99Lib.Profiles -ManagerRoot $script:f99Lib.Root -ProgramRoot $script:f99Lib.Root -MainSource $script:f99Lib.Main -SupplementarySource $script:f99Lib.Supp
        Should -Invoke New-TpmRequiredPatchPayloadStage -Times 1 -Exactly
        Should -Invoke Get-TpmPatchPlan -Times 1 -Exactly
    }

    It 'undo does not call the variant that was never installed a conflict (AMD and NVIDIA versions of one patch)' {
        # Mutation: remove the exclusive-group check from the undo loop -> the NVIDIA version, never installed, is reported as a game file conflict next to the AMD one.
        $script:f99Game = 'Beta'
        $script:f99ExeHash = (Get-FileHash -LiteralPath $script:f99Lib.Exes['Beta'] -Algorithm SHA256).Hash
        Mock Read-TpmRequiredPatchCatalog {
            [pscustomobject]@{ Path = 'x'; Content = '{}'; CatalogSha256 = ('A' * 64); Schema = 3; Entries = @(
                [pscustomobject]@{ Id = 'alpha-amd'; ProfileId = 'Alpha'; BuildName = 'Alpha Game (1.0)[TP]'; Executable = 'game.exe'; ExecutableSha256 = $script:f99ExeHash; SourceSet = 'Pack.zip'; ExclusiveGroup = 'alpha.gpu' },
                [pscustomobject]@{ Id = 'alpha-nvidia'; ProfileId = 'Alpha'; BuildName = 'Alpha Game (1.0)[TP]'; Executable = 'game.exe'; ExecutableSha256 = $script:f99ExeHash; SourceSet = 'Pack.zip'; ExclusiveGroup = 'alpha.gpu' }) }
        }
        Mock Get-TpmPatchRecoveryDirectories { @() }
        Mock Get-TpmPatchPlan { if ($PatchId -ceq 'alpha-nvidia') { throw 'Grouped target conflict.' }; [pscustomobject]@{ Status = 'Ready'; Reason = '' } }
        foreach ($answer in @('U', '1', '', '')) { [void]$script:f99Answers.Enqueue($answer) }
        Invoke-TpmRequiredPatchMenu -TpRoot $script:f99Lib.TpRoot -UserProfilesDir $script:f99Lib.Profiles -ManagerRoot $script:f99Lib.Root -ProgramRoot $script:f99Lib.Root -MainSource $script:f99Lib.Main -SupplementarySource $script:f99Lib.Supp
        $screen = Get-F99Text
        $screen | Should -Not -Match 'Could not undo'
        $screen | Should -Match 'Nothing to undo'
    }

    It 'undo calls a variant that has no saved copy "nothing to undo", not a failure: <Case>' -ForEach @(
        @{ Case = 'the other card version looks installed but TeknoParrot Manager has no saved copy'; Plan = 'AlreadyApplied' }
        @{ Case = 'the other card version is the one that is installed'; Plan = 'ExclusiveActive' }
    ) {
        # Mutation: only the "Grouped target conflict." message counts as "never installed" -> the second version is shown as "Could not undo".
        $script:f99Game = 'Beta'
        $script:f99ExeHash = (Get-FileHash -LiteralPath $script:f99Lib.Exes['Beta'] -Algorithm SHA256).Hash
        $script:f99PlanCase = $Plan
        Mock Read-TpmRequiredPatchCatalog {
            [pscustomobject]@{ Path = 'x'; Content = '{}'; CatalogSha256 = ('A' * 64); Schema = 3; Entries = @(
                [pscustomobject]@{ Id = 'beta-amd'; ProfileId = 'Beta'; BuildName = 'Beta Game (1.0)[TP]'; Executable = 'game.exe'; ExecutableSha256 = $script:f99ExeHash; SourceSet = 'Pack.zip'; ExclusiveGroup = 'beta.gpu'; Operations = @() },
                [pscustomobject]@{ Id = 'beta-nvidia'; ProfileId = 'Beta'; BuildName = 'Beta Game (1.0)[TP]'; Executable = 'game.exe'; ExecutableSha256 = $script:f99ExeHash; SourceSet = 'Pack.zip'; ExclusiveGroup = 'beta.gpu'; Operations = @() }) }
        }
        Mock Get-TpmPatchRecoveryDirectories { @() }
        Mock Get-TpmPatchPlan {
            if ($script:f99PlanCase -eq 'ExclusiveActive') { throw 'An exclusive recipe is active; undo it before selecting another variant.' }
            [pscustomobject]@{ Status = 'AlreadyApplied'; Reason = '' }
        }
        foreach ($answer in @('U', '1', '', '')) { [void]$script:f99Answers.Enqueue($answer) }
        Invoke-TpmRequiredPatchMenu -TpRoot $script:f99Lib.TpRoot -UserProfilesDir $script:f99Lib.Profiles -ManagerRoot $script:f99Lib.Root -ProgramRoot $script:f99Lib.Root -MainSource $script:f99Lib.Main -SupplementarySource $script:f99Lib.Supp
        $screen = Get-F99Text
        $screen | Should -Not -Match 'Could not undo'
        $screen | Should -Match 'Nothing to undo'
    }

    It 'undo reports leftover files once as a cleanup note, not as the reason for the game it undoes: <Case>' -ForEach @(
        @{ Case = 'leftover belongs to another game'; Own = $false }
        @{ Case = 'leftover belongs to the game that is undone'; Own = $true }
    ) {
        $script:f99Game = 'Beta'
        $script:f99ExeHash = (Get-FileHash -LiteralPath $script:f99Lib.Exes['Beta'] -Algorithm SHA256).Hash
        Mock Read-TpmRequiredPatchCatalog {
            [pscustomobject]@{ Path = 'x'; Content = '{}'; CatalogSha256 = ('A' * 64); Schema = 3; Entries = @(
                [pscustomobject]@{ Id = 'beta-one'; ProfileId = 'Beta'; BuildName = 'Beta Game (1.0)[TP]'; Executable = 'game.exe'; ExecutableSha256 = $script:f99ExeHash; SourceSet = 'Pack.zip'; Operations = @() }) }
        }
        $recovery = Join-Path $script:f99Lib.Root 'rec'
        $ownDir = Join-Path $recovery ('a' * 32)
        $otherDir = Join-Path $recovery ('b' * 32)
        [void][System.IO.Directory]::CreateDirectory($ownDir)
        [void][System.IO.Directory]::CreateDirectory($otherDir)
        $leftoverDir = if ($Own) { $ownDir } else { $otherDir }
        [System.IO.File]::WriteAllText((Join-Path $leftoverDir ('receipt.json.' + ('c' * 32) + '.tmp')), 'partial')
        $script:f99OwnDir = $ownDir
        Mock Get-TpmPatchRecoveryDirectories { @($script:f99OwnDir) }
        Mock Read-TpmUndoReceipt { }
        Mock Undo-TpmCatalogPatch { [pscustomobject]@{ Status = 'Undone' } }
        Mock Read-HostSafe { if ([string]$Prompt -match 'Undo the patch for') { return 'Y' }; if ($script:f99Answers.Count -gt 0) { return $script:f99Answers.Dequeue() }; return '' }
        foreach ($answer in @('U', '1', '', '')) { [void]$script:f99Answers.Enqueue($answer) }
        Invoke-TpmRequiredPatchMenu -TpRoot $script:f99Lib.TpRoot -UserProfilesDir $script:f99Lib.Profiles -ManagerRoot $script:f99Lib.Root -ProgramRoot $script:f99Lib.Root -MainSource $script:f99Lib.Main -SupplementarySource $script:f99Lib.Supp
        $screen = Get-F99Text
        $screen | Should -Match 'Undone: '
        $screen | Should -Not -Match 'Left alone'
        $screen | Should -Not -Match 'Nothing was changed'
        @([regex]::Matches($screen, 'Cleanup note')).Count | Should -Be 1
        if ($Own) { $screen | Should -Match 'They belong to Beta' } else { $screen | Should -Not -Match 'They belong to' }
    }

    It 'asks for the patch ZIP only for the patch that fits this graphics card' {
        # Mutation: choose the graphics card version after the ZIP is asked for -> the NVIDIA version asks for its ZIP on an AMD PC and then reports a failure.
        $script:f99Game = 'Beta'
        $script:f99ExeHash = (Get-FileHash -LiteralPath $script:f99Lib.Exes['Beta'] -Algorithm SHA256).Hash
        Mock Get-TpmHardwareEnvironmentEvidence { [pscustomobject]@{} }
        Mock Get-TpmPatchHardwareVendor { [pscustomobject]@{ State = 'KNOWN'; Vendor = 'AMD'; Name = 'AMD Radeon'; Reason = '' } }
        Mock Read-TpmRequiredPatchCatalog {
            [pscustomobject]@{ Path = 'x'; Content = '{}'; CatalogSha256 = ('A' * 64); Schema = 3; Entries = @(
                [pscustomobject]@{ Id = 'beta-amd'; ProfileId = 'Beta'; BuildName = 'Beta Game (1.0)[TP]'; Executable = 'game.exe'; ExecutableSha256 = $script:f99ExeHash; SourceSet = 'AmdPack.zip'; ExclusiveGroup = 'beta.gpu'; HardwarePredicate = [pscustomobject]@{ Vendor = 'AMD' }; Prerequisites = @(); Operations = @() },
                [pscustomobject]@{ Id = 'beta-nvidia'; ProfileId = 'Beta'; BuildName = 'Beta Game (1.0)[TP]'; Executable = 'game.exe'; ExecutableSha256 = $script:f99ExeHash; SourceSet = 'NvidiaPack.zip'; ExclusiveGroup = 'beta.gpu'; HardwarePredicate = [pscustomobject]@{ Vendor = 'NVIDIA' }; Prerequisites = @(); Operations = @() },
                [pscustomobject]@{ Id = 'beta-nvidia-only'; ProfileId = 'Beta'; BuildName = 'Beta Game (2.0)[TP]'; Executable = 'game.exe'; ExecutableSha256 = $script:f99ExeHash; SourceSet = 'NvidiaOnly.zip'; ExclusiveGroup = ''; HardwarePredicate = [pscustomobject]@{ Vendor = 'NVIDIA' }; Prerequisites = @(); Operations = @() }) }
        }
        Mock Get-TpmPatchPlan { [pscustomobject]@{ Status = 'Ready'; Reason = ''; Target = 'x' } }
        foreach ($answer in @('A', '')) { [void]$script:f99Answers.Enqueue($answer) }
        Invoke-TpmRequiredPatchMenu -TpRoot $script:f99Lib.TpRoot -UserProfilesDir $script:f99Lib.Profiles -ManagerRoot $script:f99Lib.Root -ProgramRoot $script:f99Lib.Root -MainSource $script:f99Lib.Main -SupplementarySource $script:f99Lib.Supp
        Should -Invoke Resolve-TpmRequiredPatchSourceRoot -Times 1 -Exactly -ParameterFilter { $Entry.Id -ceq 'beta-amd' }
        Should -Invoke Resolve-TpmRequiredPatchSourceRoot -Times 1 -Exactly
        Get-F99Text | Should -Not -Match 'Could not install'
    }

    It 'asks for the ZIP only of the build that is installed, and does not call the other builds a failure: <Case>' -ForEach @(
        @{ Case = 'install for registered games (A)'; Answers = @('A', '') }
        @{ Case = 'install for one game (M)'; Answers = @('M', '1', '', '') }
    ) {
        # Mutation: check the game file after the ZIP is asked for -> the build the user does not have asks for its own ZIP and shows "Could not install".
        $script:f99Game = 'Beta'
        $script:f99ExeHash = (Get-FileHash -LiteralPath $script:f99Lib.Exes['Beta'] -Algorithm SHA256).Hash
        Mock Read-TpmRequiredPatchCatalog {
            [pscustomobject]@{ Path = 'x'; Content = '{}'; CatalogSha256 = ('A' * 64); Schema = 3; Entries = @(
                [pscustomobject]@{ Id = 'beta-old'; ProfileId = 'Beta'; BuildName = 'Beta Game (1.0)[TP]'; Executable = 'game.exe'; ExecutableSha256 = ('B' * 64); SourceSet = 'OldPack.zip'; Prerequisites = @(); Operations = @() },
                [pscustomobject]@{ Id = 'beta-new'; ProfileId = 'Beta'; BuildName = 'Beta Game (1.0)[TP]'; Executable = 'game.exe'; ExecutableSha256 = $script:f99ExeHash; SourceSet = 'NewPack.zip'; Prerequisites = @(); Operations = @() }) }
        }
        Mock Get-TpmPatchPlan { [pscustomobject]@{ Status = 'Ready'; Reason = ''; Target = 'x' } }
        foreach ($answer in $Answers) { [void]$script:f99Answers.Enqueue($answer) }
        Invoke-TpmRequiredPatchMenu -TpRoot $script:f99Lib.TpRoot -UserProfilesDir $script:f99Lib.Profiles -ManagerRoot $script:f99Lib.Root -ProgramRoot $script:f99Lib.Root -MainSource $script:f99Lib.Main -SupplementarySource $script:f99Lib.Supp
        Should -Invoke Resolve-TpmRequiredPatchSourceRoot -Times 1 -Exactly -ParameterFilter { $Entry.Id -ceq 'beta-new' }
        Should -Invoke Resolve-TpmRequiredPatchSourceRoot -Times 0 -Exactly -ParameterFilter { $Entry.Id -ceq 'beta-old' }
        Get-F99Text | Should -Not -Match 'Could not install'
    }

    It 'still says "Could not install" when no build in the list matches the installed game' {
        # Mutation: treat every wrong-build result as a quiet skip -> a user whose game version is not supported is told nothing went wrong.
        $script:f99Game = 'Beta'
        Mock Read-TpmRequiredPatchCatalog {
            [pscustomobject]@{ Path = 'x'; Content = '{}'; CatalogSha256 = ('A' * 64); Schema = 3; Entries = @(
                [pscustomobject]@{ Id = 'beta-old'; ProfileId = 'Beta'; BuildName = 'Beta Game (1.0)[TP]'; Executable = 'game.exe'; ExecutableSha256 = ('B' * 64); SourceSet = 'OldPack.zip'; Prerequisites = @(); Operations = @() }) }
        }
        foreach ($answer in @('A', '', '')) { [void]$script:f99Answers.Enqueue($answer) }
        Invoke-TpmRequiredPatchMenu -TpRoot $script:f99Lib.TpRoot -UserProfilesDir $script:f99Lib.Profiles -ManagerRoot $script:f99Lib.Root -ProgramRoot $script:f99Lib.Root -MainSource $script:f99Lib.Main -SupplementarySource $script:f99Lib.Supp
        Should -Invoke Resolve-TpmRequiredPatchSourceRoot -Times 0 -Exactly
        Get-F99Text | Should -Match 'Could not install'
    }

    It 'ignores the basic display adapter when choosing the graphics card version, and does not ask which card' {
        # Mutation: pass Windows' raw adapter list on (it holds the basic display adapter next to the real card) -> the card is "not established" and every NVIDIA/AMD patch is refused.
        $script:f99Game = 'Beta'
        $script:f99ExeHash = (Get-FileHash -LiteralPath $script:f99Lib.Exes['Beta'] -Algorithm SHA256).Hash
        Mock Get-TpmHardwareEnvironmentEvidence {
            [pscustomobject]@{ Adapters = @([pscustomobject]@{ Name = 'Microsoft Basic Display Adapter' }, [pscustomobject]@{ Name = 'NVIDIA GeForce RTX 4060' }); ActiveAdapterIndex = $null; ActiveAdapterName = $null; ActiveGpuConfidence = 'UNKNOWN'; MultiGpuAmbiguous = $true }
        }
        Mock Read-TpmRequiredPatchCatalog {
            [pscustomobject]@{ Path = 'x'; Content = '{}'; CatalogSha256 = ('A' * 64); Schema = 3; Entries = @(
                [pscustomobject]@{ Id = 'beta-amd'; ProfileId = 'Beta'; BuildName = 'Beta Game (1.0)[TP]'; Executable = 'game.exe'; ExecutableSha256 = $script:f99ExeHash; SourceSet = 'AmdPack.zip'; ExclusiveGroup = 'beta.gpu'; HardwarePredicate = [pscustomobject]@{ Vendor = 'AMD' }; Prerequisites = @(); Operations = @() },
                [pscustomobject]@{ Id = 'beta-nvidia'; ProfileId = 'Beta'; BuildName = 'Beta Game (1.0)[TP]'; Executable = 'game.exe'; ExecutableSha256 = $script:f99ExeHash; SourceSet = 'NvidiaPack.zip'; ExclusiveGroup = 'beta.gpu'; HardwarePredicate = [pscustomobject]@{ Vendor = 'NVIDIA' }; Prerequisites = @(); Operations = @() }) }
        }
        Mock Get-TpmPatchPlan { [pscustomobject]@{ Status = 'Ready'; Reason = ''; Target = 'x' } }
        foreach ($answer in @('A', '')) { [void]$script:f99Answers.Enqueue($answer) }
        Invoke-TpmRequiredPatchMenu -TpRoot $script:f99Lib.TpRoot -UserProfilesDir $script:f99Lib.Profiles -ManagerRoot $script:f99Lib.Root -ProgramRoot $script:f99Lib.Root -MainSource $script:f99Lib.Main -SupplementarySource $script:f99Lib.Supp
        Should -Invoke Resolve-TpmRequiredPatchSourceRoot -Times 1 -Exactly -ParameterFilter { $Entry.Id -ceq 'beta-nvidia' }
        Should -Invoke Resolve-TpmRequiredPatchSourceRoot -Times 0 -Exactly -ParameterFilter { $Entry.Id -ceq 'beta-amd' }
        Get-F99Text | Should -Not -Match 'could not be matched|more than one graphics card'
    }

    It 'asks which card the game uses when two real cards are different makes, and installs only that card''s patch' {
        # Mutation: refuse every graphics-card patch whenever there are two adapters (the old rule) -> the NVIDIA patch is never offered on a laptop with Intel and NVIDIA.
        $script:f99Game = 'Beta'
        $script:f99ExeHash = (Get-FileHash -LiteralPath $script:f99Lib.Exes['Beta'] -Algorithm SHA256).Hash
        Mock Get-TpmHardwareEnvironmentEvidence {
            [pscustomobject]@{ Adapters = @([pscustomobject]@{ Name = 'Intel(R) UHD Graphics' }, [pscustomobject]@{ Name = 'NVIDIA GeForce RTX 4060' }); ActiveAdapterIndex = $null; ActiveAdapterName = $null; ActiveGpuConfidence = 'UNKNOWN'; MultiGpuAmbiguous = $true }
        }
        Mock Read-TpmRequiredPatchCatalog {
            [pscustomobject]@{ Path = 'x'; Content = '{}'; CatalogSha256 = ('A' * 64); Schema = 3; Entries = @(
                [pscustomobject]@{ Id = 'beta-amd'; ProfileId = 'Beta'; BuildName = 'Beta Game (1.0)[TP]'; Executable = 'game.exe'; ExecutableSha256 = $script:f99ExeHash; SourceSet = 'AmdPack.zip'; ExclusiveGroup = 'beta.gpu'; HardwarePredicate = [pscustomobject]@{ Vendor = 'AMD' }; Prerequisites = @(); Operations = @() },
                [pscustomobject]@{ Id = 'beta-nvidia'; ProfileId = 'Beta'; BuildName = 'Beta Game (1.0)[TP]'; Executable = 'game.exe'; ExecutableSha256 = $script:f99ExeHash; SourceSet = 'NvidiaPack.zip'; ExclusiveGroup = 'beta.gpu'; HardwarePredicate = [pscustomobject]@{ Vendor = 'NVIDIA' }; Prerequisites = @(); Operations = @() }) }
        }
        Mock Get-TpmPatchPlan { [pscustomobject]@{ Status = 'Ready'; Reason = ''; Target = 'x' } }
        foreach ($answer in @('A', '2', '')) { [void]$script:f99Answers.Enqueue($answer) }
        Invoke-TpmRequiredPatchMenu -TpRoot $script:f99Lib.TpRoot -UserProfilesDir $script:f99Lib.Profiles -ManagerRoot $script:f99Lib.Root -ProgramRoot $script:f99Lib.Root -MainSource $script:f99Lib.Main -SupplementarySource $script:f99Lib.Supp
        Get-F99Text | Should -Match 'more than one graphics card.*1\) Intel\(R\) UHD Graphics 2\) NVIDIA GeForce RTX 4060'
        Should -Invoke Resolve-TpmRequiredPatchSourceRoot -Times 1 -Exactly -ParameterFilter { $Entry.Id -ceq 'beta-nvidia' }
        Should -Invoke Resolve-TpmRequiredPatchSourceRoot -Times 0 -Exactly -ParameterFilter { $Entry.Id -ceq 'beta-amd' }
    }

    Context 'a patch that lays a file on top of a file another patch creates' {
        BeforeEach {
            $script:f99Game = 'Beta'
            $script:f99ExeHash = (Get-FileHash -LiteralPath $script:f99Lib.Exes['Beta'] -Algorithm SHA256).Hash
            $script:f99Installed = New-Object System.Collections.Generic.List[string]
            $script:f99Layers = @(
                [pscustomobject]@{ Id = 'beta-top'; ProfileId = 'Beta'; BuildName = 'Beta Game (1.0)[TP]'; Executable = 'game.exe'; ExecutableSha256 = $script:f99ExeHash; SourceSet = 'Pack.zip'; ExclusiveGroup = ''; Prerequisites = @(); Operations = @([pscustomobject]@{ Type = 'ReplaceFile'; Target = 'rom/a.bin'; BeforeSha256 = ('B' * 64); AfterSha256 = ('C' * 64) }) },
                [pscustomobject]@{ Id = 'beta-base'; ProfileId = 'Beta'; BuildName = 'Beta Game (1.0)[TP]'; Executable = 'game.exe'; ExecutableSha256 = $script:f99ExeHash; SourceSet = 'Pack.zip'; ExclusiveGroup = ''; Prerequisites = @(); Operations = @([pscustomobject]@{ Type = 'CreateFile'; Target = 'rom/a.bin'; BeforeState = 'Absent'; AfterSha256 = ('B' * 64) }) })
            Mock Get-TpmPatchPlan { if ($PatchId -ceq 'beta-top') { return [pscustomobject]@{ Status = 'Unavailable'; Reason = 'Grouped target conflict.' } }; [pscustomobject]@{ Status = 'Ready'; Reason = ''; Target = 'x' } }
            Mock Invoke-TpmCatalogPatch { [void]$script:f99Installed.Add([string]$PatchId); [pscustomobject]@{ Status = 'Applied'; RecoveryDirectory = 'r' } }
        }

        It 'installs the patch that creates the file first, then the one on top, with no failure line' {
            # Mutation: report the top patch as "different file" while planning -> the user sees a failure for a patch that installs fine one step later.
            Mock Read-TpmRequiredPatchCatalog { [pscustomobject]@{ Path = 'x'; Content = '{}'; CatalogSha256 = ('A' * 64); Schema = 3; Entries = $script:f99Layers } }
            foreach ($answer in @('A', 'Y', '')) { [void]$script:f99Answers.Enqueue($answer) }
            Invoke-TpmRequiredPatchMenu -TpRoot $script:f99Lib.TpRoot -UserProfilesDir $script:f99Lib.Profiles -ManagerRoot $script:f99Lib.Root -ProgramRoot $script:f99Lib.Root -MainSource $script:f99Lib.Main -SupplementarySource $script:f99Lib.Supp
            $script:f99Installed -join ',' | Should -BeExactly 'beta-base,beta-top'
            Get-F99Text | Should -Not -Match 'Could not install'
        }

        It 'still refuses the top patch when no patch in the run creates the file under it' {
            # Mutation: wait for any patch, not only the one that creates the file -> a game file the user changed is no longer reported.
            Mock Read-TpmRequiredPatchCatalog { [pscustomobject]@{ Path = 'x'; Content = '{}'; CatalogSha256 = ('A' * 64); Schema = 3; Entries = @($script:f99Layers[0]) } }
            foreach ($answer in @('A', '')) { [void]$script:f99Answers.Enqueue($answer) }
            Invoke-TpmRequiredPatchMenu -TpRoot $script:f99Lib.TpRoot -UserProfilesDir $script:f99Lib.Profiles -ManagerRoot $script:f99Lib.Root -ProgramRoot $script:f99Lib.Root -MainSource $script:f99Lib.Main -SupplementarySource $script:f99Lib.Supp
            $script:f99Installed.Count | Should -Be 0
            Get-F99Text | Should -Match 'Could not install'
        }
    }
}

Describe 'FIX99 the required-patch source-folder check' {
    BeforeEach { Install-F99Console }

    It 'refuses a game folder in either source folder, through a junction too, and accepts one outside' {
        # Mutation: compare against the ZIP source only, or by spelled path only -> the other folder, or a junction to it, passes.
        $library = New-F99Library -Spec @(@{ Code = 'InMain'; Where = 'Main' }, @{ Code = 'InSupp'; Where = 'Supp' }, @{ Code = 'Outside'; Where = 'Games' })
        $folders = @($library.Main, $library.Supp)
        { Assert-TpmPatchGameOutsideSourceFolders -GameRoot $library.Dirs['InMain'] -SourceFolders $folders } | Should -Throw '*inside your source folder*'
        { Assert-TpmPatchGameOutsideSourceFolders -GameRoot $library.Dirs['InSupp'] -SourceFolders $folders } | Should -Throw '*inside your source folder*'
        { Assert-TpmPatchGameOutsideSourceFolders -GameRoot $library.Dirs['Outside'] -SourceFolders $folders } | Should -Not -Throw
        { Assert-TpmPatchGameOutsideSourceFolders -GameRoot $library.Dirs['InMain'] -SourceFolders @('', $null) } | Should -Not -Throw
        $link = Join-Path $library.Root 'SuppLink'
        $junction = New-F99Junction -Link $link -Target $library.Supp
        if (-not $junction.Created) { Set-ItResult -Skipped -Because $junction.Because; return }
        try { { Assert-TpmPatchGameOutsideSourceFolders -GameRoot $library.Dirs['InSupp'] -SourceFolders @($link) } | Should -Throw '*inside your source folder*' }
        finally { & cmd.exe /d /c ('rmdir "{0}"' -f $link) | Out-Null }
    }
}
