#Requires -Module Pester
# FIX96: ReShade safety.
#   B2: ReShade never writes into the configured source collection (main or supplementary): install, reapply, update, undo and removal
#       refuse a game folder that lies inside a source folder, before anything is staged, saved or written.
#   S3: ReShade removal deletes only the file it checked and saved. A file that replaced it after the last check is left alone.
# These tests drive the real product functions with synthetic folders in $TestDrive; nothing touches TeknoParrot, LaunchBox, the registry,
# services or the network. Each It names the product change that makes it fail.
# What this CANNOT prove: a real ReShade install with downloaded effects, how a real console paints the rows, or a second program that
# really replaces a file between the check and the delete (the tests replace the file at that exact point from inside a mock).

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $script:f96Ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX96 bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'fix96-functions.ps1'
    ($script:f96Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:DisplayVersion = 'v1.0 RC8'
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false
    $script:logPath = Join-Path $TestDrive 'fix96.log'
    $script:logWarnShown = $false
    # The real check of one removable file, kept so a mock can run it and then change the file at the exact point the old code left open.
    $script:f96RealValidate = ${function:Get-TpmReShadeValidatedRemovalEntry}

    function New-F96Root {
        param([string]$Name)
        $root = Join-Path $TestDrive ($Name + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        [void][System.IO.Directory]::CreateDirectory($root)
        return $root
    }
    # A game folder with a game file in it; returns the path of the game file.
    function New-F96Game {
        param([string]$Dir, [string]$Name = 'game.exe')
        [void][System.IO.Directory]::CreateDirectory($Dir)
        $exe = Join-Path $Dir $Name
        [System.IO.File]::WriteAllText($exe, 'MZ-test-game')
        return $exe
    }
    function Get-F96Bytes {
        param([string]$Path)
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '<absent>' }
        return [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($Path))
    }
    function Get-F96Text {
        param($Rows)
        return ((@($Rows | ForEach-Object { ([string]$_).Trim() }) -join ' ') -replace '\s+', ' ')
    }
    # A real directory junction; Created is $false (and the test is skipped) when the machine does not allow one.
    function New-F96Junction {
        param([string]$Link, [string]$Target)
        try {
            $output = & cmd.exe /d /c ('mklink /J "{0}" "{1}"' -f $Link, $Target) 2>&1
            $exitCode = $LASTEXITCODE
            if ($exitCode -ne 0 -or -not [System.IO.Directory]::Exists($Link)) { return [pscustomobject]@{ Created = $false; Because = ('mklink /J unavailable (exit {0}): {1}' -f $exitCode, ($output -join ' ')) } }
            return [pscustomobject]@{ Created = $true; Because = '' }
        } catch { return [pscustomobject]@{ Created = $false; Because = $_.Exception.Message } }
    }
    # One game with one removable ReShade file (the hook), a profile for it and the ownership record, as the removal scan would find them.
    function New-F96RemovalFixture {
        param([string]$GameDir)
        $root = New-F96Root 'removal'
        $profiles = Join-Path $root 'profiles'; $state = Join-Path $root 'state'; $backups = Join-Path $root 'backups'
        foreach ($path in @($profiles, $state, $backups)) { [void][System.IO.Directory]::CreateDirectory($path) }
        $exe = New-F96Game -Dir $GameDir
        $profile = Join-Path $profiles 'SYNTH.xml'
        $document = New-Object System.Xml.XmlDocument
        $document.LoadXml('<GameProfile><GameName>Synthetic Game</GameName><GamePath /><EmulatorType>BudgieLoader</EmulatorType></GameProfile>')
        $document.GameProfile.GamePath = [string]$exe
        $document.Save($profile)
        $hook = Join-Path $GameDir 'opengl32.dll'
        [System.IO.File]::WriteAllText($hook, 'tpm-reshade-dll')
        $entries = @([pscustomobject]@{ DestinationPath = $hook; Kind = 'ReShadeDll'; TPMManaged = $true; ExpectedSHA256 = (Get-FileHash -LiteralPath $hook -Algorithm SHA256).Hash })
        $manifest = [pscustomobject]@{ SchemaVersion = 1; EffectId = 'ReShadeProfile.Original'; PinnedRevision = 'fixture'; Files = $entries }
        $ownership = Get-TpmReShadeProfileOwnershipPath -GameId SYNTH -StateRoot $state
        [void][System.IO.Directory]::CreateDirectory((Split-Path $ownership -Parent))
        [System.IO.File]::WriteAllText($ownership, ($manifest | ConvertTo-Json -Depth 6))
        $record = [pscustomobject]@{ GameId = 'SYNTH'; Status = 'Removable'; Detail = ''; ProfileFile = (Get-Item -LiteralPath $profile); GamePath = $exe; EmulatorType = 'BudgieLoader'; TargetDir = $GameDir; DllName = 'opengl32.dll'; OwnershipPath = $ownership; Manifest = $manifest; RemovableFiles = $entries }
        return [pscustomobject]@{ Root = $root; Profiles = $profiles; State = $state; Backups = $backups; GameDir = $GameDir; Hook = $hook; Record = $record }
    }
    # One finished ReShade change of a game (Before is written, the undo copy is made, After is written, the copy is finished).
    function New-F96Change {
        param([string]$StateRoot, [string]$GameDir, [string]$GameId, [hashtable]$Before = @{}, [hashtable]$After = @{})
        [void][System.IO.Directory]::CreateDirectory($GameDir)
        $utf8 = New-Object System.Text.UTF8Encoding $false
        foreach ($name in @($Before.Keys)) { if ($null -ne $Before[$name]) { [System.IO.File]::WriteAllBytes((Join-Path $GameDir $name), $utf8.GetBytes([string]$Before[$name])) } }
        $paths = @(@(@($Before.Keys) + @($After.Keys)) | Sort-Object -Unique | ForEach-Object { Join-Path $GameDir $_ })
        $request = New-TpmReShadeUndoRequest -GameId $GameId -GameName ('Game ' + $GameId) -Operation 'Install' -LookBefore 'None' -LookAfter 'FastCrt' -OwnerBefore 'None' -StateRoot $StateRoot
        $undo = New-TpmReShadeUndoReceipt -Request $request -Paths $paths -Roots @($GameDir)
        if (-not $undo.Succeeded) { throw ('fixture: the receipt was not made: ' + $undo.Reason) }
        foreach ($name in @($After.Keys)) { [System.IO.File]::WriteAllBytes((Join-Path $GameDir $name), $utf8.GetBytes([string]$After[$name])) }
        if ((Complete-TpmReShadeUndoReceipt -Undo $undo) -cne 'Ready') { throw 'fixture: the receipt was not finished' }
        Start-Sleep -Milliseconds 25
        return (@(Get-TpmReShadeUndoEntries -StateRoot $StateRoot | Where-Object { $_.GameId -eq $GameId })[0])
    }
}

