#Requires -Module Pester

# Menu 8 (Force feedback) installs the CURRENT plugin release with each game's own settings file and sets the wheel.
# What a user sees or loses is tested here with a fake release ZIP and fake answers (no network, no real plugin files):
#   - the plugin, the game's own FFBPlugin.ini and SDL2.dll are placed, and all three are recorded so removal works
#   - a file that is not ours, a settings file the user changed, and a game's own SDL2.dll are never overwritten
#   - nothing changes until the user says yes; a bad ZIP changes nothing; every replaced file is backed up
#   - the wheel id is built from the USB numbers and written into the settings file
#   - with no network a saved, hash-checked copy is offered; a damaged copy is not
# Synthetic folders in $TestDrive only.

BeforeAll {
    $script:Tree = (Split-Path -Parent $PSScriptRoot)
    $scriptPath = Join-Path $script:Tree 'TeknoParrot-Manager.ps1'
    $tokens = $null; $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errs)
    if ($errs.Count -gt 0) { throw 'parse failed' }
    $fa = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $fx = Join-Path $TestDrive 'fn.ps1'
    ($fa | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $fx -Encoding utf8
    $pm = Join-Path $TestDrive 'scripts'
    [void][IO.Directory]::CreateDirectory($pm)
    Copy-Item -LiteralPath (Join-Path $script:Tree 'scripts\TpmProgress.psm1') -Destination $pm -Force
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $fx
    . (Join-Path $script:Tree 'Tests\TpmExtractedScriptState.ps1')
    . (Join-Path $script:Tree 'Tests\FfbPluginTestKit.ps1')
    $script:TitleTokenStopWords = [System.Collections.Generic.HashSet[string]]::new([string[]]@('the','of','a','an','and'), [System.StringComparer]::OrdinalIgnoreCase)
    $script:FFBBlasterUnsupportedPlatforms = @('pcsx2x6')
    $script:FFBBlasterNamePattern = 'ffb.*blaster|blaster.*ffb'
    $script:RawThrillsPathLimits = @{}
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false

    # One registered game with a real (tiny) 32-bit or 64-bit program file.
    function New-R92Library {
        param([string]$Name, [string]$Game = 'FixtureGame', [string]$Arch = 'x64')
        $root = Join-Path $TestDrive $Name
        $up = Join-Path $root 'UserProfiles'; $cache = Join-Path $root 'FFBPlugin'; $dir = Join-Path $root $Game
        New-Item -ItemType Directory -Path $up, $cache, $dir -Force | Out-Null
        $exe = Join-Path $dir ($Game + '.exe')
        [IO.File]::WriteAllBytes($exe, (New-FfbTestPe -Arch $Arch))
        [IO.File]::WriteAllText((Join-Path $up ($Game + '.xml')), ('<GameProfile><EmulationProfile>{0}</EmulationProfile><GamePath>{1}</GamePath></GameProfile>' -f $Game, $exe), (New-Object System.Text.UTF8Encoding $false))
        return [pscustomobject]@{ Root = $root; Up = $up; Cache = $cache; Dir = $dir; Exe = $exe }
    }
    function Get-R92Owned { param($Lib) return @(Read-FFBPluginOwnership -CacheDir $Lib.Cache) }
}

