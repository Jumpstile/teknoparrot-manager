#Requires -Module Pester

# FIX107 (NEW-B2): the source-collection guard (owner rule R6) in the BepInEx update (menu 9).
#   TeknoParrot Manager never writes inside the configured source collection (main source folder and supplementary source folder).
#   FIX96 did this for ReShade and FIX99 for dgVoodoo2, Crosshair and the force feedback plugin. BepInEx still trusted the saved games root:
#   a saved games folder inside a source folder let the update stage, back up and promote files inside the collection.
#   Invoke-BepInExUpdateCheck now takes the two source folders (-ProtectedRoots) and refuses such a game before any release lookup,
#   download, backup or write. Every later game-folder check (before staging, before backup, before promotion) passes them too.
# These tests drive the real product functions with synthetic folders in $TestDrive; nothing touches TeknoParrot, LaunchBox, the registry,
# services or the network. Each It names the product change that makes it fail.
# What this CANNOT prove: that the menu passes the two source folders to the update (the menu is script body, not a function) or a real
# BepInEx download (the release lookup and download are replaced by fixtures).

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $script:f107Ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX107 bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'fix107-bep-functions.ps1'
    ($script:f107Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:DisplayVersion = 'v1.0 RC8'
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false
    $script:logPath = Join-Path $TestDrive 'fix107-bep.log'
    $script:logWarnShown = $false
    $script:f107RealMutationPath = ${function:Test-TpmGameMutationPath}
    $script:f107RefusalOne = 'Not changed: 1 game is inside your source folder (where your game collection is kept).'

    function Get-F107Text {
        return (((@($script:f107Rows | ForEach-Object { ([string]$_).Trim() }) -join ' ') -replace '\s+', ' ').Trim())
    }
    function New-F107Root {
        param([string]$Name)
        $root = Join-Path $TestDrive ($Name + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        [void][System.IO.Directory]::CreateDirectory($root)
        return $root
    }
    # One line per folder and per file (with the SHA-256 of the file) under the paths: two equal snapshots are byte-for-byte the same tree.
    function Get-F107Snapshot {
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
    # A library of games, each with a game file and a profile. A game is in the main source folder (Main), the supplementary source folder
    # (Supp) or in the games folder (Games); its folder is named like its code.
    function New-F107Library {
        param([Parameter(Mandatory)][hashtable[]]$Spec)
        $root = New-F107Root 'library'
        $library = [ordered]@{
            Root = $root; Profiles = (Join-Path $root 'UserProfiles'); Cache = (Join-Path $root 'BepCache')
            Main = (Join-Path $root 'Collection'); Supp = (Join-Path $root 'Supplementary'); Games = (Join-Path $root 'Games')
            Exes = @{}; Dirs = @{}; ProfileFiles = @{}
        }
        foreach ($folder in @($library.Profiles, $library.Main, $library.Supp, $library.Games)) { [void][System.IO.Directory]::CreateDirectory($folder) }
        foreach ($game in $Spec) {
            $parent = switch ([string]$game.Where) { 'Main' { Join-Path $library.Main 'Unpacked' } 'Supp' { Join-Path $library.Supp 'Unpacked' } default { $library.Games } }
            $dir = Join-Path $parent ([string]$game.Code)
            [void][System.IO.Directory]::CreateDirectory($dir)
            $exe = Join-Path $dir 'game.exe'
            [System.IO.File]::WriteAllText($exe, 'MZ-test-game')
            $profile = Join-Path $library.Profiles ([string]$game.Code + '.xml')
            [System.IO.File]::WriteAllText($profile, ('<GameProfile><GameName>Game {0}</GameName><GamePath>{1}</GamePath></GameProfile>' -f $game.Code, [System.Security.SecurityElement]::Escape($exe)), (New-Object System.Text.UTF8Encoding $false))
            $library.Exes[[string]$game.Code] = $exe
            $library.Dirs[[string]$game.Code] = $dir
            $library.ProfileFiles[[string]$game.Code] = $profile
        }
        return [pscustomobject]$library
    }
    function Get-F107Guarded {
        param($Library)
        return (Get-F107Snapshot -Path (@($Library.Main, $Library.Supp) + @($Library.ProfileFiles.Values)))
    }
}

Describe 'FIX107 BepInEx never updates a game inside the source collection' {
    BeforeEach {
        $script:f107Rows = New-Object System.Collections.Generic.List[string]
        $script:f107Log = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { [void]$script:f107Rows.Add([string]($Object -join ' ')) }
        Mock Write-Log { [void]$script:f107Log.Add([string]$msg) }
        Mock Get-ConsoleContentWidth { return 120 }
        Mock Write-TpmCompactExtractionProgress {}
        Mock Get-BepInExLatestRelease { throw 'release lookup must not run for a game inside the source folder' }
        Mock Invoke-TpmDownload { throw 'download must not run for a game inside the source folder' }
    }

    It 'refuses a game inside the <Where> source folder when the saved games folder is inside it: nothing is written, the screen says why' -ForEach @(
        @{ Where = 'Main' }
        @{ Where = 'Supp' }
    ) {
        # Mutation: do not pass -ProtectedRoots to the preflight Test-TpmGameMutationPath call of Invoke-BepInExUpdateCheckLegacy -> the game is accepted (the saved games folder is its own approved root) and reaches the update.
        $library = New-F107Library -Spec @(@{ Code = 'InsideGame'; Where = $Where })
        $approved = if ($Where -eq 'Main') { $library.Main } else { $library.Supp }
        $before = Get-F107Guarded -Library $library
        $result = Invoke-BepInExUpdateCheck -UserProfilesDir $library.Profiles -CacheDir $library.Cache -ApprovedGamesRoot $approved -ProtectedRoots @($library.Main, $library.Supp)
        Get-F107Guarded -Library $library | Should -BeExactly $before
        Test-Path -LiteralPath $library.Cache | Should -BeFalse
        $result.Succeeded | Should -BeFalse
        $result.Reason | Should -BeExactly 'NO_ELIGIBLE_GAMES'
        $result.Updated | Should -Be 0
        @($result.FailureRecords)[0].ReasonKey | Should -BeExactly 'SOURCE_COLLECTION'
        @($result.FailureRecords)[0].NextAction | Should -Match 'Move the game out of your source folder'
        $text = Get-F107Text
        $text | Should -Match ([regex]::Escape($script:f107RefusalOne))
        $text | Should -Not -Match 'SOURCE_COLLECTION'
        Should -Invoke Get-BepInExLatestRelease -Times 0 -Exactly
        Should -Invoke Invoke-TpmDownload -Times 0 -Exactly
        ($script:f107Log -join "`n") | Should -Match 'BepInEx: skipped InsideGame during path preflight; reason=SOURCE_COLLECTION'
    }

    It 'still looks at a game outside the source folders while it refuses the one inside' {
        # Mutation: refuse every game once one game is inside a source folder (or none) -> the outside game is never inspected, or the inside one is.
        $library = New-F107Library -Spec @(@{ Code = 'InsideGame'; Where = 'Main' }, @{ Code = 'OutsideGame'; Where = 'Games' })
        $before = Get-F107Guarded -Library $library
        $result = Invoke-BepInExUpdateCheck -UserProfilesDir $library.Profiles -CacheDir $library.Cache -ApprovedGamesRoot $library.Root -ProtectedRoots @($library.Main, $library.Supp)
        Get-F107Guarded -Library $library | Should -BeExactly $before
        $inside = @($result.FailureRecords | Where-Object Game -eq 'InsideGame')
        $inside.Count | Should -Be 1
        $inside[0].ReasonKey | Should -BeExactly 'SOURCE_COLLECTION'
        $outside = @($result.FailureRecords | Where-Object Game -eq 'OutsideGame')
        $outside.Count | Should -Be 1
        $outside[0].Operation | Should -BeExactly 'inspection'
        $outside[0].ReasonKey | Should -Not -BeExactly 'SOURCE_COLLECTION'
        (Get-F107Text) | Should -Match ([regex]::Escape($script:f107RefusalOne))
    }

    It 'checks every game folder with both source folders: before the update is staged, backed up and promoted' {
        # Mutation: drop -ProtectedRoots from any of the three mutation-boundary Test-TpmGameMutationPath calls of the update loop -> that call sees no source folder.
        $library = New-F107Library -Spec @(@{ Code = 'OutsideGame'; Where = 'Games' })
        $script:f107Calls = New-Object System.Collections.Generic.List[string]
        Mock Test-TpmGameMutationPath {
            [void]$script:f107Calls.Add((@($ProtectedRoots | ForEach-Object { [string]$_ }) -join '|'))
            & $script:f107RealMutationPath @PesterBoundParameters
        }
        $script:f107StageRoot = New-F107Root 'stage'
        Mock Test-BepInExGameRootSafe { $true }
        Mock Test-BepInExNoReparsePath { $true }
        Mock Test-BepInExExistingTreeSafe { $true }
        Mock Test-BepInExPackagePathSafe { $true }
        Mock Get-BepInExPeArchitectureEvidence { [pscustomobject]@{ State = 'SUPPORTED'; Architecture = 'x64'; Reason = 'supported fixture' } }
        Mock Get-BepInExLatestRelease { [pscustomobject]@{ Version = '5.4.23'; DownloadUrl = 'https://example.invalid/BepInEx_win_x64_5.4.23.zip'; FileName = 'BepInEx_win_x64_5.4.23.zip'; SizeBytes = 1; ExpectedSha256 = $null } }
        Mock Get-BepInExInstalledVersion { '5.4.22' }
        Mock Get-BepInExInstallationHealth { [pscustomobject]@{ Installed = $true; Complete = $true; Version = '5.4.22'; Architecture = 'x64'; Reason = 'Complete' } }
        Mock Read-HostSafe { 'Y' }
        Mock Invoke-TpmDownload { Set-Content -LiteralPath $DestinationPath -Value 'verified package' -NoNewline; $true }
        Mock New-TpmStagingDirectory { $dir = Join-Path $script:f107StageRoot ([guid]::NewGuid().ToString('N')); [void][System.IO.Directory]::CreateDirectory($dir); return $dir }
        Mock Expand-ZipFileSafe {}
        Mock Get-BepInExStagedFiles { @('BepInEx\core.dll') }
        Mock New-BepInExUpdateBackup { Join-Path $library.Dirs['OutsideGame'] 'BepInEx_Backup_test' }
        Mock Invoke-TpmTransactionalTreePromote { $true }
        Mock Remove-BepInExStagingDirectory { $true }
        $roots = @($library.Main, $library.Supp)
        $expected = ($roots -join '|')

        $result = Invoke-BepInExUpdateCheck -UserProfilesDir $library.Profiles -CacheDir $library.Cache -ApprovedGamesRoot $library.Games -ProtectedRoots $roots

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        Should -Invoke Invoke-TpmTransactionalTreePromote -Times 1 -Exactly
        $script:f107Calls.Count | Should -Be 4 -Because 'one preflight check and three checks around staging, backup and promotion'
        @($script:f107Calls | Where-Object { $_ -ceq $expected }).Count | Should -Be 4
    }

    It 'updates a game when no source folder is configured' {
        # Mutation: refuse every game when ProtectedRoots is empty -> a user without a source folder can no longer update BepInEx (no promotion, no accounting).
        $library = New-F107Library -Spec @(@{ Code = 'OutsideGame'; Where = 'Games' })
        $script:f107StageRoot = New-F107Root 'stage'
        Mock Test-BepInExGameRootSafe { $true }
        Mock Test-BepInExNoReparsePath { $true }
        Mock Test-BepInExExistingTreeSafe { $true }
        Mock Test-BepInExPackagePathSafe { $true }
        Mock Get-BepInExPeArchitectureEvidence { [pscustomobject]@{ State = 'SUPPORTED'; Architecture = 'x64'; Reason = 'supported fixture' } }
        Mock Get-BepInExLatestRelease { [pscustomobject]@{ Version = '5.4.23'; DownloadUrl = 'https://example.invalid/BepInEx_win_x64_5.4.23.zip'; FileName = 'BepInEx_win_x64_5.4.23.zip'; SizeBytes = 1; ExpectedSha256 = $null } }
        Mock Get-BepInExInstalledVersion { '5.4.22' }
        Mock Get-BepInExInstallationHealth { [pscustomobject]@{ Installed = $true; Complete = $true; Version = '5.4.22'; Architecture = 'x64'; Reason = 'Complete' } }
        Mock Read-HostSafe { 'Y' }
        Mock Invoke-TpmDownload { Set-Content -LiteralPath $DestinationPath -Value 'verified package' -NoNewline; $true }
        Mock New-TpmStagingDirectory { $dir = Join-Path $script:f107StageRoot ([guid]::NewGuid().ToString('N')); [void][System.IO.Directory]::CreateDirectory($dir); return $dir }
        Mock Expand-ZipFileSafe {}
        Mock Get-BepInExStagedFiles { @('BepInEx\core.dll') }
        Mock New-BepInExUpdateBackup { Join-Path $library.Dirs['OutsideGame'] 'BepInEx_Backup_test' }
        Mock Invoke-TpmTransactionalTreePromote { $true }
        Mock Remove-BepInExStagingDirectory { $true }
        $result = Invoke-BepInExUpdateCheck -UserProfilesDir $library.Profiles -CacheDir $library.Cache -ApprovedGamesRoot $library.Games -ProtectedRoots @('', $null)
        @($result.FailureRecords | Where-Object ReasonKey -eq 'SOURCE_COLLECTION').Count | Should -Be 0
        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        $result.Updated | Should -Be 1
        Should -Invoke Invoke-TpmTransactionalTreePromote -Times 1 -Exactly
        (Get-F107Text) | Should -Not -Match 'inside your source folder'
    }
}