Describe 'FIX96 B2: the game check refuses a game inside a source folder' {
    BeforeEach {
        Mock Write-Log {}
        $script:f96Root = New-F96Root 'guard'
    }

    It 'refuses a game inside the main source folder and accepts the same kind of game outside it' {
        # Mutation: take the source-folder check out of Test-TpmGameMutationPath -> the game in the collection is reported Valid.
        $source = Join-Path $script:f96Root 'Collection'
        $inside = New-F96Game -Dir (Join-Path $source 'Unpacked\Game')
        $outside = New-F96Game -Dir (Join-Path $script:f96Root 'Games\Game')
        $refused = Test-TpmGameMutationPath -GamePath $inside -RequireLeaf -ProtectedRoots @($source)
        $refused.Valid | Should -BeFalse
        $refused.ReasonCode | Should -BeExactly 'SOURCE_COLLECTION'
        $refused.ProtectedRoot | Should -BeExactly $source
        $refused.Reason | Should -Match 'never changes files there'
        (Test-TpmGameMutationPath -GamePath $outside -RequireLeaf -ProtectedRoots @($source)).Valid | Should -BeTrue
        (Test-TpmGameMutationPath -GamePath $inside -RequireLeaf).Valid | Should -BeTrue -Because 'without protected folders the check is unchanged'
    }

    It 'refuses a game inside the supplementary source folder, ignoring case and a trailing separator' {
        # Mutation: look only at the first protected folder, or compare case-sensitively -> the supplementary game or the upper-case spelling passes.
        $main = Join-Path $script:f96Root 'Main'
        $supplementary = Join-Path $script:f96Root 'Supplementary'
        [void][System.IO.Directory]::CreateDirectory($main)
        $inside = New-F96Game -Dir (Join-Path $supplementary 'Game')
        (Test-TpmGameMutationPath -GamePath $inside -RequireLeaf -ProtectedRoots @($main, $supplementary)).ReasonCode | Should -BeExactly 'SOURCE_COLLECTION'
        $spelled = $supplementary.ToUpperInvariant() + '\'
        (Test-TpmGameMutationPath -GamePath $inside -RequireLeaf -ProtectedRoots @($spelled)).ReasonCode | Should -BeExactly 'SOURCE_COLLECTION'
        (Test-TpmGameMutationPath -GamePath $inside -RequireLeaf -ProtectedRoots @('', $null, $main)).Valid | Should -BeTrue -Because 'empty entries and a different folder protect nothing'
    }

    It 'does not refuse a folder that only starts with the same letters as a source folder' {
        # Mutation: compare with a plain StartsWith and no path separator -> "Collection2" is treated as inside "Collection".
        $source = Join-Path $script:f96Root 'Collection'
        [void][System.IO.Directory]::CreateDirectory($source)
        $neighbor = New-F96Game -Dir (Join-Path $script:f96Root 'Collection2\Game')
        (Test-TpmGameMutationPath -GamePath $neighbor -RequireLeaf -ProtectedRoots @($source)).Valid | Should -BeTrue
    }

    It 'sees a source folder that is a junction to the real folder holding the game' {
        # Mutation: compare only the spelled paths (leave out the real folder behind a link) -> the game in the real folder passes.
        $real = Join-Path $script:f96Root 'RealCollection'
        $inside = New-F96Game -Dir (Join-Path $real 'Game')
        $link = Join-Path $script:f96Root 'CollectionLink'
        $junction = New-F96Junction -Link $link -Target $real
        if (-not $junction.Created) { Set-ItResult -Skipped -Because $junction.Because; return }
        try {
            $refused = Test-TpmGameMutationPath -GamePath $inside -RequireLeaf -ProtectedRoots @($link)
            $refused.Valid | Should -BeFalse
            $refused.ReasonCode | Should -BeExactly 'SOURCE_COLLECTION'
            $refused.ProtectedRoot | Should -BeExactly $link
        } finally { [System.IO.Directory]::Delete($link) }
    }

    It 'has plain reasons for the two new codes' {
        # Mutation: remove the two entries from Get-TpmPlainReasonTable -> the Details show the generic "could not be completed" sentence.
        foreach ($code in @('SOURCE_COLLECTION', 'UNDO_SOURCE_FOLDER')) {
            $reason = Get-TpmPlainReason -Code $code
            $reason.Known | Should -BeTrue -Because $code
            $reason.Text | Should -Match 'source folder'
            $reason.Text | Should -Not -Match '\bTPM\b'
        }
    }

    It 'refuses (fails closed) when a configured source folder exists but its real location cannot be read' {
        # Mutation: let Get-TpmGuardPathForms (or Find-TpmProtectedSourceRoot) fall back to the spelled path when the real path cannot be read -> a game inside the real folder behind an unreadable junction passes.
        $real = Join-Path $script:f96Root 'RealCollection'
        $inside = New-F96Game -Dir (Join-Path $real 'Game')
        $unreadable = Join-Path $script:f96Root 'CollectionLink'
        [void][System.IO.Directory]::CreateDirectory($unreadable)
        $script:f96Unreadable = $unreadable
        $script:f96RealResolve = Get-Command Get-TpmResolvedExistingPath -CommandType Function
        Mock Get-TpmResolvedExistingPath { & $script:f96RealResolve -Path $Path }
        Mock Get-TpmResolvedExistingPath { return '' } -ParameterFilter { $Path -eq $script:f96Unreadable }
        { Find-TpmProtectedSourceRoot -Path $inside -ProtectedRoots @($unreadable) } | Should -Throw '*could not be checked*'
        $result = Test-TpmGameMutationPath -GamePath $inside -RequireLeaf -ProtectedRoots @($unreadable)
        $result.Valid | Should -BeFalse
        $result.ReasonCode | Should -BeExactly 'PATH_VALIDATION_FAILED'
        $result.Reason | Should -Match 'could not be confirmed'
    }

    It 'refuses (fails closed) when the game path exists but its real location cannot be read' {
        # Mutation: ignore a failed real-path lookup of the game itself -> a game behind an unreadable link passes.
        $source = Join-Path $script:f96Root 'Collection'
        [void][System.IO.Directory]::CreateDirectory($source)
        $game = New-F96Game -Dir (Join-Path $script:f96Root 'Games\Game')
        $script:f96UnreadableGame = $game
        $script:f96RealResolve = Get-Command Get-TpmResolvedExistingPath -CommandType Function
        Mock Get-TpmResolvedExistingPath { & $script:f96RealResolve -Path $Path }
        Mock Get-TpmResolvedExistingPath { return '' } -ParameterFilter { $Path -eq $script:f96UnreadableGame }
        (Test-TpmGameMutationPath -GamePath $game -RequireLeaf -ProtectedRoots @($source)).Valid | Should -BeFalse
    }

    It 'still compares by spelled path when a configured source folder does not exist at all' {
        # Mutation: refuse every unresolvable folder, including one that is not there -> a missing optional supplementary folder blocks every game.
        $missing = Join-Path $script:f96Root 'NoSuchCollection'
        $game = New-F96Game -Dir (Join-Path $script:f96Root 'Games\Game')
        (Test-TpmGameMutationPath -GamePath $game -RequireLeaf -ProtectedRoots @($missing)).Valid | Should -BeTrue
        $insideMissing = Join-Path $missing 'Game\game.exe'
        Find-TpmProtectedSourceRoot -Path $insideMissing -ProtectedRoots @($missing) | Should -BeExactly $missing
    }
}