Describe 'Force feedback plugin release install' {
    BeforeEach {
        $script:r92Shown = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-Host { [void]$script:r92Shown.Add([string]($Object -join ' ')) }
        Mock Write-Log {}
        $script:r92Tag = 'v.9.9.9.9'
        $script:r92Map = [ordered]@{ FixtureGame = 'd3d9.dll' }
        $script:r92Zip = @{}
        $script:r92Go = 'Y'
        $script:r92ReplaceIni = 'N'
        Mock Get-FFBPluginLatestRelease { New-FfbTestRelease -Tag $script:r92Tag }
        Mock Get-FFBPluginGameMap { $script:r92Map }
        Mock Invoke-FFBPluginDownload { param([string]$destDir, [object]$Release) New-FFBDownloadFixtureResult -destDir $destDir -Release $Release -ZipOptions $script:r92Zip }
        Mock Read-TpmYesNo {
            if ($Prompt -match 'Go ahead') { $script:r92Go }
            elseif ($Prompt -match 'Replace your file') { $script:r92ReplaceIni }
            else { 'Y' }
        }
    }

    It 'places the plugin under the game DLL name with the game own settings file and SDL2.dll, and records all three' {
        # Mutation: deploy only the DLL (the old behavior) -> the game has no settings file and the plugin reads the default GameId 0.
        $lib = New-R92Library -Name 'three'
        $result = Invoke-FFBPluginSetup -UserProfilesDir $lib.Up -CacheDir $lib.Cache
        $result.Succeeded | Should -BeTrue
        $result.Deployed | Should -Be 1
        foreach ($name in 'd3d9.dll', 'FFBPlugin.ini', 'SDL2.dll') { Test-Path -LiteralPath (Join-Path $lib.Dir $name) -PathType Leaf | Should -BeTrue -Because $name }
        (Get-Content -LiteralPath (Join-Path $lib.Dir 'FFBPlugin.ini') -Raw) | Should -Match 'Game=FixtureGame'
        $owned = Get-R92Owned -Lib $lib
        $owned.Count | Should -Be 3
        @($owned | ForEach-Object { [string]$_.Kind } | Sort-Object) | Should -Be @('Dll', 'Ini', 'Sdl2')
        foreach ($record in $owned) { (Get-FileHash -LiteralPath $record.Destination -Algorithm SHA256).Hash | Should -BeExactly ([string]$record.DeployedSha256) }
        ($script:r92Shown -join "`n") | Should -Match 'Using FFB Arcade Plugin v\.9\.9\.9\.9'
    }

    It 'writes the chosen wheel into the settings file and keeps every other byte' {
        $lib = New-R92Library -Name 'wheel'
        $guid = '6d044fc2000000000000504944564944'
        $result = Invoke-FFBPluginSetup -UserProfilesDir $lib.Up -CacheDir $lib.Cache -DeviceGuid $guid
        $result.Succeeded | Should -BeTrue
        $text = Get-Content -LiteralPath (Join-Path $lib.Dir 'FFBPlugin.ini') -Raw
        $text | Should -Be "[Settings]`r`nGameId=7`r`nDeviceGUID=$guid`r`nGame=FixtureGame`r`n"
    }

    It 'never overwrites an SDL2.dll the game already has' {
        $lib = New-R92Library -Name 'ownsdl'
        [IO.File]::WriteAllText((Join-Path $lib.Dir 'SDL2.dll'), 'games-own-sdl')
        $result = Invoke-FFBPluginSetup -UserProfilesDir $lib.Up -CacheDir $lib.Cache
        $result.Deployed | Should -Be 1
        (Get-Content -LiteralPath (Join-Path $lib.Dir 'SDL2.dll') -Raw) | Should -Be 'games-own-sdl'
        @(Get-R92Owned -Lib $lib | ForEach-Object { [string]$_.Kind } | Sort-Object) | Should -Be @('Dll', 'Ini')
    }

    It 'leaves the game alone when <File> is already there and is not ours' -ForEach @(
        @{ File = 'd3d9.dll' }
        @{ File = 'FFBPlugin.ini' }
    ) {
        # Mutation: overwrite a file that is not recorded as ours -> the user's own hook or settings are lost.
        $lib = New-R92Library -Name ('foreign-' + $File.Replace('.', ''))
        $foreign = Join-Path $lib.Dir $File
        [IO.File]::WriteAllText($foreign, 'not-ours')
        $result = Invoke-FFBPluginSetup -UserProfilesDir $lib.Up -CacheDir $lib.Cache
        $result.Deployed | Should -Be 0
        $result.SkippedCollision | Should -Be 1
        (Get-Content -LiteralPath $foreign -Raw) | Should -Be 'not-ours'
        @(Get-ChildItem -LiteralPath $lib.Dir -File | Where-Object { $_.Name -notin @('FixtureGame.exe', $File) }).Count | Should -Be 0 -Because 'no other plugin file is placed next to a file that is not ours'
        (Get-R92Owned -Lib $lib).Count | Should -Be 0
        ($script:r92Shown -join "`n") | Should -Match 'did not put it there'
    }

    It 'skips a game when the plugin file and the game are not both 32-bit or both 64-bit' {
        # Mutation: place the file anyway -> the game never loads it and the run still says installed.
        $lib = New-R92Library -Name 'arch' -Arch 'x86'
        $result = Invoke-FFBPluginSetup -UserProfilesDir $lib.Up -CacheDir $lib.Cache
        $result.Deployed | Should -Be 0
        $result.SkippedDllMissing | Should -Be 1
        Test-Path -LiteralPath (Join-Path $lib.Dir 'd3d9.dll') | Should -BeFalse
    }

    It 'skips a game whose plugin folder has no known DLL name, and says so' {
        # Mutation: guess a DLL name -> a file with the wrong name is placed.
        $lib = New-R92Library -Name 'noname'
        $script:r92Map = [ordered]@{ OtherGame = 'd3d9.dll' }
        $script:r92Zip = @{ ExtraGames = @('FixtureGame') }
        $result = Invoke-FFBPluginSetup -UserProfilesDir $lib.Up -CacheDir $lib.Cache
        $result.Deployed | Should -Be 0
        $result.SkippedNoName | Should -Be 1
        $result.AccountingComplete | Should -BeTrue
        @(Get-ChildItem -LiteralPath $lib.Dir -File).Count | Should -Be 1
        ($script:r92Shown -join "`n") | Should -Match 'does not know which file name'
    }

    It 'changes nothing when the user does not say go ahead' {
        # Mutation: apply the plan before asking -> files change although the user said no.
        $lib = New-R92Library -Name 'declined'
        $script:r92Go = 'N'
        $result = Invoke-FFBPluginSetup -UserProfilesDir $lib.Up -CacheDir $lib.Cache
        $result.Succeeded | Should -BeTrue
        $result.Declined | Should -BeTrue
        $result.Deployed | Should -Be 0
        @(Get-ChildItem -LiteralPath $lib.Dir -File).Count | Should -Be 1
        (Get-R92Owned -Lib $lib).Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $lib.Cache -Directory -Filter 'TPM-FFB-stage-*').Count | Should -Be 0
    }

    It 'refuses a ZIP with <Case> and changes nothing' -ForEach @(
        @{ Case = 'a path that climbs out of its folder'; Options = @{ ExtraEntryNames = @('FixtureGame/../../evil.txt') } }
        @{ Case = 'an absolute path'; Options = @{ ExtraEntryNames = @('/evil.txt') } }
        @{ Case = 'a drive letter'; Options = @{ ExtraEntryNames = @('C:/evil.txt') } }
        @{ Case = 'no settings file for a game that needs it'; Options = @{ OmitIniFor = @('FixtureGame') } }
        @{ Case = 'no plugin DLL for a game that needs it'; Options = @{ OmitDllFor = @('FixtureGame') } }
    ) {
        # Mutation: unpack first and check later, or unpack the whole ZIP -> an escaping entry is written, or a game gets half a plugin.
        $lib = New-R92Library -Name ('zip-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:r92Zip = $Options
        $result = Invoke-FFBPluginSetup -UserProfilesDir $lib.Up -CacheDir $lib.Cache
        $result.Succeeded | Should -BeFalse
        $result.Reason | Should -Be 'PLUGIN_ZIP_REFUSED'
        @(Get-ChildItem -LiteralPath $lib.Dir -File).Count | Should -Be 1
        Test-Path -LiteralPath (Join-Path $lib.Root 'evil.txt') | Should -BeFalse
        (Get-R92Owned -Lib $lib).Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $lib.Cache -Force | Where-Object { $_.Name -like 'TPM-FFB-stage-*' -or $_.Name -like 'TPM-FFB-Plugin-Release*' }).Count | Should -Be 0 -Because 'a refused ZIP is not kept as the saved copy'
    }

    It 'extracts only the files of the games that are registered' {
        $zip = Join-Path $TestDrive 'two-games.zip'
        New-FfbTestZip -Path $zip -Games ([ordered]@{ GameA = 'a.dll'; GameB = 'b.dll' })
        $check = Test-FFBPluginZip -ZipPath $zip
        $check.Valid | Should -BeTrue
        $stage = Join-Path $TestDrive 'two-games-stage'
        $staged = Expand-FFBPluginGameFiles -ZipPath $zip -Folders $check.Folders -Needed @('GameA') -StageDir $stage
        @($staged.Keys) | Should -Be @('GameA')
        @(Get-ChildItem -LiteralPath $stage -Recurse -File).Count | Should -Be 3
        @(Get-ChildItem -LiteralPath $stage -Recurse -File | ForEach-Object Name | Sort-Object { $_.ToLowerInvariant() }) | Should -Be @('dinput8.dll', 'FFBPlugin.ini', 'SDL2.dll')
    }

    It 'refuses a ZIP that unpacks to more than the cap, or lists a path twice' {
        $zip = Join-Path $TestDrive 'cap.zip'
        New-FfbTestZip -Path $zip -Games ([ordered]@{ GameA = 'a.dll' })
        (Test-FFBPluginZip -ZipPath $zip -MaxTotalBytes 10).Reason | Should -Be 'ZIP_TOO_BIG'
        (Test-FFBPluginZip -ZipPath $zip).Valid | Should -BeTrue
        $dup = Join-Path $TestDrive 'dup.zip'
        $archive = [System.IO.Compression.ZipFile]::Open($dup, [System.IO.Compression.ZipArchiveMode]::Create)
        try { foreach ($n in 1, 2) { $e = $archive.CreateEntry('GameA/FFBPlugin.ini'); $s = $e.Open(); $s.WriteByte(65); $s.Dispose() } } finally { $archive.Dispose() }
        (Test-FFBPluginZip -ZipPath $dup).Reason | Should -Be 'ZIP_DUPLICATE_ENTRY'
        $bad = Join-Path $TestDrive 'bad.zip'
        [IO.File]::WriteAllText($bad, 'this is not a zip')
        (Test-FFBPluginZip -ZipPath $bad).Reason | Should -Be 'ZIP_UNREADABLE'
    }
}

