#Requires -Module Pester
# Issues: https://github.com/Jumpstile/teknoparrot-manager/issues/341
# https://github.com/Jumpstile/teknoparrot-manager/issues/367
# https://github.com/Jumpstile/teknoparrot-manager/issues/368
# https://github.com/Jumpstile/teknoparrot-manager/issues/369
# Audit: <audit-folder>\ISSUES-AUDIT-RESULT.md
# Parse, extract and dot-source functions only; never execute the product entry point.
BeforeAll {
    $sourcePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw "Cannot parse production source: $($parseErrors -join '; ')" }
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    # Select the named behaviors and their real statically called helpers. Only
    # terminal output, network and registration-ledger boundaries are replaced.
    $boundaries = @(
        'Write-Host', 'Write-Log', 'Write-TpmCompactExtractionProgress', 'Invoke-TpmDownload',
        'Test-TpmRegistrationLedgerConfigured', 'Test-TpmRegistrationLedgerStopped',
        'Open-TpmRegistrationLedgerOperation', 'Update-TpmRegistrationLedgerUnit',
        'Publish-TpmRegistrationLedgerContext'
    )
    $definitions = @{}
    foreach ($node in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))) {
        if ($definitions.ContainsKey($node.Name)) { throw "Duplicate function: $($node.Name)" }
        $definitions[$node.Name] = $node
    }
    $pending = New-Object System.Collections.Generic.Queue[string]
    foreach ($name in @('Invoke-ThumbnailDownload', 'Remove-TpmReShadeOwnedDeployment',
        'Get-TpmReShadeProfileOwnershipPath', 'Invoke-AutoSync', 'Build-DatIndexFromStream',
        'Get-TpmAutoSyncZipInventory', 'Expand-ZipFileSafe', 'Get-TpmDirectoryManifest',
        'Test-TpmDirectoryAgainstZipInventory')) { $pending.Enqueue($name) }
    $selected = @{}
    while ($pending.Count -gt 0) {
        $name = $pending.Dequeue()
        if ($selected.ContainsKey($name) -or $boundaries -contains $name) { continue }
        if (-not $definitions.ContainsKey($name)) { throw "Required production helper missing: $name" }
        $definition = $definitions[$name]
        $selected[$name] = $definition
        foreach ($command in @($definition.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true))) {
            $called = $command.GetCommandName()
            if ($called -and $definitions.ContainsKey($called) -and $boundaries -notcontains $called) { $pending.Enqueue($called) }
        }
    }
    $functionPath = Join-Path $TestDrive 'rc8-file-issue-functions.ps1'
    [IO.File]::WriteAllText($functionPath, (($selected.Values | Sort-Object { $_.Extent.StartOffset } | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"))
    . $functionPath

    function Write-Log { param([string]$Message, [Parameter(ValueFromRemainingArguments = $true)]$Rest) }
    function Write-TpmCompactExtractionProgress {
        param([string]$Phase, [string]$Label, [long]$Current, [long]$Total,
            [datetime]$StartedAt, [switch]$Complete, [string]$Outcome,
            [string]$Unit, [Parameter(ValueFromRemainingArguments = $true)]$Rest)
        if ($script:rc8ProgressHook) { & $script:rc8ProgressHook $Label $Current ([bool]$Complete) }
    }
    function Invoke-TpmDownload {
        param([string]$DownloadUrl, [string]$DestinationPath, [string]$Label,
            [switch]$Quiet, [ref]$LastStatusCode, [string]$AllowedRoot, [switch]$NoOverwrite)
        $script:rc8NetworkCalls++
        # No request or destination write is performed, even on a rejected copy.
        $LastStatusCode.Value = 0
        return $false
    }
    function Test-TpmRegistrationLedgerConfigured { return $false }
    function Test-TpmRegistrationLedgerStopped { return $false }
    function Open-TpmRegistrationLedgerOperation { throw 'Ledger access is forbidden.' }
    function Update-TpmRegistrationLedgerUnit { param([Parameter(ValueFromRemainingArguments = $true)]$Rest) return $true }
    function Publish-TpmRegistrationLedgerContext { throw 'Ledger access is forbidden.' }

    function New-Rc8Directory {
        param([string]$Name)
        $path = Join-Path $TestDrive ($Name + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        [void][IO.Directory]::CreateDirectory($path)
        return $path
    }
    function New-Rc8Zip {
        param([string]$Path, [System.Collections.IDictionary]$Entries)
        $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew)
        try {
            $archive = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create)
            try {
                foreach ($name in $Entries.Keys) {
                    $entry = $archive.CreateEntry([string]$name)
                    if ([string]$name -like '*/') { continue }
                    $writer = New-Object IO.StreamWriter($entry.Open())
                    try { $writer.Write([string]$Entries[$name]) } finally { $writer.Dispose() }
                }
            } finally { $archive.Dispose() }
        } finally { $stream.Dispose() }
    }
    function New-Rc8Junction {
        param([string]$Link, [string]$Target)
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
            return [pscustomobject]@{ Created = $false; Because = 'A real Windows directory junction requires cmd.exe /c mklink /J.' }
        }
        try {
            $output = & cmd.exe /d /c ('mklink /J "{0}" "{1}"' -f $Link, $Target) 2>&1
            $exitCode = $LASTEXITCODE
            if ($exitCode -ne 0 -or -not [IO.Directory]::Exists($Link)) {
                return [pscustomobject]@{ Created = $false; Because = "mklink /J unavailable (exit $exitCode): $($output -join ' ')" }
            }
            $attributes = [IO.File]::GetAttributes($Link)
            if (($attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { throw 'mklink did not create a reparse point.' }
            return [pscustomobject]@{ Created = $true; Because = '' }
        } catch { return [pscustomobject]@{ Created = $false; Because = "Cannot create real TestDrive junction: $($_.Exception.Message)" } }
    }
    function New-Rc8ThumbnailFixture {
        $root = New-Rc8Directory 'thumb'
        $runtime = Join-Path $root 'runtime'
        $profiles = Join-Path $root 'profiles'
        $assets = Join-Path $root 'assets'
        $custom = Join-Path $assets 'CustomThumbnails'
        $outside = Join-Path $root 'outside'
        foreach ($path in @($runtime, $profiles, $custom, $outside)) { [void][IO.Directory]::CreateDirectory($path) }
        [IO.File]::WriteAllText((Join-Path $profiles 'SYNTH.xml'), '<GameProfile />')
        [IO.File]::WriteAllBytes((Join-Path $custom 'SYNTH.png'), [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN1cAAAAASUVORK5CYII='))
        [IO.File]::WriteAllText((Join-Path $outside 'sentinel.txt'), 'outside-unchanged')
        $script:TpmOwnedLayout = [pscustomobject]@{ Assets = $assets }
        return [pscustomobject]@{ Root = $root; Runtime = $runtime; Profiles = $profiles; Outside = $outside; Custom = $custom; Icons = (Join-Path $runtime 'Icons') }
    }
    function New-Rc8RemovalFixture {
        $root = New-Rc8Directory 'removal'
        $profiles = Join-Path $root 'profiles'
        $game = Join-Path $root 'Game'
        $state = Join-Path $root 'state'
        $backups = Join-Path $root 'backups'
        foreach ($path in @($profiles, $game, $state, $backups)) { [void][IO.Directory]::CreateDirectory($path) }
        $exe = Join-Path $game 'game.exe'
        [IO.File]::WriteAllText($exe, 'synthetic-not-executable')
        $profile = Join-Path $profiles 'SYNTH.xml'
        $document = New-Object Xml.XmlDocument
        $document.LoadXml('<GameProfile><GamePath /><EmulatorType>BudgieLoader</EmulatorType></GameProfile>')
        $document.GameProfile.GamePath = [string]$exe
        $document.Save($profile)
        $first = Join-Path $game 'opengl32.dll'
        $second = Join-Path $game 'TPM-Preset.ini'
        [IO.File]::WriteAllText($first, 'first-before')
        [IO.File]::WriteAllText($second, 'second-before')
        $entries = @(
            [pscustomobject]@{ DestinationPath = $first; Kind = 'ReShadeDll'; TPMManaged = $true; ExpectedSHA256 = (Get-FileHash -LiteralPath $first -Algorithm SHA256).Hash },
            [pscustomobject]@{ DestinationPath = $second; Kind = 'ReShadePreset'; TPMManaged = $true; ExpectedSHA256 = (Get-FileHash -LiteralPath $second -Algorithm SHA256).Hash }
        )
        $manifest = [pscustomobject]@{ SchemaVersion = 1; EffectId = 'Synthetic'; PinnedRevision = 'fixture'; Files = $entries }
        $ownership = Get-TpmReShadeProfileOwnershipPath -GameId SYNTH -StateRoot $state
        [void][IO.Directory]::CreateDirectory((Split-Path $ownership -Parent))
        [IO.File]::WriteAllText($ownership, ($manifest | ConvertTo-Json -Depth 6))
        $record = [pscustomobject]@{ GameId = 'SYNTH'; Status = 'Removable'; Detail = ''; ProfileFile = (Get-Item -LiteralPath $profile); GamePath = $exe; EmulatorType = 'BudgieLoader'; TargetDir = $game; DllName = 'opengl32.dll'; OwnershipPath = $ownership; Manifest = $manifest; RemovableFiles = $entries }
        return [pscustomobject]@{ Root = $root; Profiles = $profiles; State = $state; Backups = $backups; First = $first; Second = $second; Record = $record; OwnershipHash = (Get-FileHash -LiteralPath $ownership -Algorithm SHA256).Hash }
    }
    function Invoke-Rc8Removal {
        param($Fixture)
        return (Remove-TpmReShadeOwnedDeployment -ScanRecord $Fixture.Record -UserProfilesDir $Fixture.Profiles -BackupRoot $Fixture.Backups -StateRoot $Fixture.State -ConfirmRemoval)
    }
    function New-Rc8SyncFixture {
        param([string]$ExecutableRelativePath = 'bin\game.exe', [string]$ArchiveRelativePath = 'bin/game.exe')
        $root = New-Rc8Directory 'sync'
        $install = Join-Path $root 'install'
        $game = Join-Path $install 'Game'
        $profiles = Join-Path $root 'profiles'
        $source = Join-Path $root 'source'
        foreach ($path in @($game, $profiles, $source)) { [void][IO.Directory]::CreateDirectory($path) }
        $exe = Join-Path $game $ExecutableRelativePath
        [void][IO.Directory]::CreateDirectory((Split-Path $exe -Parent))
        [IO.File]::WriteAllText($exe, 'original')
        $profile = Join-Path $profiles 'SYNTH.xml'
        $document = New-Object Xml.XmlDocument
        $document.LoadXml('<GameProfile><GamePath /></GameProfile>')
        $document.GameProfile.GamePath = [string]$exe
        $document.Save($profile)
        $rawName = 'Synthetic Arcade (1.00)[TP]'
        $zip = Join-Path $source ($rawName + '.zip')
        New-Rc8Zip -Path $zip -Entries ([ordered]@{ $ArchiveRelativePath = 'replacement' })
        $datText = '<datafile><game name="Synthetic Arcade (1.00)[TP]"><GameProfile>SYNTH</GameProfile><Executable>' + $ArchiveRelativePath + '</Executable></game></datafile>'
        $datStream = New-Object IO.MemoryStream(,[Text.Encoding]::UTF8.GetBytes($datText))
        try { $dat = Build-DatIndexFromStream -stream $datStream } finally { $datStream.Dispose() }
        $statePath = Join-Path $root 'syncstate.json'
        [IO.File]::WriteAllText($statePath, '{}')
        # The sync replaces a folder that holds a different file, so the old files need a Backups folder to be kept in (AutoSync refuses without one).
        $script:TpmOwnedLayout = [pscustomobject]@{ Backups = (Join-Path $root 'backups') }
        return [pscustomobject]@{ Root = $root; Install = $install; Game = $game; Profiles = $profiles; Source = $source; Exe = $exe; Profile = $profile; ProfileHash = (Get-FileHash -LiteralPath $profile -Algorithm SHA256).Hash; RawName = $rawName; Zip = $zip; Dat = $dat; State = $statePath }
    }
}

# Pester requires per-test hooks inside a Describe; all issue cases inherit them.
Describe 'RC8 file-safety fixture isolation' {
BeforeEach {
    $script:rc8ProgressHook = $null
    $script:rc8NetworkCalls = 0
    $script:TpmOwnedLayout = $null
    $script:RawThrillsPathLimits = @{}
}
AfterEach { $script:rc8ProgressHook = $null; $script:TpmOwnedLayout = $null }

Describe 'RC8 issue #341: thumbnail copy refuses an Icons junction outside the selected runtime' -Tag 'RC8-Issue' {
    It 'Preconditions: normal runtime root, Icons child/ancestor is junction, missing destination PNG, matching registered profile/custom PNG, normal user chooses thumbnails.' {
        $f = New-Rc8ThumbnailFixture
        $junction = New-Rc8Junction -Link $f.Icons -Target $f.Outside
        if (-not $junction.Created) { Set-ItResult -Skipped -Because $junction.Because; return }
        try {
            $result = Invoke-ThumbnailDownload -userProfilesDir $f.Profiles -tpRoot $f.Runtime
            $result.Succeeded | Should -BeFalse
            $result.Reason | Should -Be 'ICONS_DIRECTORY_UNSAFE'
            Test-Path -LiteralPath (Join-Path $f.Outside 'SYNTH.png') | Should -BeFalse
            [IO.File]::ReadAllText((Join-Path $f.Outside 'sentinel.txt')) | Should -BeExactly 'outside-unchanged'
            @(Get-ChildItem -LiteralPath $f.Outside -Force).Count | Should -Be 1
            $script:rc8NetworkCalls | Should -Be 0
        } finally { [IO.Directory]::Delete($f.Icons) }
    }

    It 'Plain-directory negative creates only inside runtime.' {
        $f = New-Rc8ThumbnailFixture
        $result = Invoke-ThumbnailDownload -userProfilesDir $f.Profiles -tpRoot $f.Runtime
        $result.Succeeded | Should -BeTrue
        $result.CustomCopied | Should -Be 1
        (Get-FileHash -LiteralPath (Join-Path $f.Icons 'SYNTH.png') -Algorithm SHA256).Hash | Should -Be (Get-FileHash -LiteralPath (Join-Path $f.Custom 'SYNTH.png') -Algorithm SHA256).Hash
        Test-Path -LiteralPath (Join-Path $f.Outside 'SYNTH.png') | Should -BeFalse
        [IO.File]::WriteAllText((Join-Path $f.Icons 'SYNTH.png'), 'existing-icon')
        $second = Invoke-ThumbnailDownload -userProfilesDir $f.Profiles -tpRoot $f.Runtime
        $second.CustomCopied | Should -Be 0
        [IO.File]::ReadAllText((Join-Path $f.Icons 'SYNTH.png')) | Should -BeExactly 'existing-icon'
        $script:rc8NetworkCalls | Should -Be 0
    }

    It 'Regression real NTFS junction/intermediate reparse, directory replacement before write, normal directory, existing icon preservation, outside sentinel unchanged; network-free fixture.' {
        $f = New-Rc8ThumbnailFixture
        # Probe capability before installing the deterministic replacement hook.
        $probe = Join-Path $f.Runtime 'probe'
        $junction = New-Rc8Junction -Link $probe -Target $f.Outside
        if (-not $junction.Created) { Set-ItResult -Skipped -Because $junction.Because; return }
        [IO.Directory]::Delete($probe)
        [void][IO.Directory]::CreateDirectory($f.Icons)
        $script:rc8RaceFixture = $f
        $script:rc8RaceInjected = $false
        $script:rc8ProgressHook = {
            param($Label, $Current, $Complete)
            if ($Label -eq 'Thumbnail custom-image processing' -and $Current -eq 1 -and -not $Complete -and -not $script:rc8RaceInjected) {
                [IO.Directory]::Delete($script:rc8RaceFixture.Icons)
                $created = New-Rc8Junction -Link $script:rc8RaceFixture.Icons -Target $script:rc8RaceFixture.Outside
                if (-not $created.Created) { throw $created.Because }
                $script:rc8RaceInjected = $true
            }
        }
        try {
            $result = Invoke-ThumbnailDownload -userProfilesDir $f.Profiles -tpRoot $f.Runtime
            $script:rc8RaceInjected | Should -BeTrue
            $result.Succeeded | Should -BeFalse
            $result.CustomCopyFailed | Should -Be 1
            Test-Path -LiteralPath (Join-Path $f.Outside 'SYNTH.png') | Should -BeFalse
            [IO.File]::ReadAllText((Join-Path $f.Outside 'sentinel.txt')) | Should -BeExactly 'outside-unchanged'
        } finally {
            $script:rc8ProgressHook = $null
            if ($script:rc8RaceInjected) { [IO.Directory]::Delete($f.Icons) }
        }
    }
}

Describe 'RC8 issue #367: ReShade removal rollback preserves the concurrent second-file edit' -Tag 'RC8-Issue' {
    It 'Condition: a game/user modifies the second file after backup but before deletion revalidation. The first removed file should be restored; the second edit is instead overwritten with its older backup.' {
        $f = New-Rc8RemovalFixture
        $script:rc8RemovalFixture = $f
        $script:rc8EditInjected = $false
        $script:rc8FirstWasDeleted = $false
        $script:rc8ProgressHook = {
            param($Label, $Current, $Complete)
            if ($Label -eq 'ReShade removal' -and $Current -eq 2 -and -not $Complete) {
                $script:rc8FirstWasDeleted = -not [IO.File]::Exists($script:rc8RemovalFixture.First)
                [IO.File]::WriteAllText($script:rc8RemovalFixture.Second, 'concurrent-second-edit')
                $script:rc8EditInjected = $true
            }
        }
        $result = Invoke-Rc8Removal $f
        $script:rc8EditInjected | Should -BeTrue
        $script:rc8FirstWasDeleted | Should -BeTrue
        [IO.File]::ReadAllText($f.First) | Should -BeExactly 'first-before'
        [IO.File]::ReadAllText($f.Second) | Should -BeExactly 'concurrent-second-edit'
        $result.Status | Should -Be 'ManualRecoveryRequired'
        $result.Detail | Should -Match 'left untouched|not overwritten'
        @($result.RemovedFiles).Count | Should -Be 0
        (Get-FileHash -LiteralPath $f.Record.OwnershipPath -Algorithm SHA256).Hash | Should -Be $f.OwnershipHash
        [IO.File]::ReadAllText((Join-Path $result.BackupPath 'file_0_opengl32.dll')) | Should -BeExactly 'first-before'
        [IO.File]::ReadAllText((Join-Path $result.BackupPath 'file_1_TPM-Preset.ini')) | Should -BeExactly 'second-before'
        Test-Path -LiteralPath (Join-Path $result.BackupPath 'ownership.json') | Should -BeTrue
    }

    It 'Cover unchanged, partial deletion, concurrent modification and recovery failure paths. Preserve backups. (unchanged)' {
        $f = New-Rc8RemovalFixture
        $result = Invoke-Rc8Removal $f
        $result.Status | Should -Be 'Removed'
        @($result.RemovedFiles).Count | Should -Be 2
        Test-Path -LiteralPath $f.First | Should -BeFalse
        Test-Path -LiteralPath $f.Second | Should -BeFalse
        Test-Path -LiteralPath $f.Record.OwnershipPath | Should -BeFalse
        [IO.File]::ReadAllText((Join-Path $result.BackupPath 'file_0_opengl32.dll')) | Should -BeExactly 'first-before'
        [IO.File]::ReadAllText((Join-Path $result.BackupPath 'file_1_TPM-Preset.ini')) | Should -BeExactly 'second-before'
    }

    It 'Cover unchanged, partial deletion, concurrent modification and recovery failure paths. Preserve backups. (partial deletion)' {
        $f = New-Rc8RemovalFixture
        $script:rc8ProgressHook = {
            param($Label, $Current, $Complete)
            if ($Label -eq 'ReShade removal' -and $Current -eq 2 -and -not $Complete) { throw 'Synthetic interruption after first actual deletion.' }
        }
        $result = Invoke-Rc8Removal $f
        $result.Status | Should -Be 'RolledBack'
        [IO.File]::ReadAllText($f.First) | Should -BeExactly 'first-before'
        [IO.File]::ReadAllText($f.Second) | Should -BeExactly 'second-before'
        Test-Path -LiteralPath (Join-Path $result.BackupPath 'file_0_opengl32.dll') | Should -BeTrue
    }

    It 'Unexpected concurrent states must produce explicit conflict/manual-recovery status without destroying the newer data.' {
        $f = New-Rc8RemovalFixture
        $script:rc8RemovalFixture = $f
        $script:rc8ProgressHook = {
            param($Label, $Current, $Complete)
            if ($Label -eq 'ReShade removal' -and $Current -eq 2 -and -not $Complete) { throw 'Synthetic interruption.' }
            if ($Label -eq 'ReShade removal rollback' -and -not $Complete) { [IO.File]::WriteAllText($script:rc8RemovalFixture.First, 'concurrent-recreated-first') }
        }
        $result = Invoke-Rc8Removal $f
        $result.Status | Should -Be 'ManualRecoveryRequired'
        [IO.File]::ReadAllText($f.First) | Should -BeExactly 'concurrent-recreated-first'
        [IO.File]::ReadAllText($f.Second) | Should -BeExactly 'second-before'
        [IO.File]::ReadAllText((Join-Path $result.BackupPath 'file_0_opengl32.dll')) | Should -BeExactly 'first-before'
    }

    It 'Cover unchanged, partial deletion, concurrent modification and recovery failure paths. Preserve backups. (recovery failure)' {
        $f = New-Rc8RemovalFixture
        $script:rc8RemovalFixture = $f
        $script:rc8ProgressHook = {
            param($Label, $Current, $Complete)
            if ($Label -eq 'ReShade removal' -and $Current -eq 2 -and -not $Complete) {
                $backup = @(Get-ChildItem -LiteralPath $script:rc8RemovalFixture.Backups -Recurse -Filter 'file_0_opengl32.dll')
                if ($backup.Count -ne 1) { throw 'Expected first verified backup.' }
                [IO.File]::WriteAllText($backup[0].FullName, 'damaged-backup')
                throw 'Synthetic interruption with damaged recovery evidence.'
            }
        }
        $result = Invoke-Rc8Removal $f
        $result.Status | Should -Be 'ManualRecoveryRequired'
        Test-Path -LiteralPath $f.First | Should -BeFalse
        [IO.File]::ReadAllText($f.Second) | Should -BeExactly 'second-before'
        $result.RollbackError | Should -Match 'preserved backup'
        Test-Path -LiteralPath $result.BackupPath -PathType Container | Should -BeTrue
        [IO.File]::ReadAllText((Join-Path $result.BackupPath 'file_1_TPM-Preset.ini')) | Should -BeExactly 'second-before'
    }
}

Describe 'RC8 issue #368: renamed registered Game/bin/game.exe resolves extraction root Game' -Tag 'RC8-Issue' {
    It 'For a renamed game with Game/bin/game.exe and an archive containing bin/game.exe, replacement targets Game/bin and produces Game/bin/bin/game.exe.' {
        $f = New-Rc8SyncFixture
        $f.Dat.Count | Should -Be 1
        $map = Get-StagingFolderMap $f.Install
        $map.ContainsKey((Get-NormalizedGameKey $f.RawName)) | Should -BeFalse
        $map.ContainsKey('SYNTH') | Should -BeFalse
        $resolved = Resolve-ExtractedGameFolder -RawZipName $f.RawName -InstallFolder $f.Install -FolderMap $map -DatIndex $f.Dat -UserProfilesDir $f.Profiles
        $resolved | Should -Be $f.Game
        $result = Invoke-AutoSync -zipSource $f.Source -installFolder $f.Install -syncStatePath $f.State -datIndex $f.Dat -userProfilesDir $f.Profiles
        $result.Failed | Should -Be 0
        $result.Synced | Should -Be 1
        @($result.SyncedNames).Count | Should -Be 1
        $result.SyncedNames[0] | Should -BeExactly 'Game'
        $result.TransactionResults[0].Outcome | Should -Be 'SUCCEEDED'
        $result.TransactionResults[0].TechnicalDetails.TargetPath | Should -Be $f.Game
        [IO.File]::ReadAllText($f.Exe) | Should -BeExactly 'replacement'
        Test-Path -LiteralPath (Join-Path $f.Game 'bin\bin\game.exe') | Should -BeFalse
        $saved = Get-Content -LiteralPath $f.State -Raw | ConvertFrom-Json
        $saved.PSObject.Properties[$f.RawName].Value.LocalPath | Should -Be $f.Game
        # SyncedNames is the real post-sync registration scan contract.
        (Join-Path $f.Install $result.SyncedNames[0]) | Should -Be $resolved
        (Read-Xml $f.Profile).GameProfile.GamePath | Should -Be $f.Exe
        (Get-FileHash -LiteralPath $f.Profile -Algorithm SHA256).Hash | Should -Be $f.ProfileHash
    }

    It 'Root-level executables must remain supported.' {
        $f = New-Rc8SyncFixture -ExecutableRelativePath 'game.exe' -ArchiveRelativePath 'game.exe'
        $result = Invoke-AutoSync -zipSource $f.Source -installFolder $f.Install -syncStatePath $f.State -datIndex $f.Dat -userProfilesDir $f.Profiles
        $result.Failed | Should -Be 0
        $result.Synced | Should -Be 1
        $result.SyncedNames[0] | Should -BeExactly 'Game'
        [IO.File]::ReadAllText($f.Exe) | Should -BeExactly 'replacement'
        (Read-Xml $f.Profile).GameProfile.GamePath | Should -Be $f.Exe
    }

    It 'Resolve a proven extraction root or refuse safely; never equate executable parent with game root without evidence.' {
        $f = New-Rc8SyncFixture -ArchiveRelativePath 'other/game.exe'
        $result = Invoke-AutoSync -zipSource $f.Source -installFolder $f.Install -syncStatePath $f.State -datIndex $f.Dat -userProfilesDir $f.Profiles
        $result.Synced | Should -Be 0
        $result.Failed | Should -Be 1
        $result.UnsafePathSkipped | Should -Be 1
        $result.TransactionResults[0].ReasonCode | Should -Be 'AMBIGUOUS_EXTRACTION_ROOT'
        $result.TransactionResults[0].Mutation.Started | Should -BeFalse
        [IO.File]::ReadAllText($f.Exe) | Should -BeExactly 'original'
        [IO.File]::ReadAllText($f.State) | Should -BeExactly '{}'
        Test-Path -LiteralPath (Join-Path $f.Game 'other') | Should -BeFalse
        (Get-FileHash -LiteralPath $f.Profile -Algorithm SHA256).Hash | Should -Be $f.ProfileHash
    }

    It 'Assert final executable/profile mapping, extraction destination and post-sync scan agree; preserve original bytes/backup on refusal or failure.' {
        $f = New-Rc8SyncFixture
        $script:rc8ExtractionInterrupted = $false
        $script:rc8ProgressHook = {
            param($Label, $Current, $Complete)
            if ($Label -eq 'Synthetic Arcade (1.00)[TP]' -and -not $Complete) {
                $script:rc8ExtractionInterrupted = $true
                throw 'Synthetic extraction write failure before promotion.'
            }
        }
        $result = Invoke-AutoSync -zipSource $f.Source -installFolder $f.Install -syncStatePath $f.State -datIndex $f.Dat -userProfilesDir $f.Profiles
        $script:rc8ExtractionInterrupted | Should -BeTrue
        $result.Failed | Should -Be 1
        $result.Synced | Should -Be 0
        @($result.SyncedNames).Count | Should -Be 0
        $result.TransactionResults[0].Outcome | Should -Be 'FAILED_BEFORE_MUTATION'
        [IO.File]::ReadAllText($f.Exe) | Should -BeExactly 'original'
        [IO.File]::ReadAllText($f.State) | Should -BeExactly '{}'
        (Get-FileHash -LiteralPath $f.Profile -Algorithm SHA256).Hash | Should -Be $f.ProfileHash
    }
}

Describe 'RC8 issue #369: ZIP inventory includes parents of nested empty directory entries' -Tag 'RC8-Issue' {
    It 'A valid archive with directory entry cache/empty/ but no separate cache/ entry is therefore undercounted.' {
        $root = New-Rc8Directory 'zip-empty'
        $zip = Join-Path $root 'Game.zip'
        $stage = Join-Path $root 'stage'
        New-Rc8Zip -Path $zip -Entries ([ordered]@{ 'game.exe' = 'game'; 'cache/empty/' = '' })
        $inventory = Get-TpmAutoSyncZipInventory -ZipPath $zip
        $inventory.FileCount | Should -Be 1
        @($inventory.Entries).Count | Should -Be 3
        @($inventory.Entries | Where-Object { $_.RelativePath -eq 'cache' -and $_.IsDirectory }).Count | Should -Be 1
        Expand-ZipFileSafe -ZipPath $zip -DestDir $stage
        Test-Path -LiteralPath (Join-Path $stage 'cache\empty') -PathType Container | Should -BeTrue
        $manifest = Get-TpmDirectoryManifest -Path $stage
        $manifest.Readable | Should -BeTrue
        (Test-TpmDirectoryAgainstZipInventory -Manifest $manifest -Inventory $inventory) | Should -BeTrue
        # Exact verification remains strict: equal-size wrong bytes and extra
        # directories are not accepted merely because parent closure was fixed.
        [IO.File]::WriteAllText((Join-Path $stage 'game.exe'), 'evil')
        (Test-TpmDirectoryAgainstZipInventory -Manifest (Get-TpmDirectoryManifest $stage) -Inventory $inventory) | Should -BeFalse
        [IO.File]::WriteAllText((Join-Path $stage 'game.exe'), 'game')
        [void][IO.Directory]::CreateDirectory((Join-Path $stage 'unexpected'))
        (Test-TpmDirectoryAgainstZipInventory -Manifest (Get-TpmDirectoryManifest $stage) -Inventory $inventory) | Should -BeFalse
    }

    It 'Cover explicit parents, implicit parents, multiple nested empty directories and ordinary file-only archives. (<Case>)' -ForEach @(
        @{ Case = 'explicit parents'; Entries = [ordered]@{ 'game.exe' = 'game'; 'cache/' = ''; 'cache/empty/' = '' }; Count = 3 },
        @{ Case = 'implicit parents'; Entries = [ordered]@{ 'bin/game.exe' = 'game' }; Count = 2 },
        @{ Case = 'multiple nested empty directories'; Entries = [ordered]@{ 'game.exe' = 'game'; 'cache/one/' = ''; 'cache/two/' = ''; 'deep/one/two/empty/' = '' }; Count = 8 },
        @{ Case = 'ordinary file-only'; Entries = [ordered]@{ 'game.exe' = 'game' }; Count = 1 }
    ) {
        param($Case, $Entries, $Count)
        $root = New-Rc8Directory 'zip-matrix'
        $zip = Join-Path $root 'Game.zip'
        $stage = Join-Path $root 'stage'
        New-Rc8Zip -Path $zip -Entries $Entries
        $inventory = Get-TpmAutoSyncZipInventory -ZipPath $zip
        @($inventory.Entries).Count | Should -Be $Count
        Expand-ZipFileSafe -ZipPath $zip -DestDir $stage
        $manifest = Get-TpmDirectoryManifest -Path $stage
        $manifest.Readable | Should -BeTrue
        @($manifest.Items).Count | Should -Be $Count
        (Test-TpmDirectoryAgainstZipInventory -Manifest $manifest -Inventory $inventory) | Should -BeTrue
    }

    It 'Preserve path-traversal, collision and unsafe-entry rejection; do not relax manifest verification broadly to hide a count mismatch. (<Case>)' -ForEach @(
        @{ Case = 'path traversal'; Entries = [ordered]@{ 'game.exe' = 'game'; '../escape.txt' = 'bad' } },
        @{ Case = 'directory beneath file'; Entries = [ordered]@{ 'cache' = 'file'; 'cache/empty/' = '' } },
        @{ Case = 'canonical path collision'; Entries = [ordered]@{ 'bin/game.exe' = 'game'; 'bin\game.exe' = 'bad' } },
        @{ Case = 'unsafe device entry'; Entries = [ordered]@{ 'game.exe' = 'game'; 'NUL.txt' = 'bad' } }
    ) {
        param($Case, $Entries)
        $root = New-Rc8Directory 'zip-unsafe'
        $zip = Join-Path $root 'Game.zip'
        $stage = Join-Path $root 'stage'
        New-Rc8Zip -Path $zip -Entries $Entries
        { Get-TpmAutoSyncZipInventory -ZipPath $zip } | Should -Throw
        { Expand-ZipFileSafe -ZipPath $zip -DestDir $stage } | Should -Throw
        Test-Path -LiteralPath $stage | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $root 'escape.txt') | Should -BeFalse
    }
}
}