Describe 'FIX96 B2: install, reapply and update write nothing into a source folder' {
    BeforeEach {
        Mock Write-Log {}
        Mock Write-TpmCompactExtractionProgress {}
        Mock Write-Host {}
        Mock Get-ExeArchitecture { 'x64' }
        $script:f96Root = New-F96Root 'deploy'
        $script:f96State = Join-Path $script:f96Root 'State'
        $script:f96Dll = Join-Path $script:f96Root 'ReShade64.dll'
        [System.IO.File]::WriteAllText($script:f96Dll, 'MZ-tpm-reshade-runtime')
    }

    It 'stops before staging, before the undo copy and before any write for a game inside a source folder' {
        # Mutation: remove the source-folder check from Install-TpmReShadeProfileDeployment -> the staging folder, the undo copy and the hook are made.
        $source = Join-Path $script:f96Root 'Collection'
        $gameDir = Join-Path $source 'Unpacked\Game'
        $exe = New-F96Game -Dir $gameDir
        $ownership = Join-Path $script:f96State 'Deployments\src.json'
        Mock New-TpmStagingDirectory { throw 'must not stage' }
        Mock New-TpmReShadeUndoReceipt { throw 'must not save an undo copy' }
        $request = New-TpmReShadeUndoRequest -GameId 'Src' -GameName 'Src Game' -Operation 'Install' -LookBefore 'None' -LookAfter 'Original' -OwnerBefore 'None' -StateRoot $script:f96State
        $result = Install-TpmReShadeProfileDeployment -ProfileDefinition (Get-TpmReShadeProfile -ProfileId Original) -GamePath $exe -Doc ([xml]'<GameProfile><EmulatorType>Default</EmulatorType></GameProfile>') -SourceDll $script:f96Dll -CacheRoot (Join-Path $script:f96Root 'cache') -OwnershipPath $ownership -CanonicalPreset -UndoReceipt $request -ProtectedRoots @($source)
        $result.Succeeded | Should -BeFalse
        $result.Reason | Should -BeExactly 'SOURCE_COLLECTION'
        Should -Invoke New-TpmStagingDirectory -Times 0 -Exactly
        Should -Invoke New-TpmReShadeUndoReceipt -Times 0 -Exactly
        @(Get-ChildItem -LiteralPath $gameDir -Force | ForEach-Object Name) | Should -Be @('game.exe')
        Test-Path -LiteralPath $ownership | Should -BeFalse
    }

    It 'still installs into a game outside the source folders' {
        # Mutation: refuse every game once a protected folder is given -> the normal game is not installed.
        $source = Join-Path $script:f96Root 'Collection'
        [void][System.IO.Directory]::CreateDirectory($source)
        $gameDir = Join-Path $script:f96Root 'Games\Game'
        $exe = New-F96Game -Dir $gameDir
        $result = Install-TpmReShadeProfileDeployment -ProfileDefinition (Get-TpmReShadeProfile -ProfileId Original) -GamePath $exe -Doc ([xml]'<GameProfile><EmulatorType>Default</EmulatorType></GameProfile>') -SourceDll $script:f96Dll -CacheRoot (Join-Path $script:f96Root 'cache') -OwnershipPath (Join-Path $script:f96State 'Deployments\ok.json') -CanonicalPreset -ProtectedRoots @($source)
        $result.Succeeded | Should -BeTrue -Because ($result | ConvertTo-Json -Depth 3)
        Test-Path -LiteralPath (Join-Path $gameDir 'dxgi.dll') -PathType Leaf | Should -BeTrue
    }

    It 'hands the protected folders on when a previous look is reapplied' {
        # Mutation: leave -ProtectedRoots out of the Install-TpmReShadeProfileDeployment call in Restore-TpmReShadeProfile -> the reapply path has no source-folder check.
        $profile = Get-TpmReShadeProfile -ProfileId Levels
        $entry = [pscustomobject]@{ ProfileId = 'Levels'; VariantId = 'Default'; DefinitionVersion = [string]$profile.SchemaVersion; EffectIds = @($profile.Effects); EffectSha256 = @(Get-TpmReShadeProfileEffectHashes -ProfileDefinition $profile); Applied = $true }
        $source = Join-Path $script:f96Root 'Collection'
        $exe = New-F96Game -Dir (Join-Path $source 'Game')
        $script:f96SeenRoots = $null
        Mock Install-TpmReShadeProfileDeployment { $script:f96SeenRoots = @($ProtectedRoots); [pscustomobject]@{ Succeeded = $false; State = 'SOURCE_COLLECTION'; Reason = 'SOURCE_COLLECTION'; Error = ''; UndoReceipt = $null } }
        $result = Restore-TpmReShadeProfile -HistoryEntry $entry -CacheRoot (Join-Path $script:f96Root 'cache') -OwnershipRoot (Join-Path $script:f96Root 'ownership') -GamePath $exe -Doc ([xml]'<GameProfile/>') -SourceDll $script:f96Dll -ProtectedRoots @($source)
        $result.Succeeded | Should -BeFalse
        $result.Reason | Should -BeExactly 'SOURCE_COLLECTION'
        $script:f96SeenRoots | Should -Be @($source)
    }

    It 'refuses a 32-bit game when the 32-bit ReShade file is missing, leaves its folder exactly as it was, and a 64-bit game still gets ReShade' {
        # Mutation: install the 64-bit DLL into a 32-bit game when ReShade32.dll is missing -> the 64-bit DLL is written into a 32-bit game, where it never loads.
        $dir32 = Join-Path $script:f96Root 'Games\Game32'
        $dir64 = Join-Path $script:f96Root 'Games\Game64'
        $exe32 = New-F96Game -Dir $dir32
        $exe64 = New-F96Game -Dir $dir64
        Mock Get-ExeArchitecture { if ($ExePath -like '*Game32*') { 'x86' } else { 'x64' } }
        $doc = [xml]'<GameProfile><EmulatorType>Default</EmulatorType></GameProfile>'
        $ownership32 = Join-Path $script:f96State 'Deployments\g32.json'
        $refused = Install-TpmReShadeProfileDeployment -ProfileDefinition (Get-TpmReShadeProfile -ProfileId Original) -GamePath $exe32 -Doc $doc -SourceDll $script:f96Dll -CacheRoot (Join-Path $script:f96Root 'cache') -OwnershipPath $ownership32 -CanonicalPreset
        $refused.Succeeded | Should -BeFalse
        $refused.State | Should -BeExactly 'DLL_32BIT_MISSING'
        @(Get-ChildItem -LiteralPath $dir32 -Force | ForEach-Object Name) | Should -Be @('game.exe')
        Test-Path -LiteralPath $ownership32 | Should -BeFalse
        $installed = Install-TpmReShadeProfileDeployment -ProfileDefinition (Get-TpmReShadeProfile -ProfileId Original) -GamePath $exe64 -Doc $doc -SourceDll $script:f96Dll -CacheRoot (Join-Path $script:f96Root 'cache') -OwnershipPath (Join-Path $script:f96State 'Deployments\g64.json') -CanonicalPreset
        $installed.Succeeded | Should -BeTrue -Because ($installed | ConvertTo-Json -Depth 3)
        Test-Path -LiteralPath (Join-Path $dir64 'dxgi.dll') -PathType Leaf | Should -BeTrue
    }

    It 'gives a 32-bit game ReShade32.dll and a 64-bit game ReShade64.dll' {
        # Mutation: always copy the file named by -SourceDll -> a 32-bit game gets the 64-bit DLL and ReShade never loads.
        $dir32 = Join-Path $script:f96Root 'Games\Game32'
        $dir64 = Join-Path $script:f96Root 'Games\Game64'
        $exe32 = New-F96Game -Dir $dir32
        $exe64 = New-F96Game -Dir $dir64
        $dll32 = Join-Path (Split-Path -Parent $script:f96Dll) 'ReShade32.dll'
        [System.IO.File]::WriteAllBytes($dll32, [byte[]](0x4d, 0x5a, 0x32, 0x32))
        Mock Get-ExeArchitecture { if ($ExePath -like '*Game32*' -or $ExePath -like '*ReShade32.dll') { 'x86' } else { 'x64' } }
        $doc = [xml]'<GameProfile><EmulatorType>Default</EmulatorType></GameProfile>'
        $r32 = Install-TpmReShadeProfileDeployment -ProfileDefinition (Get-TpmReShadeProfile -ProfileId Original) -GamePath $exe32 -Doc $doc -SourceDll $script:f96Dll -CacheRoot (Join-Path $script:f96Root 'cache') -OwnershipPath (Join-Path $script:f96State 'Deployments\h32.json') -CanonicalPreset
        $r32.Succeeded | Should -BeTrue -Because ($r32 | ConvertTo-Json -Depth 3)
        $r64 = Install-TpmReShadeProfileDeployment -ProfileDefinition (Get-TpmReShadeProfile -ProfileId Original) -GamePath $exe64 -Doc $doc -SourceDll $script:f96Dll -CacheRoot (Join-Path $script:f96Root 'cache') -OwnershipPath (Join-Path $script:f96State 'Deployments\h64.json') -CanonicalPreset
        $r64.Succeeded | Should -BeTrue -Because ($r64 | ConvertTo-Json -Depth 3)
        (Get-FileHash -LiteralPath (Join-Path $dir32 'dxgi.dll') -Algorithm SHA256).Hash | Should -BeExactly (Get-FileHash -LiteralPath $dll32 -Algorithm SHA256).Hash
        (Get-FileHash -LiteralPath (Join-Path $dir64 'dxgi.dll') -Algorithm SHA256).Hash | Should -BeExactly (Get-FileHash -LiteralPath $script:f96Dll -Algorithm SHA256).Hash
    }

    It 'recognizes a Linux-style (ELF) game file and not a Windows game file' {
        # Mutation: always return $false -> Linux-style games are treated like Windows games.
        $elf = Join-Path $script:f96Root 'linuxgame.elf'
        $win = Join-Path $script:f96Root 'wingame.exe'
        $short = Join-Path $script:f96Root 'tiny.bin'
        [System.IO.File]::WriteAllBytes($elf, [byte[]](0x7f, 0x45, 0x4c, 0x46, 1, 1, 1, 0))
        [System.IO.File]::WriteAllBytes($win, [byte[]](0x4d, 0x5a, 0x90, 0x00, 3, 0, 0, 0))
        [System.IO.File]::WriteAllBytes($short, [byte[]](0x7f))
        Test-TpmFileIsElf -Path $elf | Should -BeTrue
        Test-TpmFileIsElf -Path $win | Should -BeFalse
        Test-TpmFileIsElf -Path $short | Should -BeFalse
        Test-TpmFileIsElf -Path (Join-Path $script:f96Root 'missing.elf') | Should -BeFalse
    }
}