Describe 'Force feedback plugin updates keep what the user owns' {
    BeforeEach {
        $script:r92Shown = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-Host { [void]$script:r92Shown.Add([string]($Object -join ' ')) }
        Mock Write-Log {}
        $script:r92Tag = 'v.9.9.9.9'
        $script:r92Map = [ordered]@{ FixtureGame = 'd3d9.dll' }
        $script:r92Zip = @{}
        $script:r92Go = 'Y'
        $script:r92ReplaceIni = 'N'
        Mock Get-FFBPluginLatestRelease { New-FfbTestRelease -Tag $script:r92Tag }
        Mock Get-FFBPluginGameMap { $script:r92Map }
        Mock Invoke-FFBPluginDownload { param([string]$destDir, [object]$Release) New-FFBDownloadFixtureResult -destDir $destDir -Release $Release -ZipOptions $script:r92Zip }
        Mock Read-TpmYesNo {
            if ($Prompt -match 'Go ahead') { $script:r92Go }
            elseif ($Prompt -match 'Replace your file') { $script:r92ReplaceIni }
            else { 'Y' }
        }
    }

    It 'says already up to date and touches nothing when the release is the same' {
        $lib = New-R92Library -Name 'same'
        [void](Invoke-FFBPluginSetup -UserProfilesDir $lib.Up -CacheDir $lib.Cache)
        $before = (Get-R92Owned -Lib $lib | ForEach-Object { [string]$_.DeployedSha256 }) -join ','
        $result = Invoke-FFBPluginSetup -UserProfilesDir $lib.Up -CacheDir $lib.Cache
        $result.Succeeded | Should -BeTrue
        $result.SkippedCurrent | Should -Be 1
        $result.Deployed | Should -Be 0
        (Get-R92Owned -Lib $lib | ForEach-Object { [string]$_.DeployedSha256 }) -join ',' | Should -Be $before
        Test-Path -LiteralPath (Join-Path $lib.Dir 'FullBackup') | Should -BeFalse
    }

    It 'replaces its own unchanged files with a backup when a newer release has different files' {
        $lib = New-R92Library -Name 'newer'
        [void](Invoke-FFBPluginSetup -UserProfilesDir $lib.Up -CacheDir $lib.Cache)
        $oldDll = (Get-FileHash -LiteralPath (Join-Path $lib.Dir 'd3d9.dll') -Algorithm SHA256).Hash
        $script:r92Tag = 'v.10.0.0.0'
        $script:r92Zip = @{ Arch = 'x86'; IniText = "[Settings]`r`nGameId=9`r`nDeviceGUID=`r`n" }
        Mock Get-ExeArchitecture { 'x64' }
        $result = Invoke-FFBPluginSetup -UserProfilesDir $lib.Up -CacheDir $lib.Cache
        $result.Deployed | Should -Be 1
        (Get-FileHash -LiteralPath (Join-Path $lib.Dir 'd3d9.dll') -Algorithm SHA256).Hash | Should -Not -Be $oldDll
        (Get-Content -LiteralPath (Join-Path $lib.Dir 'FFBPlugin.ini') -Raw) | Should -Match 'GameId=9'
        $backups = @(Get-ChildItem -LiteralPath (Join-Path $lib.Dir 'FullBackup') -Recurse -File -Filter 'd3d9.dll')
        $backups.Count | Should -Be 1
        (Get-FileHash -LiteralPath $backups[0].FullName -Algorithm SHA256).Hash | Should -Be $oldDll
        (Get-R92Owned -Lib $lib).Count | Should -Be 3
    }

    It 'keeps a settings file the user changed (default) while the plugin file is updated' {
        # Mutation: overwrite the ini because it is on the record -> the user's own tuning is lost.
        $lib = New-R92Library -Name 'keepmine'
        [void](Invoke-FFBPluginSetup -UserProfilesDir $lib.Up -CacheDir $lib.Cache)
        $ini = Join-Path $lib.Dir 'FFBPlugin.ini'
        [IO.File]::WriteAllText($ini, "[Settings]`r`nGameId=7`r`nMyTuning=1`r`n")
        $oldDll = (Get-FileHash -LiteralPath (Join-Path $lib.Dir 'd3d9.dll') -Algorithm SHA256).Hash
        $script:r92Tag = 'v.10.0.0.0'
        $script:r92Zip = @{ Arch = 'x86'; IniText = "[Settings]`r`nGameId=9`r`nDeviceGUID=`r`n" }
        Mock Get-ExeArchitecture { 'x64' }
        $result = Invoke-FFBPluginSetup -UserProfilesDir $lib.Up -CacheDir $lib.Cache
        $result.Deployed | Should -Be 1
        (Get-Content -LiteralPath $ini -Raw) | Should -Be "[Settings]`r`nGameId=7`r`nMyTuning=1`r`n"
        (Get-FileHash -LiteralPath (Join-Path $lib.Dir 'd3d9.dll') -Algorithm SHA256).Hash | Should -Not -Be $oldDll
        Should -Invoke Read-TpmYesNo -ParameterFilter { $Prompt -match 'Replace your file' } -Times 1 -Exactly
    }

    It 'replaces a changed settings file only when asked to, and backs the user file up first' {
        $lib = New-R92Library -Name 'replacemine'
        [void](Invoke-FFBPluginSetup -UserProfilesDir $lib.Up -CacheDir $lib.Cache)
        $ini = Join-Path $lib.Dir 'FFBPlugin.ini'
        [IO.File]::WriteAllText($ini, "[Settings]`r`nMyTuning=1`r`n")
        $script:r92Tag = 'v.10.0.0.0'
        $script:r92Zip = @{ IniText = "[Settings]`r`nGameId=9`r`nDeviceGUID=`r`n" }
        $script:r92ReplaceIni = 'Y'
        $result = Invoke-FFBPluginSetup -UserProfilesDir $lib.Up -CacheDir $lib.Cache
        $result.Deployed | Should -Be 1
        (Get-Content -LiteralPath $ini -Raw) | Should -Match 'GameId=9'
        $backups = @(Get-ChildItem -LiteralPath (Join-Path $lib.Dir 'FullBackup') -Recurse -File -Filter 'FFBPlugin.ini')
        $backups.Count | Should -Be 1
        (Get-Content -LiteralPath $backups[0].FullName -Raw) | Should -Match 'MyTuning=1'
    }

    It 're-applies a changed wheel on request, and keeps the wheel when none is picked' {
        $lib = New-R92Library -Name 'rewheel'
        $first = '6d044fc2000000000000504944564944'
        $second = '4f0408b3000000000000504944564944'
        [void](Invoke-FFBPluginSetup -UserProfilesDir $lib.Up -CacheDir $lib.Cache -DeviceGuid $first)
        (Get-FFBPluginIniDevice -Path (Join-Path $lib.Dir 'FFBPlugin.ini')) | Should -Be $first
        $result = Invoke-FFBPluginSetup -UserProfilesDir $lib.Up -CacheDir $lib.Cache -DeviceGuid $second
        $result.Deployed | Should -Be 1
        (Get-FFBPluginIniDevice -Path (Join-Path $lib.Dir 'FFBPlugin.ini')) | Should -Be $second
        # Another run with no wheel chosen must not blank the wheel that is already set.
        $again = Invoke-FFBPluginSetup -UserProfilesDir $lib.Up -CacheDir $lib.Cache
        $again.SkippedCurrent | Should -Be 1
        (Get-FFBPluginIniDevice -Path (Join-Path $lib.Dir 'FFBPlugin.ini')) | Should -Be $second
    }

    It 'upgrades a game that only has the old plugin file TeknoParrot Manager recorded' {
        # Old releases placed only the renamed DLL and recorded only it.
        $lib = New-R92Library -Name 'oldinstall'
        $old = Join-Path $lib.Dir 'd3d9.dll'
        [IO.File]::WriteAllText($old, 'old-mame-plugin')
        $oldHash = (Get-FileHash -LiteralPath $old -Algorithm SHA256).Hash
        Write-FFBPluginOwnership -CacheDir $lib.Cache -Entries @([pscustomobject]@{ ProfileCode = 'FixtureGame'; GameRoot = $lib.Dir; Destination = $old; SourceSha256 = $oldHash; DeployedSha256 = $oldHash; SourceRevision = ('a' * 40); CreatedUtc = (Get-Date).ToUniversalTime().ToString('o') })
        $result = Invoke-FFBPluginSetup -UserProfilesDir $lib.Up -CacheDir $lib.Cache
        $result.Deployed | Should -Be 1
        (Get-FileHash -LiteralPath $old -Algorithm SHA256).Hash | Should -Not -Be $oldHash
        Test-Path -LiteralPath (Join-Path $lib.Dir 'FFBPlugin.ini') | Should -BeTrue
        $backups = @(Get-ChildItem -LiteralPath (Join-Path $lib.Dir 'FullBackup') -Recurse -File -Filter 'd3d9.dll')
        (Get-Content -LiteralPath $backups[0].FullName -Raw) | Should -Be 'old-mame-plugin'
        (Get-R92Owned -Lib $lib).Count | Should -Be 3
    }

    It 'recognizes an unrecorded old plugin file by its fingerprint, backs it up, and replaces it' {
        # Mutation: leave a fingerprint match alone -> the old plugin is never upgraded; or skip the backup -> the old file is lost.
        $lib = New-R92Library -Name 'fingerprint'
        $old = Join-Path $lib.Dir 'd3d9.dll'
        [IO.File]::WriteAllText($old, 'old-mame-plugin')
        $oldHash = (Get-FileHash -LiteralPath $old -Algorithm SHA256).Hash
        Mock Get-FFBPluginOldDllHashes { @($oldHash.ToLowerInvariant()) }
        (Get-R92Owned -Lib $lib).Count | Should -Be 0
        $result = Invoke-FFBPluginSetup -UserProfilesDir $lib.Up -CacheDir $lib.Cache
        $result.Deployed | Should -Be 1
        (Get-FileHash -LiteralPath $old -Algorithm SHA256).Hash | Should -Not -Be $oldHash
        $backups = @(Get-ChildItem -LiteralPath (Join-Path $lib.Dir 'FullBackup') -Recurse -File -Filter 'd3d9.dll')
        (Get-Content -LiteralPath $backups[0].FullName -Raw) | Should -Be 'old-mame-plugin'
        (Get-R92Owned -Lib $lib).Count | Should -Be 3
        ($script:r92Shown -join "`n") | Should -Match 'old plugin file in this game was recognized'
    }

    It 'never touches a file with the same name whose fingerprint is not on the list' {
        $lib = New-R92Library -Name 'fingerprint-other'
        $other = Join-Path $lib.Dir 'd3d9.dll'
        [IO.File]::WriteAllText($other, 'someone-elses-hook')
        Mock Get-FFBPluginOldDllHashes { @('B77B5176B6FF0915D57CE8A9DFA8812F56379BB7C6589B31216C83DB6B83C432') }
        $result = Invoke-FFBPluginSetup -UserProfilesDir $lib.Up -CacheDir $lib.Cache
        $result.Deployed | Should -Be 0
        $result.SkippedCollision | Should -Be 1
        (Get-Content -LiteralPath $other -Raw) | Should -Be 'someone-elses-hook'
        Test-Path -LiteralPath (Join-Path $lib.Dir 'FullBackup') | Should -BeFalse
        ($script:r92Shown -join "`n") | Should -Match 'did not put it there'
    }

    It 'removes all three recorded files with a backup, and keeps one the user changed' {
        $lib = New-R92Library -Name 'remove3'
        [void](Invoke-FFBPluginSetup -UserProfilesDir $lib.Up -CacheDir $lib.Cache)
        $ini = Join-Path $lib.Dir 'FFBPlugin.ini'
        [IO.File]::WriteAllText($ini, 'user-changed')
        (Remove-FFBPluginOwnedDeployment -CacheDir $lib.Cache -ProfileCode 'FixtureGame') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $lib.Dir 'd3d9.dll') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $lib.Dir 'SDL2.dll') | Should -BeFalse
        (Get-Content -LiteralPath $ini -Raw) | Should -Be 'user-changed'
        @(Get-ChildItem -LiteralPath (Join-Path $lib.Dir 'FullBackup') -Recurse -File | ForEach-Object Name | Sort-Object { $_.ToLowerInvariant() }) | Should -Be @('d3d9.dll', 'SDL2.dll')
        @(Get-R92Owned -Lib $lib | ForEach-Object { [string]$_.Kind }) | Should -Be @('Ini')
    }
}