Describe 'FIX96 B2: the setup flow skips games inside a source folder and says so plainly' {
    BeforeEach {
        $script:f96Root = New-F96Root 'flow'
        $script:f96Profiles = Join-Path $script:f96Root 'UserProfiles'
        [void][System.IO.Directory]::CreateDirectory($script:f96Profiles)
        $script:TpmOwnedLayout = [pscustomobject]@{ Assets = (Join-Path $script:f96Root 'Assets'); State = (Join-Path $script:f96Root 'State') }
        $script:f96Main = Join-Path $script:f96Root 'Collection'
        $script:f96Supplementary = Join-Path $script:f96Root 'Supplementary'
        $script:f96GameDirs = [ordered]@{
            GameA = (Join-Path $script:f96Main 'GameA')
            GameB = (Join-Path $script:f96Supplementary 'GameB')
            GameC = (Join-Path $script:f96Root 'Games\GameC')
        }
        $script:f96Names = @($script:f96GameDirs.Keys)
        foreach ($name in $script:f96Names) {
            $exe = New-F96Game -Dir $script:f96GameDirs[$name] -Name ($name + '.exe')
            [System.IO.File]::WriteAllText((Join-Path $script:f96Profiles ($name + '.xml')), ('<GameProfile><GameName>Fixture {0}</GameName><GamePath>{1}</GamePath></GameProfile>' -f $name, $exe))
        }
        $script:f96SourceDll = Join-Path $script:f96Root 'ReShade64.dll'
        [System.IO.File]::WriteAllBytes($script:f96SourceDll, [byte[]](0x4d, 0x5a))
        $script:f96Profile = Get-TpmReShadeProfile -ProfileId 'FastCrt'
        $script:f96Rows = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-Host { [void]$script:f96Rows.Add([string]$Object) }
        Mock Write-Log {}
        Mock Get-ConsoleContentWidth { 100 }
        Mock Get-TpmConsoleMetrics { [pscustomobject]@{ Width = 100; Left = 0; Top = 0; Height = 40; BufferWidth = 100; BufferHeight = 300 } }
        Mock Test-TpmNoReparsePath { $true }
        Mock Assert-TpmNoReparseWriteTarget {}
        Mock Write-TpmCompactExtractionProgress {}
        Mock Get-TpmReShadeHdrGate { [pscustomobject]@{ State = 'HIDDEN'; Visible = $false; Enabled = $false; Reason = 'test'; Fingerprint = '' } }
        Mock Show-TpmReShadeProfileGalleryWindow { [pscustomobject]@{ Available = $false; Session = $null; Reason = 'fixture' } }
        Mock Invoke-ReShadeUpdateIfAvailable { param($SourceDll, $InstalledVersion) [pscustomobject]@{ Updated = $false; SourceDll = $SourceDll } }
        Mock Test-ReShadeDllSignature { [pscustomobject]@{ Status = 'UnknownError'; Signer = '(none)'; Thumbprint = ('C3' * 20) } }
        Mock Read-TpmReShadeState { [pscustomobject]@{ Favorites = @() } }
        Mock Select-RegisteredGamesInteractive { @($script:f96Names | ForEach-Object { Get-Item -LiteralPath (Join-Path $script:f96Profiles ($_ + '.xml')) }) }
        Mock Read-TpmReShadeTerminalProfile { [pscustomobject]@{ Cancelled = $false; SelectedProfile = $script:f96Profile; PreviewSession = $null } }
        Mock Close-TpmReShadeProfileGallerySession {}
        Mock Test-TpmInteractiveInput { $false }
        Mock Read-HostSafe { return '' }
        Mock Read-TpmChoice { return 'Y' }
        Mock Read-TpmYesNo { return 'N' }
        Mock Get-TpmReShadeChooserOptions { [pscustomobject]@{ Restore = [pscustomobject]@{ Found = $false; Valid = $false }; Remembered = [pscustomobject]@{ Found = $false; Valid = $false } } }
        Mock Get-TpmReShadeApplyPreflight {
            param($SelectedGames)
            $records = @($SelectedGames | ForEach-Object { [pscustomobject]@{ Game = $_.BaseName; Status = 'Ready'; Detail = '' } })
            [pscustomobject]@{ Total = $records.Count; Ready = $records.Count; Protected = 0; MissingPath = 0; Unsafe = 0; Failed = 0; Records = $records }
        }
        Mock Get-ExeArchitecture { 'x64' }
        Mock Get-TpmReShadeProfileOwnershipPath { Join-Path $script:f96Root ($GameId + '.ownership.json') }
        Mock Get-ReShadeTargetInfo { param($ExeDir) [pscustomobject]@{ TargetDir = $ExeDir; DllName = 'dxgi.dll' } }
        Mock Get-TpmReShadeOwnershipClassification { [pscustomobject]@{ Status = 'NoReShadePresent'; Detail = 'fixture' } }
        Mock New-TpmReShadePresetContent { '; fixture preset' }
        Mock Get-TpmReShadeProfileTechniqueDisplay { 'fixture' }
        Mock Install-TpmReShadeProfileDeployment {
            param($GamePath, $OwnershipPath, $UndoReceipt)
            [pscustomobject]@{ Succeeded = $true; State = 'INSTALLED'; TargetDir = [IO.Path]::GetDirectoryName($GamePath); DllName = 'dxgi.dll'; PresetApplied = $false; PresetSource = $null; ApiDetected = $true; UndoReceipt = $null }
        }
        Mock Test-TpmReShadeDeploymentVerified { $true }
        Mock Add-TpmReShadeProfileHistory {}
    }
    AfterEach {
        $script:TpmOwnedLayout = $null
    }

    It 'changes only the game outside the source folders, hands them to the deployment, and leaves the other profiles byte for byte alone' {
        # Mutation: leave -ProtectedRoots out of Test-TpmGameMutationPath in Invoke-ReShadeSetupLegacy, or drop the supplementary folder -> GameA or GameB is installed.
        $before = @{}
        foreach ($name in $script:f96Names) { $before[$name] = Get-F96Bytes (Join-Path $script:f96Profiles ($name + '.xml')) }
        $result = Invoke-ReShadeSetupLegacy -UserProfilesDir $script:f96Profiles -SourceDll $script:f96SourceDll -ZipSource $script:f96Main -ZipSourceSupplementary $script:f96Supplementary
        @($result.ChangedItems) | Should -Be @('GameC')
        @($result.SourceFolderItems) | Should -Be @('GameA', 'GameB')
        $result.Deployed | Should -Be 1
        $result.Unsafe | Should -Be 2
        Should -Invoke Install-TpmReShadeProfileDeployment -Times 1 -Exactly
        Should -Invoke Install-TpmReShadeProfileDeployment -Times 0 -Exactly -ParameterFilter { $GamePath -like '*GameA*' -or $GamePath -like '*GameB*' }
        Should -Invoke Install-TpmReShadeProfileDeployment -Times 1 -Exactly -ParameterFilter { @($ProtectedRoots).Count -eq 2 -and $ProtectedRoots[0] -eq $script:f96Main -and $ProtectedRoots[1] -eq $script:f96Supplementary }
        foreach ($name in $script:f96Names) { (Get-F96Bytes (Join-Path $script:f96Profiles ($name + '.xml'))) | Should -BeExactly $before[$name] -Because 'the profile registration stays untouched' }
        (Get-F96Text @($result.UnsafeDetails)) | Should -Match 'inside the source folder'
        (Get-F96Text @($result.DetailNotes)) | Should -Match 'SOURCE_COLLECTION: 2'
    }

    It 'installs normally when no source folder is configured' {
        # Mutation: treat an empty source folder as a folder that holds everything -> no game is installed.
        $result = Invoke-ReShadeSetupLegacy -UserProfilesDir $script:f96Profiles -SourceDll $script:f96SourceDll -ZipSource '' -ZipSourceSupplementary ''
        $result.Deployed | Should -Be 3
        @($result.SourceFolderItems).Count | Should -Be 0
    }

    It 'skips a 32-bit game, installs the 64-bit games and never hands the 32-bit game to the deployment' {
        # Mutation: leave the 32-bit check out of the deployment loop in Invoke-ReShadeSetupLegacy -> the 32-bit game is handed to the deployment, or counted as unsafe.
        Mock Get-ExeArchitecture { if ($ExePath -like '*GameB*') { 'x86' } else { 'x64' } }
        $result = Invoke-ReShadeSetupLegacy -UserProfilesDir $script:f96Profiles -SourceDll $script:f96SourceDll -ZipSource '' -ZipSourceSupplementary ''
        @($result.ChangedItems) | Should -Be @('GameA', 'GameC')
        @($result.SkippedItems) | Should -Be @('GameB')
        $result.Unsupported | Should -Be 1
        $result.Unsafe | Should -Be 0
        Should -Invoke Install-TpmReShadeProfileDeployment -Times 2 -Exactly
        Should -Invoke Install-TpmReShadeProfileDeployment -Times 0 -Exactly -ParameterFilter { $GamePath -like '*GameB*' }
        (Get-F96Text @($result.DetailNotes)) | Should -Match ([regex]::Escape('32-bit game -- the 32-bit ReShade file (ReShade32.dll) was not found -- skipped'))
    }
}

Describe 'FIX96 B2: the result screen tells a beginner what to do' {
    BeforeEach {
        $script:f96Rows = [System.Collections.Generic.List[object]]::new()
        $script:f96Prompts = 0
        Mock Write-Host { [void]$script:f96Rows.Add([pscustomobject]@{ Text = [string]$Object }) }
        Mock Write-Log {}
        Mock Get-ConsoleContentWidth { return 100 }
        Mock Read-HostSafe {
            $script:f96Prompts++
            if ($script:f96Prompts -gt 40) { throw 'runaway prompt loop in the test' }
            return $Default
        }
    }
    BeforeAll {
        function New-F96Result {
            param([int]$Unsafe, [string[]]$SourceFolder, [int]$Unsupported = 0)
            return [pscustomobject]@{
                Deployed = 1; Protected = 0; Unsafe = $Unsafe; MissingPath = 0; MissingDevice = 0; Unsupported = $Unsupported; KeptPrevious = 0; ErrorCount = 0
                UnverifiedItems = @(); SelectedProfileName = 'Fast CRT'; ProtectedRecords = @(); ProtectedDetails = @()
                UnsafeDetails = @('Game A: The game is inside the source folder.'); SummaryDetails = @(); DetailNotes = @(); SelectedProfileTechniques = 'CRT-ZFast'
                SourceFolderItems = $SourceFolder
            }
        }
    }

    It 'says the games are inside the source folder and what to do, without calling them unsafe' {
        # Mutation: fold the source-folder games into "could not be checked safely" -> the beginner is not told the real reason or the fix.
        $null = Show-TpmReShadeSetupResult -Result (New-F96Result -Unsafe 2 -SourceFolder @('GameA', 'GameB'))
        $plain = Get-F96Text @($script:f96Rows | ForEach-Object { $_.Text })
        $plain | Should -Match ([regex]::Escape('Not changed: 2 games are inside your source folder (where your game collection is kept).'))
        $plain | Should -Match ([regex]::Escape('Move the game out of it, or fix the game folder in its profile.'))
        $plain | Should -Not -Match 'could not be checked safely'
        $plain | Should -Not -Match '\bTPM\b'
    }

    It 'keeps the other unsafe games on their own line' {
        # Mutation: subtract nothing (or everything) from the unsafe count -> the 1 other unsafe game is lost or counted twice.
        $null = Show-TpmReShadeSetupResult -Result (New-F96Result -Unsafe 3 -SourceFolder @('GameA', 'GameB'))
        $plain = Get-F96Text @($script:f96Rows | ForEach-Object { $_.Text })
        $plain | Should -Match ([regex]::Escape('2 games are inside your source folder'))
        $plain | Should -Match ([regex]::Escape('1 game could not be checked safely.'))
    }

    It 'says how many 32-bit games were skipped and why, in the same words for one and for many' {
        # Mutation: bring back the old "file was not found" sentence for a 32-bit game, or lose the singular/plural wording.
        $null = Show-TpmReShadeSetupResult -Result (New-F96Result -Unsafe 0 -SourceFolder @() -Unsupported 1)
        (Get-F96Text @($script:f96Rows | ForEach-Object { $_.Text })) | Should -Match ([regex]::Escape('Not changed: 1 32-bit game was skipped. The 32-bit ReShade file was not found. Download ReShade again to get it.'))
        $script:f96Rows.Clear()
        $null = Show-TpmReShadeSetupResult -Result (New-F96Result -Unsafe 0 -SourceFolder @() -Unsupported 3)
        $plain = Get-F96Text @($script:f96Rows | ForEach-Object { $_.Text })
        $plain | Should -Match ([regex]::Escape('Not changed: 3 32-bit games were skipped. The 32-bit ReShade file was not found. Download ReShade again to get it.'))
        $plain | Should -Not -Match 'ReShade file that was not found'
    }
}