Describe 'Force feedback plugin with no network' {
    BeforeEach {
        $script:r92Shown = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-Host { [void]$script:r92Shown.Add([string]($Object -join ' ')) }
        Mock Write-Log {}
        $script:r92Use = 'Y'
        Mock Get-FFBPluginLatestRelease { $null }
        Mock Get-FFBPluginGameMap { throw 'the table must come from the saved copy' }
        Mock Invoke-TpmDownload { throw 'there is no network' }
        Mock Read-TpmYesNo { if ($Prompt -match 'saved copy') { $script:r92Use } else { 'Y' } }
    }

    It 'offers the saved copy, says it may not be the newest, and installs from it' {
        $lib = New-R92Library -Name 'offline'
        $saved = Join-Path $lib.Cache 'TPM-FFB-Plugin-Release.zip'
        New-FfbTestZip -Path $saved -Games ([ordered]@{ FixtureGame = 'd3d9.dll' })
        $hash = (Get-FileHash -LiteralPath $saved -Algorithm SHA256).Hash
        [void](Save-FFBPluginCache -CacheDir $lib.Cache -ZipPath $saved -Tag 'v.8.0.0.0' -AssetName 'FFB.Arcade.Plugin.test.zip' -Sha256 $hash -GameMap ([ordered]@{ FixtureGame = 'd3d9.dll' }))
        $result = Invoke-FFBPluginSetup -UserProfilesDir $lib.Up -CacheDir $lib.Cache
        $result.Succeeded | Should -BeTrue
        $result.Deployed | Should -Be 1
        $result.SourceRevision | Should -Be 'v.8.0.0.0'
        Test-Path -LiteralPath (Join-Path $lib.Dir 'FFBPlugin.ini') | Should -BeTrue
        ($script:r92Shown -join "`n") | Should -Match 'may not be the newest'
        ($script:r92Shown -join "`n") | Should -Match 'Using FFB Arcade Plugin v\.8\.0\.0\.0 \(saved copy\)'
        Should -Invoke Invoke-TpmDownload -Times 0 -Exactly
        Test-Path -LiteralPath $saved | Should -BeTrue
    }

    It 'changes nothing when the user does not want the saved copy' {
        $lib = New-R92Library -Name 'offline-no'
        $saved = Join-Path $lib.Cache 'TPM-FFB-Plugin-Release.zip'
        New-FfbTestZip -Path $saved -Games ([ordered]@{ FixtureGame = 'd3d9.dll' })
        $hash = (Get-FileHash -LiteralPath $saved -Algorithm SHA256).Hash
        [void](Save-FFBPluginCache -CacheDir $lib.Cache -ZipPath $saved -Tag 'v.8.0.0.0' -AssetName 'x.zip' -Sha256 $hash -GameMap ([ordered]@{ FixtureGame = 'd3d9.dll' }))
        $script:r92Use = 'N'
        $result = Invoke-FFBPluginSetup -UserProfilesDir $lib.Up -CacheDir $lib.Cache
        $result.Succeeded | Should -BeFalse
        $result.Reason | Should -Be 'SOURCE_REVISION_UNAVAILABLE'
        @(Get-ChildItem -LiteralPath $lib.Dir -File).Count | Should -Be 1
    }

    It 'does not offer a saved copy that no longer matches its recorded hash' {
        # Mutation: offer the saved copy without checking it -> a damaged ZIP is unpacked into game folders.
        $lib = New-R92Library -Name 'offline-damaged'
        $saved = Join-Path $lib.Cache 'TPM-FFB-Plugin-Release.zip'
        New-FfbTestZip -Path $saved -Games ([ordered]@{ FixtureGame = 'd3d9.dll' })
        $hash = (Get-FileHash -LiteralPath $saved -Algorithm SHA256).Hash
        [void](Save-FFBPluginCache -CacheDir $lib.Cache -ZipPath $saved -Tag 'v.8.0.0.0' -AssetName 'x.zip' -Sha256 $hash -GameMap ([ordered]@{ FixtureGame = 'd3d9.dll' }))
        [IO.File]::AppendAllText($saved, 'damage')
        $result = Invoke-FFBPluginSetup -UserProfilesDir $lib.Up -CacheDir $lib.Cache
        $result.Succeeded | Should -BeFalse
        $result.Reason | Should -Be 'SOURCE_REVISION_UNAVAILABLE'
        Should -Invoke Read-TpmYesNo -Times 0 -Exactly -ParameterFilter { $Prompt -match 'saved copy' }
        @(Get-ChildItem -LiteralPath $lib.Dir -File).Count | Should -Be 1
    }

    It 'saves the newest release as the one cached copy when the network works' {
        Mock Get-FFBPluginLatestRelease { New-FfbTestRelease -Tag 'v.9.0.0.0' }
        Mock Get-FFBPluginGameMap { [ordered]@{ FixtureGame = 'd3d9.dll' } }
        Mock Invoke-FFBPluginDownload { param([string]$destDir, [object]$Release) New-FFBDownloadFixtureResult -destDir $destDir -Release $Release }
        $lib = New-R92Library -Name 'saved-newest'
        $old = Join-Path $lib.Cache 'TPM-FFB-Plugin-Release.zip'
        New-FfbTestZip -Path $old -Games ([ordered]@{ OlderGame = 'o.dll' })
        $oldHash = (Get-FileHash -LiteralPath $old -Algorithm SHA256).Hash
        [void](Save-FFBPluginCache -CacheDir $lib.Cache -ZipPath $old -Tag 'v.1.0.0.0' -AssetName 'old.zip' -Sha256 $oldHash -GameMap ([ordered]@{ OlderGame = 'o.dll' }))
        $result = Invoke-FFBPluginSetup -UserProfilesDir $lib.Up -CacheDir $lib.Cache
        $result.Deployed | Should -Be 1
        @(Get-ChildItem -LiteralPath $lib.Cache -File -Filter 'TPM-FFB-Plugin-Release*.zip').Count | Should -Be 1
        $now = Get-FFBPluginCachedRelease -CacheDir $lib.Cache
        $now.Revision | Should -Be 'v.9.0.0.0'
        $now.Sha256 | Should -Not -Be $oldHash
    }
}