Describe 'FIX96 B2: undo puts nothing back into a source folder' {
    BeforeEach {
        Mock Write-Log {}
        Mock Write-TpmCompactExtractionProgress {}
        Mock Write-Host {}
        Mock Get-ConsoleContentWidth { 100 }
        Mock Get-TpmConsoleMetrics { [pscustomobject]@{ Width = 100; Left = 0; Top = 0; Height = 40; BufferWidth = 100; BufferHeight = 300 } }
        Mock Test-TpmInteractiveInput { $false }
        Mock Read-HostSafe { return '' }
        $script:f96Root = New-F96Root 'undo'
        $script:f96State = Join-Path $script:f96Root 'State'
        $script:f96Source = Join-Path $script:f96Root 'Collection'
        $script:f96Game = Join-Path $script:f96Source 'Game'
        $script:f96Entry = New-F96Change -StateRoot $script:f96State -GameDir $script:f96Game -GameId 'U' -Before @{ 'dxgi.dll' = $null; 'ReShade.ini' = 'own' } -After @{ 'dxgi.dll' = 'tpm-dll'; 'ReShade.ini' = 'tpm' }
    }

    It 'refuses the undo of a game inside a source folder and keeps both the files and the undo copy' {
        # Mutation: leave the source-folder check out of Invoke-TpmReShadeUndo -> the files in the collection are rewritten.
        $result = Invoke-TpmReShadeUndo -Entry $script:f96Entry -ProtectedRoots @($script:f96Source)
        $result.Status | Should -BeExactly 'NotChanged'
        $result.Code | Should -BeExactly 'UNDO_SOURCE_FOLDER'
        $result.Detail | Should -Match 'inside the source folder'
        [System.IO.File]::ReadAllText((Join-Path $script:f96Game 'dxgi.dll')) | Should -BeExactly 'tpm-dll'
        [System.IO.File]::ReadAllText((Join-Path $script:f96Game 'ReShade.ini')) | Should -BeExactly 'tpm'
        Test-Path -LiteralPath $script:f96Entry.Folder -PathType Container | Should -BeTrue
    }

    It 'still undoes the same change when the folder is not a source folder' {
        # Mutation: refuse every undo once a protected folder is given -> the control undo does nothing.
        $result = Invoke-TpmReShadeUndo -Entry $script:f96Entry -ProtectedRoots @((Join-Path $script:f96Root 'Elsewhere'))
        $result.Status | Should -BeExactly 'Undone'
        Test-Path -LiteralPath (Join-Path $script:f96Game 'dxgi.dll') | Should -BeFalse
        [System.IO.File]::ReadAllText((Join-Path $script:f96Game 'ReShade.ini')) | Should -BeExactly 'own'
    }

    It 'passes the protected folders from the Undo menu down to the undo' {
        # Mutation: leave -ProtectedRoots out of Show-TpmReShadeUndoMenu or Invoke-TpmReShadeUndoGameChoice -> the menu undoes a game in the collection.
        $script:f96Choices = New-Object 'System.Collections.Generic.Queue[string]'
        $script:f96Choices.Enqueue('1'); $script:f96Choices.Enqueue('B')
        Mock Read-TpmChoice { return $script:f96Choices.Dequeue() }
        Mock Confirm-TpmReShadeUndoWord { return $true }
        Show-TpmReShadeUndoMenu -StateRoot $script:f96State -ProtectedRoots @($script:f96Source)
        [System.IO.File]::ReadAllText((Join-Path $script:f96Game 'dxgi.dll')) | Should -BeExactly 'tpm-dll'
        Should -Invoke Confirm-TpmReShadeUndoWord -Times 1 -Exactly
    }

    It 'passes the protected folders from Undo all down to every undo' {
        # Mutation: leave -ProtectedRoots out of Invoke-TpmReShadeUndoAllChoice -> Undo all rewrites the collection.
        Mock Confirm-TpmReShadeUndoWord { return $true }
        Mock Invoke-TpmProgressGroup { & $Action }
        Invoke-TpmReShadeUndoAllChoice -Entries @($script:f96Entry) -ProtectedRoots @($script:f96Source)
        [System.IO.File]::ReadAllText((Join-Path $script:f96Game 'ReShade.ini')) | Should -BeExactly 'tpm'
        Test-Path -LiteralPath $script:f96Entry.Folder -PathType Container | Should -BeTrue
    }
}

Describe 'FIX96 removal: B2 source-folder refusal and S3 delete-what-was-checked' {
    BeforeEach {
        Mock Write-Log {}
        Mock Write-TpmCompactExtractionProgress {}
        Mock Write-Host {}
        $script:f96Calls = 0
        $script:f96Inject = $null
        # The third check of the file is the last one before the delete: it runs the real check, then the test replaces the file.
        Mock Get-TpmReShadeValidatedRemovalEntry {
            $script:f96Calls++
            $validated = & $script:f96RealValidate -Entry $Entry -ProfileRoot $ProfileRoot -TargetRoot $TargetRoot
            if ($script:f96Calls -eq 3 -and $null -ne $script:f96Inject) { & $script:f96Inject }
            return $validated
        }
    }

    It 'removes the file it checked and saved when nothing changed it' {
        # Mutation: break the delete helper (for example a wrong identity) -> a normal removal ends as a conflict and the hook stays.
        $f = New-F96RemovalFixture -GameDir (Join-Path (New-F96Root 'games') 'Game')
        $result = Remove-TpmReShadeOwnedDeployment -ScanRecord $f.Record -UserProfilesDir $f.Profiles -BackupRoot $f.Backups -StateRoot $f.State -ConfirmRemoval
        $script:f96Calls | Should -Be 3
        $result.Status | Should -BeExactly 'Removed'
        Test-Path -LiteralPath $f.Hook | Should -BeFalse
        [System.IO.File]::ReadAllText((Join-Path $result.BackupPath 'file_0_opengl32.dll')) | Should -BeExactly 'tpm-reshade-dll'
    }

    It 'still removes what an earlier version installed into a 32-bit game' {
        # Mutation: make removal depend on the game being 64-bit -> ReShade files an earlier version put into a 32-bit game can no longer be removed.
        Mock Get-ExeArchitecture { 'x86' }
        $f = New-F96RemovalFixture -GameDir (Join-Path (New-F96Root 'games32') 'Game')
        $result = Remove-TpmReShadeOwnedDeployment -ScanRecord $f.Record -UserProfilesDir $f.Profiles -BackupRoot $f.Backups -StateRoot $f.State -ConfirmRemoval
        $result.Status | Should -BeExactly 'Removed'
        Test-Path -LiteralPath $f.Hook | Should -BeFalse
    }

    It 'removes a read-only file it checked and saved' {
        # Mutation: leave the read-only clearing out of Remove-TpmReShadeVerifiedFile -> the delete is refused and the removal ends in manual recovery.
        $f = New-F96RemovalFixture -GameDir (Join-Path (New-F96Root 'games') 'Game')
        [System.IO.File]::SetAttributes($f.Hook, [System.IO.FileAttributes]::ReadOnly)
        $result = Remove-TpmReShadeOwnedDeployment -ScanRecord $f.Record -UserProfilesDir $f.Profiles -BackupRoot $f.Backups -StateRoot $f.State -ConfirmRemoval
        $result.Status | Should -BeExactly 'Removed'
        Test-Path -LiteralPath $f.Hook | Should -BeFalse
    }

    It 'keeps a different file that replaced the checked one right before the delete' {
        # Mutation: delete by path again (Remove-Item) after the last check -> the replacement is deleted and nothing holds a copy of it.
        $f = New-F96RemovalFixture -GameDir (Join-Path (New-F96Root 'games') 'Game')
        $script:f96Fx = $f
        $script:f96Inject = { [System.IO.File]::Delete($script:f96Fx.Hook); [System.IO.File]::WriteAllText($script:f96Fx.Hook, 'users-own-replacement') }
        $result = Remove-TpmReShadeOwnedDeployment -ScanRecord $f.Record -UserProfilesDir $f.Profiles -BackupRoot $f.Backups -StateRoot $f.State -ConfirmRemoval
        $script:f96Calls | Should -Be 3 -Because 'the replacement happens at the last check'
        [System.IO.File]::ReadAllText($f.Hook) | Should -BeExactly 'users-own-replacement'
        $result.Status | Should -BeExactly 'ManualRecoveryRequired'
        $result.Detail | Should -Match 'left untouched'
        @($result.RemovedFiles).Count | Should -Be 0
        Test-Path -LiteralPath $f.Record.OwnershipPath | Should -BeTrue
        [System.IO.File]::ReadAllText((Join-Path $result.BackupPath 'file_0_opengl32.dll')) | Should -BeExactly 'tpm-reshade-dll'
    }

    It 'keeps a different file that has exactly the same bytes' {
        # Mutation: compare only the bytes at the delete and drop the file identity -> a same-bytes file made by someone else is deleted.
        $f = New-F96RemovalFixture -GameDir (Join-Path (New-F96Root 'games') 'Game')
        $script:f96Fx = $f
        $script:f96Inject = { [System.IO.File]::Move($script:f96Fx.Hook, ($script:f96Fx.Hook + '.moved')); [System.IO.File]::WriteAllText($script:f96Fx.Hook, 'tpm-reshade-dll') }
        $result = Remove-TpmReShadeOwnedDeployment -ScanRecord $f.Record -UserProfilesDir $f.Profiles -BackupRoot $f.Backups -StateRoot $f.State -ConfirmRemoval
        $script:f96Calls | Should -Be 3
        Test-Path -LiteralPath $f.Hook -PathType Leaf | Should -BeTrue
        $result.Status | Should -BeExactly 'ManualRecoveryRequired'
        @($result.RemovedFiles).Count | Should -Be 0
    }

    It 'keeps the same file when it was rewritten in place right before the delete' {
        # Mutation: verify only the file identity and not the bytes on the open file -> the rewritten file is deleted.
        $f = New-F96RemovalFixture -GameDir (Join-Path (New-F96Root 'games') 'Game')
        $script:f96Fx = $f
        $script:f96Inject = { [System.IO.File]::WriteAllText($script:f96Fx.Hook, 'rewritten-in-place') }
        $result = Remove-TpmReShadeOwnedDeployment -ScanRecord $f.Record -UserProfilesDir $f.Profiles -BackupRoot $f.Backups -StateRoot $f.State -ConfirmRemoval
        $script:f96Calls | Should -Be 3
        [System.IO.File]::ReadAllText($f.Hook) | Should -BeExactly 'rewritten-in-place'
        $result.Status | Should -BeExactly 'ManualRecoveryRequired'
    }

    It 'changes nothing when a configured source folder cannot be resolved' {
        # Mutation: treat an unresolvable source folder as "not inside" in Remove-TpmReShadeOwnedDeployment -> the removal goes ahead.
        $unreadable = New-F96Root 'unreadable-collection'
        $script:f96Unreadable = $unreadable
        $script:f96RealResolve = Get-Command Get-TpmResolvedExistingPath -CommandType Function
        Mock Get-TpmResolvedExistingPath { & $script:f96RealResolve -Path $Path }
        Mock Get-TpmResolvedExistingPath { return '' } -ParameterFilter { $Path -eq $script:f96Unreadable }
        $f = New-F96RemovalFixture -GameDir (Join-Path (New-F96Root 'games') 'Game')
        $result = Remove-TpmReShadeOwnedDeployment -ScanRecord $f.Record -UserProfilesDir $f.Profiles -BackupRoot $f.Backups -StateRoot $f.State -ProtectedRoots @($unreadable) -ConfirmRemoval
        $result.Status | Should -Not -BeExactly 'Removed'
        $script:f96Calls | Should -Be 0
        Test-Path -LiteralPath $f.Hook -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $f.Record.OwnershipPath -PathType Leaf | Should -BeTrue
        @(Get-ChildItem -LiteralPath $f.Backups -Force).Count | Should -Be 0
    }

    It 'refuses a game folder inside a source folder before saving or removing anything' {
        # Mutation: leave the source-folder check out of Remove-TpmReShadeOwnedDeployment -> the undo copy, the saved copy and the delete all run in the collection.
        $source = New-F96Root 'collection'
        $f = New-F96RemovalFixture -GameDir (Join-Path $source 'Game')
        $result = Remove-TpmReShadeOwnedDeployment -ScanRecord $f.Record -UserProfilesDir $f.Profiles -BackupRoot $f.Backups -StateRoot $f.State -ProtectedRoots @($source) -ConfirmRemoval
        $result.Status | Should -BeExactly 'SourceFolderRefused'
        $result.GameName | Should -BeExactly 'Synthetic Game'
        $result.Detail | Should -Match 'Nothing was changed'
        $script:f96Calls | Should -Be 0 -Because 'nothing was checked, saved or deleted'
        Test-Path -LiteralPath $f.Hook -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $f.Record.OwnershipPath -PathType Leaf | Should -BeTrue
        @(Get-ChildItem -LiteralPath $f.Backups -Force).Count | Should -Be 0
        @(Get-TpmReShadeUndoEntries -StateRoot $f.State).Count | Should -Be 0
    }
}