Describe 'Force feedback wheel' {
    BeforeEach {
        $script:r92Shown = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-Host { [void]$script:r92Shown.Add([string]($Object -join ' ')) }
        Mock Write-Log {}
    }

    It 'builds the wheel id from the USB vendor and product numbers' {
        # The documented example: Logitech vendor 046D, product C24F.
        ConvertTo-FFBPluginDeviceGuid -VendorId 0x046D -ProductId 0xC24F | Should -Be '6d044fc2000000000000504944564944'
        ConvertTo-FFBPluginDeviceGuid -VendorId 0 -ProductId 0 | Should -Be '00000000000000000000504944564944'
        ConvertTo-FFBPluginDeviceGuid -VendorId 0xFFFF -ProductId 0x0001 | Should -Be 'ffff0100000000000000504944564944'
        { ConvertTo-FFBPluginDeviceGuid -VendorId 70000 -ProductId 1 } | Should -Throw
    }

    It 'lists controllers by name, writes the picked one, and keeps raw numbers under details' {
        Mock Get-TpmGameControllerList { @([pscustomobject]@{ Name = 'Logitech G29 Racing Wheel'; VendorId = 0x046D; ProductId = 0xC24F }, [pscustomobject]@{ Name = 'Arcade Pad'; VendorId = 0x1234; ProductId = 0x5678 }) }
        Mock Read-HostSafe { '1' }
        $wheel = Select-FFBPluginWheel
        $wheel.Cancelled | Should -BeFalse
        $wheel.DeviceGuid | Should -Be '6d044fc2000000000000504944564944'
        $wheel.Name | Should -Be 'Logitech G29 Racing Wheel'
        $screen = $script:r92Shown -join "`n"
        $screen | Should -Match 'Logitech G29 Racing Wheel'
        $screen | Should -Match 'Arcade Pad'
        $screen | Should -Not -Match '046D|C24F|1234|5678' -Because 'raw numbers are only shown under details'
    }

    It 'lets the user skip the wheel' {
        Mock Get-TpmGameControllerList { @([pscustomobject]@{ Name = 'Logitech G29 Racing Wheel'; VendorId = 0x046D; ProductId = 0xC24F }) }
        Mock Read-HostSafe { 'S' }
        $wheel = Select-FFBPluginWheel
        $wheel.Cancelled | Should -BeFalse
        $wheel.DeviceGuid | Should -Be ''
    }

    It 'says plainly when no controller is found and goes on without a wheel only if the user agrees: <Answer>' -ForEach @(
        @{ Answer = 'Y'; Cancelled = $false }
        @{ Answer = 'N'; Cancelled = $true }
    ) {
        Mock Get-TpmGameControllerList { @() }
        Mock Read-TpmYesNo { $Answer }
        $wheel = Select-FFBPluginWheel
        $wheel.Cancelled | Should -Be $Cancelled
        $wheel.DeviceGuid | Should -Be ''
        ($script:r92Shown -join "`n") | Should -Match 'No game controllers were found'
    }

    It 'leaves the settings file untouched when it has no wheel line' {
        $ini = Join-Path $TestDrive 'no-wheel.ini'
        [IO.File]::WriteAllText($ini, "[Settings]`r`nGameId=7`r`n")
        Set-FFBPluginIniDevice -Path $ini -DeviceGuid '6d044fc2000000000000504944564944' | Should -BeFalse
        (Get-Content -LiteralPath $ini -Raw) | Should -Be "[Settings]`r`nGameId=7`r`n"
    }

    It 'lists any game controller by name and leaves out keyboards, mice and system controllers' {
        # Fake Windows device list: no real hardware or registry is read.
        Mock Get-ItemProperty { throw 'no friendly name' }
        Mock Get-CimInstance {
            @(
                [pscustomobject]@{ Name = 'Xbox 360 Controller for Windows'; PNPClass = 'XnaComposite'; PNPDeviceID = 'USB\VID_045E&PID_028E\1' }
                [pscustomobject]@{ Name = 'Logitech G29 Driving Force Racing Wheel'; PNPClass = 'HIDClass'; PNPDeviceID = 'HID\VID_046D&PID_C24F\2' }
                [pscustomobject]@{ Name = 'DualSense Wireless Controller'; PNPClass = 'HIDClass'; PNPDeviceID = 'HID\VID_054C&PID_0CE6\3' }
                [pscustomobject]@{ Name = 'DualShock 4 Controller'; PNPClass = 'HIDClass'; PNPDeviceID = 'HID\VID_054C&PID_05C4\3' }
                [pscustomobject]@{ Name = 'Wireless Controller'; PNPClass = 'HIDClass'; PNPDeviceID = 'HID\VID_054C&PID_09CC\4' }
                [pscustomobject]@{ Name = 'Controller Without Numbers (Xbox)'; PNPClass = 'XboxComposite'; PNPDeviceID = 'SWD\XBOX\5' }
                [pscustomobject]@{ Name = 'HID Keyboard Device'; PNPClass = 'Keyboard'; PNPDeviceID = 'HID\VID_046D&PID_C31C\6' }
                [pscustomobject]@{ Name = 'HID-compliant mouse'; PNPClass = 'Mouse'; PNPDeviceID = 'HID\VID_046D&PID_C077\7' }
                [pscustomobject]@{ Name = 'HID-compliant system controller'; PNPClass = 'HIDClass'; PNPDeviceID = 'HID\VID_046D&PID_C31C&MI_01\8' }
            )
        }
        $list = @(Get-TpmGameControllerList)
        @($list | ForEach-Object { $_.Name }) | Should -Be @('Controller Without Numbers (Xbox)', 'DualSense Wireless Controller', 'DualShock 4 Controller', 'Logitech G29 Driving Force Racing Wheel', 'Wireless Controller', 'Xbox 360 Controller for Windows')
        $xbox = $list | Where-Object { $_.Name -like 'Xbox 360*' }
        $xbox.VendorId | Should -Be 0x045E
        $xbox.ProductId | Should -Be 0x028E
        ($list | Where-Object { $_.Name -like 'Controller Without*' }).VendorId | Should -BeNullOrEmpty
    }

    It 'shows a controller with no USB numbers by name, writes no wheel id, and explains it under details' {
        Mock Get-TpmGameControllerList { @([pscustomobject]@{ Name = 'Mystery Pad'; VendorId = $null; ProductId = $null }) }
        $script:r92Answers = New-Object System.Collections.Queue
        'D', '1' | ForEach-Object { $script:r92Answers.Enqueue($_) }
        Mock Read-HostSafe { $script:r92Answers.Dequeue() }
        $wheel = Select-FFBPluginWheel
        $wheel.DeviceGuid | Should -Be ''
        $wheel.Name | Should -Be 'Mystery Pad'
        $screen = $script:r92Shown -join "`n"
        $screen | Should -Match 'cannot be written as a wheel ID'
        $screen | Should -Match 'still installed'
    }
}

Describe 'Force feedback settings file differences' {
    It 'shows how the changed settings file differs when the user asks (D), then keeps it' {
        # Mutation: break the Details action -> the user cannot see what differs before choosing.
        $script:r92Shown = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-Host { [void]$script:r92Shown.Add([string]($Object -join ' ')) }
        Mock Write-Log {}
        $script:r92Tag = 'v.9.9.9.9'
        $script:r92Map = [ordered]@{ FixtureGame = 'd3d9.dll' }
        $script:r92Zip = @{}
        Mock Get-FFBPluginLatestRelease { New-FfbTestRelease -Tag $script:r92Tag }
        Mock Get-FFBPluginGameMap { $script:r92Map }
        Mock Invoke-FFBPluginDownload { param([string]$destDir, [object]$Release) New-FFBDownloadFixtureResult -destDir $destDir -Release $Release -ZipOptions $script:r92Zip }
        $script:r92Answers = [System.Collections.Generic.Queue[string]]::new()
        Mock Read-HostSafe { $script:r92Answers.Dequeue() }
        $lib = New-R92Library -Name 'diff'
        [void]$script:r92Answers.Enqueue('Y')
        [void](Invoke-FFBPluginSetup -UserProfilesDir $lib.Up -CacheDir $lib.Cache)
        $ini = Join-Path $lib.Dir 'FFBPlugin.ini'
        [IO.File]::WriteAllText($ini, "[Settings]`r`nMyTuning=1`r`n")
        $script:r92Tag = 'v.10.0.0.0'
        $script:r92Zip = @{ IniText = "[Settings]`r`nGameId=9`r`nDeviceGUID=`r`n" }
        foreach ($answer in 'D', 'N', 'Y') { [void]$script:r92Answers.Enqueue($answer) }
        $result = Invoke-FFBPluginSetup -UserProfilesDir $lib.Up -CacheDir $lib.Cache
        $result.Errors | Should -Be 0
        $screen = $script:r92Shown -join "`n"
        $screen | Should -Match 'Lines only in your file'
        $screen | Should -Match 'MyTuning=1'
        $screen | Should -Match 'GameId=9'
        (Get-Content -LiteralPath $ini -Raw) | Should -Match 'MyTuning=1'
    }
}