Describe 'FIX96 removal: the driver tells the beginner and does not claim success' {
    BeforeEach {
        $script:f96Rows = New-Object 'System.Collections.Generic.List[string]'
        $script:f96Prompt = 0
        Mock Write-Log {}
        Mock Write-TpmCompactExtractionProgress {}
        Mock Write-Host { [void]$script:f96Rows.Add([string]$Object) }
        Mock Get-ConsoleContentWidth { 100 }
        Mock Read-HostSafe { if ($script:f96Prompt++ -eq 0) { 'A' } else { 'REMOVE' } }
    }

    It 'leaves a game inside the source folder alone, says why and what to do, and returns not succeeded' {
        # Mutation: leave -ProtectedRoots out of the Remove-TpmReShadeOwnedDeployment call in Invoke-TpmReShadeRemoval (or ignore the refusal in Succeeded) -> the game is changed or the run is called a success.
        $root = New-F96Root 'driver'
        $profiles = Join-Path $root 'UserProfiles'; $state = Join-Path $root 'state'
        $source = Join-Path $root 'Collection'
        [void][System.IO.Directory]::CreateDirectory($profiles)
        $game = New-F96Game -Dir (Join-Path $source 'Game')
        $hook = Join-Path $source 'Game\dxgi.dll'
        [System.IO.File]::WriteAllText($hook, 'owned')
        [System.IO.File]::WriteAllText((Join-Path $profiles 'Flow.xml'), ('<GameProfile><GameName>Flow Game</GameName><GamePath>' + $game + '</GamePath><EmulatorType>Default</EmulatorType></GameProfile>'))
        $hash = (Get-FileHash -LiteralPath $hook -Algorithm SHA256).Hash
        Save-TpmReShadeOwnershipManifest -Manifest ([pscustomobject]@{ SchemaVersion = 1; EffectId = 'ReShadeProfile.CleanSharp'; PinnedRevision = 'TPM-PROFILE'; Files = @([pscustomobject]@{ RelativeSource = 'dxgi.dll'; DestinationPath = $hook; ExpectedSHA256 = $hash; ActualSHA256 = $hash; TPMManaged = $true; Kind = 'ReShadeDll' }) }) -Path (Get-TpmReShadeProfileOwnershipPath -GameId Flow -StateRoot $state)
        $summary = Invoke-TpmReShadeRemoval -UserProfilesDir $profiles -StateRoot $state -BackupRoot (Join-Path $profiles 'FullBackup') -ProtectedRoots @($source)
        $summary.Succeeded | Should -BeFalse
        $summary.SourceFolderRefused | Should -Be 1
        $summary.Removed | Should -Be 0
        Test-Path -LiteralPath $hook -PathType Leaf | Should -BeTrue
        $plain = Get-F96Text $script:f96Rows
        $plain | Should -Match ([regex]::Escape('Not removed: Flow Game is inside your source folder. Nothing was changed in it.'))
        $plain | Should -Match ([regex]::Escape('Move the game out of it, or fix the game folder in its profile.'))
    }
}
