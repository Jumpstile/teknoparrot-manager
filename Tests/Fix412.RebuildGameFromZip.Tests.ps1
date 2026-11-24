#Requires -Module Pester

# Rebuild one game from its ZIP: the game folder is put back to exactly what the ZIP holds. The old folder is never
# deleted: it is renamed to a kept place and stays there until the player puts it back or deletes it.
# Isolated fake ZIPs and folders under $TestDrive only.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Fix412 bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'fix412-functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding UTF8
    $progressModuleDirectory = Join-Path $TestDrive 'scripts'
    [void][IO.Directory]::CreateDirectory($progressModuleDirectory)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Destination (Join-Path $progressModuleDirectory 'TpmProgress.psm1') -Force
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $script:DisplayVersion = 'v1.0 RC9.3'
    $script:ScriptVersion = '1.0'
    $script:ReleaseCandidateLabel = 'RC9.3'
    $script:ActiveTpmWorkflowStatus = $null
    $script:PostgresRecoveryStatus = $null
    $script:PostgresRecoveryResumeState = $null
    $script:TpmWorkflowRendering = $false
    $script:logPath = Join-Path $TestDrive 'fix412.log'
    $script:logWarnShown = $false
    $script:RawThrillsPathLimits = @{}
    $script:FileVersionPins = @{}
    $script:GpuIncompatibleGames = @{}
    $script:f412RealMove = ${function:Invoke-TpmAutoSyncMovePath}

    function New-F412Fixture {
        $root = Join-Path $TestDrive ('f412-' + [guid]::NewGuid().ToString('N').Substring(0, 10))
        $fx = [pscustomobject]@{
            Root = $root; Games = (Join-Path $root 'Games'); Zips = (Join-Path $root 'Zips')
            State = (Join-Path $root 'State'); Backups = (Join-Path $root 'Backups')
            SyncState = (Join-Path $root 'Games\TeknoParrot-Manager.syncstate.json')
            Target = (Join-Path $root 'Games\Papa Game')
            Zip = (Join-Path $root 'Zips\Papa Game.zip')
            KeptRoot = (Join-Path $root 'TPM-old-game-folders')
        }
        New-Item -ItemType Directory -Path $fx.Games, $fx.Zips, $fx.State, $fx.Backups, $fx.Target -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $fx.Target 'game.exe'), 'old exe')
        [IO.File]::WriteAllText((Join-Path $fx.Target 'save.dat'), 'my save')
        New-F412Zip -Path $fx.Zip -Entries ([ordered]@{ 'game.exe' = 'new exe'; 'data/level.bin' = 'new level' })
        $script:TpmOwnedLayout = [pscustomobject]@{ State = $fx.State; Backups = $fx.Backups }
        return $fx
    }

    function New-F412Game {
        param($Fixture)
        return [pscustomobject]@{ Code = 'PAPA'; Name = 'Papa Game'; Folder = $Fixture.Target; GamePath = (Join-Path $Fixture.Target 'game.exe') }
    }

    function New-F412Zip {
        param([string]$Path, [System.Collections.IDictionary]$Entries)
        $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew)
        try {
            $archive = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create)
            try {
                foreach ($name in $Entries.Keys) {
                    $entry = $archive.CreateEntry([string]$name)
                    $writer = New-Object IO.StreamWriter($entry.Open(), (New-Object Text.UTF8Encoding($false)))
                    try { $writer.Write([string]$Entries[$name]) } finally { $writer.Dispose() }
                }
            } finally { $archive.Dispose() }
        } finally { $stream.Dispose() }
    }

    function Get-F412TreeDigest {
        param([string]$Path)
        if (-not (Test-Path -LiteralPath $Path)) { return '<absent>' }
        $prefix = [IO.Path]::GetFullPath($Path).TrimEnd('\')
        return ((Get-ChildItem -LiteralPath $Path -Recurse -Force | Sort-Object FullName | ForEach-Object {
            $relative = $_.FullName.Substring($prefix.Length)
            if ($_.PSIsContainer) { $relative + '|dir' } else { $relative + '|' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
        }) -join "`n")
    }

    function Get-F412Sha1 {
        param([string]$Text)
        $sha = [Security.Cryptography.SHA1]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))) -replace '-', '') } finally { $sha.Dispose() }
    }

    function Get-F412Leftovers {
        param($Fixture)
        return @(Get-ChildItem -LiteralPath $Fixture.Root -Force -Filter '.tpm-autosync-*' -ErrorAction SilentlyContinue)
    }
}

AfterAll {
    $script:TpmOwnedLayout = $null
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    $script:TpmProgressModuleImported = $false
    $script:TpmProgressModuleLoadedPath = ''
}

Describe 'Rebuild one game from its ZIP (FIX412)' {
    BeforeEach {
        Mock Write-Host { }
        Mock Get-TpmFolderProcesses { @() }
        Mock Get-TpmDatFilesForGame { $null }
        Mock Read-TpmResetRestoreAnswer { 'YES' }
    }
    AfterEach { $script:TpmOwnedLayout = $null }

    It 'rebuilds the folder from the ZIP and keeps the old folder aside, untouched, without copying it' {
        $fx = New-F412Fixture
        $oldDigest = Get-F412TreeDigest -Path $fx.Target

        $result = Invoke-TpmRebuildOneGame -Game (New-F412Game -Fixture $fx) -InstallFolder $fx.Games -ZipSources @($fx.Zips) -SyncStatePath $fx.SyncState

        $result.Outcome | Should -Be 'SUCCEEDED'
        [IO.File]::ReadAllText((Join-Path $fx.Target 'game.exe')) | Should -BeExactly 'new exe'
        [IO.File]::ReadAllText((Join-Path $fx.Target 'data\level.bin')) | Should -BeExactly 'new level'
        Test-Path -LiteralPath (Join-Path $fx.Target 'save.dat') | Should -BeFalse
        $kept = @(Get-ChildItem -LiteralPath $fx.KeptRoot -Directory)
        $kept.Count | Should -Be 1
        (Get-F412TreeDigest -Path $kept[0].FullName) | Should -BeExactly $oldDigest
        $result.Summary | Should -Match ([regex]::Escape($kept[0].FullName))
        Test-Path -LiteralPath ($kept[0].FullName + '.tpm.json') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $fx.Backups 'AutoSyncReplaced') | Should -BeFalse
        @(Get-F412Leftovers -Fixture $fx).Count | Should -Be 0
        Test-Path -LiteralPath $fx.SyncState | Should -BeTrue
    }

    It 'says plainly when the ZIP is not found and changes nothing' {
        $fx = New-F412Fixture
        Remove-Item -LiteralPath $fx.Zip -Force
        New-F412Zip -Path (Join-Path $fx.Zips 'Some Other Game.zip') -Entries ([ordered]@{ 'other.exe' = 'x' })
        $oldDigest = Get-F412TreeDigest -Path $fx.Target

        $result = Invoke-TpmRebuildOneGame -Game (New-F412Game -Fixture $fx) -InstallFolder $fx.Games -ZipSources @($fx.Zips) -SyncStatePath $fx.SyncState

        $result.Outcome | Should -Be 'FAILED_BEFORE_MUTATION'
        $result.ReasonCode | Should -Be 'ZIP_NOT_FOUND'
        $result.Summary | Should -Match 'could not find the ZIP'
        (Get-F412TreeDigest -Path $fx.Target) | Should -BeExactly $oldDigest
        Test-Path -LiteralPath $fx.KeptRoot | Should -BeFalse
        Should -Invoke Read-TpmResetRestoreAnswer -Times 0 -Exactly
    }

    It 'refuses a ZIP whose files do not match the DAT checksum and changes nothing' {
        $fx = New-F412Fixture
        Mock Get-TpmDatFilesForGame { , @([pscustomobject]@{ Name = 'game.exe'; Size = '7'; Sha1 = ('A' * 40) }) }
        $oldDigest = Get-F412TreeDigest -Path $fx.Target

        $result = Invoke-TpmRebuildOneGame -Game (New-F412Game -Fixture $fx) -InstallFolder $fx.Games -ZipSources @($fx.Zips) -SyncStatePath $fx.SyncState

        $result.Outcome | Should -Be 'FAILED_BEFORE_MUTATION'
        $result.ReasonCode | Should -Be 'DAT_MISMATCH'
        (Get-F412TreeDigest -Path $fx.Target) | Should -BeExactly $oldDigest
        Test-Path -LiteralPath $fx.KeptRoot | Should -BeFalse
        @(Get-F412Leftovers -Fixture $fx).Count | Should -Be 0
    }

    It 'accepts a ZIP whose files match the DAT checksum' {
        $fx = New-F412Fixture
        Mock Get-TpmDatFilesForGame { , @([pscustomobject]@{ Name = 'game.exe'; Size = '7'; Sha1 = (Get-F412Sha1 -Text 'new exe') }) }

        $result = Invoke-TpmRebuildOneGame -Game (New-F412Game -Fixture $fx) -InstallFolder $fx.Games -ZipSources @($fx.Zips) -SyncStatePath $fx.SyncState

        $result.Outcome | Should -Be 'SUCCEEDED'
        [IO.File]::ReadAllText((Join-Path $fx.Target 'game.exe')) | Should -BeExactly 'new exe'
    }

    It 'refuses before asking when there is not enough free space, and changes nothing' {
        $fx = New-F412Fixture
        Mock Get-TpmAutoSyncStagingSpaceState { 'Short' }
        $oldDigest = Get-F412TreeDigest -Path $fx.Target

        $result = Invoke-TpmRebuildOneGame -Game (New-F412Game -Fixture $fx) -InstallFolder $fx.Games -ZipSources @($fx.Zips) -SyncStatePath $fx.SyncState

        $result.Outcome | Should -Be 'FAILED_BEFORE_MUTATION'
        $result.ReasonCode | Should -Be 'INSUFFICIENT_STAGING_SPACE'
        $result.Summary | Should -Match 'not enough free space'
        (Get-F412TreeDigest -Path $fx.Target) | Should -BeExactly $oldDigest
        Test-Path -LiteralPath $fx.KeptRoot | Should -BeFalse
        Should -Invoke Read-TpmResetRestoreAnswer -Times 0 -Exactly
    }

    It 'stops before changing anything when the space runs out inside the rebuild itself' {
        $fx = New-F412Fixture
        $oldDigest = Get-F412TreeDigest -Path $fx.Target
        Mock Get-TpmAutoSyncStagingSpaceState { 'Short' }

        $result = Invoke-TpmRebuildGame -Game (New-F412Game -Fixture $fx) -ZipPath $fx.Zip -InstallFolder $fx.Games -SyncStatePath $fx.SyncState

        $result.Outcome | Should -Be 'FAILED_BEFORE_MUTATION'
        $result.ReasonCode | Should -Be 'INSUFFICIENT_STAGING_SPACE'
        (Get-F412TreeDigest -Path $fx.Target) | Should -BeExactly $oldDigest
        @(Get-F412Leftovers -Fixture $fx).Count | Should -Be 0
    }

    It 'puts the old folder back untouched when the swap fails half way' {
        $fx = New-F412Fixture
        $oldDigest = Get-F412TreeDigest -Path $fx.Target
        $script:f412PromoteFailed = $false
        $script:f412Target = $fx.Target
        Mock Invoke-TpmAutoSyncMovePath {
            if (-not $script:f412PromoteFailed -and [IO.Path]::GetFullPath($Destination).TrimEnd('\') -ieq [IO.Path]::GetFullPath($script:f412Target).TrimEnd('\')) {
                $script:f412PromoteFailed = $true
                throw 'simulated failure while putting the new folder in place'
            }
            & $script:f412RealMove @PesterBoundParameters
        }

        $result = Invoke-TpmRebuildGame -Game (New-F412Game -Fixture $fx) -ZipPath $fx.Zip -InstallFolder $fx.Games -SyncStatePath $fx.SyncState

        $result.Outcome | Should -Be 'ROLLED_BACK_VERIFIED'
        (Get-F412TreeDigest -Path $fx.Target) | Should -BeExactly $oldDigest
        Test-Path -LiteralPath $fx.KeptRoot | Should -BeFalse
        @(Get-F412Leftovers -Fixture $fx).Count | Should -Be 0
    }

    It 'names the folder that really holds the old files when the cleanup of the extraction marker fails' {
        # Mutation: take the first leftover path (the marker file) instead of the transaction folder -> the message names a folder that does not exist.
        $fx = New-F412Fixture
        $script:f412RealRemove = ${function:Invoke-TpmAutoSyncRemovePath}
        Mock Invoke-TpmAutoSyncRemovePath {
            if ([string]$Path -like '*.extracting') { throw 'simulated lock on the marker file' }
            & $script:f412RealRemove @PesterBoundParameters
        }

        $result = Invoke-TpmRebuildGame -Game (New-F412Game -Fixture $fx) -ZipPath $fx.Zip -InstallFolder $fx.Games -SyncStatePath $fx.SyncState

        $result.Outcome | Should -Be 'SUCCEEDED'
        $keptAt = [string]($result.Summary -replace '^.*It is kept here: ', '')
        Test-Path -LiteralPath $keptAt -PathType Container | Should -BeTrue
        [IO.File]::ReadAllText((Join-Path $keptAt 'save.dat')) | Should -BeExactly 'my save'
    }

    It 'says so when only the AutoSync record of an up-to-date game was repaired' {
        # Mutation: always say "Nothing was changed" for a rebuild that finds the folder already matches -> the repaired record goes unmentioned.
        $fx = New-F412Fixture
        $first = Invoke-TpmRebuildGame -Game (New-F412Game -Fixture $fx) -ZipPath $fx.Zip -InstallFolder $fx.Games -SyncStatePath $fx.SyncState
        $first.Outcome | Should -Be 'SUCCEEDED'
        [IO.File]::WriteAllText($fx.SyncState, '{}')

        $second = Invoke-TpmRebuildGame -Game (New-F412Game -Fixture $fx) -ZipPath $fx.Zip -InstallFolder $fx.Games -SyncStatePath $fx.SyncState

        $second.Outcome | Should -Be 'NO_OP'
        $second.Summary | Should -Match 'AutoSync record'
    }

    It 'changes nothing when the answer is not YES' {
        $fx = New-F412Fixture
        Mock Read-TpmResetRestoreAnswer { 'no' }
        $oldDigest = Get-F412TreeDigest -Path $fx.Target

        $result = Invoke-TpmRebuildOneGame -Game (New-F412Game -Fixture $fx) -InstallFolder $fx.Games -ZipSources @($fx.Zips) -SyncStatePath $fx.SyncState

        $result.Outcome | Should -Be 'NO_OP'
        (Get-F412TreeDigest -Path $fx.Target) | Should -BeExactly $oldDigest
        Test-Path -LiteralPath $fx.KeptRoot | Should -BeFalse
    }

    It 'does not start while the game is running' {
        $fx = New-F412Fixture
        Mock Get-TpmFolderProcesses { @('papagame') }
        $oldDigest = Get-F412TreeDigest -Path $fx.Target

        $result = Invoke-TpmRebuildOneGame -Game (New-F412Game -Fixture $fx) -InstallFolder $fx.Games -ZipSources @($fx.Zips) -SyncStatePath $fx.SyncState

        $result.ReasonCode | Should -Be 'GAME_RUNNING'
        (Get-F412TreeDigest -Path $fx.Target) | Should -BeExactly $oldDigest
    }
}

Describe 'Undo and clean up a rebuild (FIX412)' {
    BeforeEach {
        Mock Write-Host { }
        Mock Get-TpmFolderProcesses { @() }
        Mock Get-TpmDatFilesForGame { $null }
        Mock Read-TpmResetRestoreAnswer { 'YES' }
    }
    AfterEach { $script:TpmOwnedLayout = $null }

    It 'puts the old folder back and keeps the rebuilt one aside' {
        $fx = New-F412Fixture
        $oldDigest = Get-F412TreeDigest -Path $fx.Target
        $null = Invoke-TpmRebuildOneGame -Game (New-F412Game -Fixture $fx) -InstallFolder $fx.Games -ZipSources @($fx.Zips) -SyncStatePath $fx.SyncState
        $kept = @(Get-TpmRebuildKeptFolders -InstallFolder $fx.Games)[0]

        $result = Restore-TpmRebuildKeptFolder -Kept $kept -InstallFolder $fx.Games

        $result.Outcome | Should -Be 'SUCCEEDED'
        (Get-F412TreeDigest -Path $fx.Target) | Should -BeExactly $oldDigest
        $keptNow = @(Get-ChildItem -LiteralPath $fx.KeptRoot -Directory)
        $keptNow.Count | Should -Be 1
        [IO.File]::ReadAllText((Join-Path $keptNow[0].FullName 'game.exe')) | Should -BeExactly 'new exe'
    }

    It 'deletes a kept old folder only when asked, and never a folder outside the kept place' {
        $fx = New-F412Fixture
        $null = Invoke-TpmRebuildOneGame -Game (New-F412Game -Fixture $fx) -InstallFolder $fx.Games -ZipSources @($fx.Zips) -SyncStatePath $fx.SyncState
        $kept = @(Get-TpmRebuildKeptFolders -InstallFolder $fx.Games)[0]
        $outside = [pscustomobject]@{ Name = 'Games'; Path = $fx.Games; RecordPath = ($fx.Games + '.tpm.json'); Record = $null }

        $refused = Remove-TpmRebuildKeptFolder -Kept $outside -InstallFolder $fx.Games
        $refused.Outcome | Should -Be 'FAILED_BEFORE_MUTATION'
        Test-Path -LiteralPath $fx.Games | Should -BeTrue

        $deleted = Remove-TpmRebuildKeptFolder -Kept $kept -InstallFolder $fx.Games
        $deleted.Outcome | Should -Be 'SUCCEEDED'
        Test-Path -LiteralPath $kept.Path | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $fx.Target 'game.exe') | Should -BeTrue
    }
}

Describe 'The DAT list check reads the real DAT and is not offered for folders TPM did not keep (FIX412)' {
    BeforeEach {
        Mock Write-Host { }
        Mock Get-TpmFolderProcesses { @() }
    }
    AfterEach { $script:TpmOwnedLayout = $null }

    It 'collects one game''s files with size and SHA-1 from a DAT file, and finds nothing for a game it does not list' {
        $sha1 = Get-F412Sha1 -Text 'new exe'
        $dat = '<?xml version="1.0"?><datafile><header><name>test</name></header>' +
            '<game name="Papa Game"><GameProfile>PAPA</GameProfile><Executable>game.exe</Executable>' +
            ('<rom name="game.exe" size="7" crc="aaaaaaaa" sha1="{0}"/><rom name="data/level.bin" size="9" sha1="{1}"/></game>' -f $sha1, ('B' * 40)) +
            '<game name="Other Game"><rom name="x.bin" size="1" sha1="' + ('C' * 40) + '"/></game></datafile>'
        $datPath = Join-Path $TestDrive ('f412-' + [guid]::NewGuid().ToString('N') + '.dat')
        [IO.File]::WriteAllText($datPath, $dat, (New-Object Text.UTF8Encoding($false)))

        $files = Get-TpmDatFilesForGame -GameName 'papa game' -DatFilePath $datPath
        @($files).Count | Should -Be 2
        (@($files) | Where-Object { $_.Name -eq 'game.exe' }).Sha1 | Should -BeExactly $sha1
        (@($files) | Where-Object { $_.Name -eq 'game.exe' }).Size | Should -Be '7'
        Get-TpmDatFilesForGame -GameName 'Missing Game' -DatFilePath $datPath | Should -BeNullOrEmpty
    }

    It 'reports a missing file or a different size before anything is unpacked' {
        $fx = New-F412Fixture
        $inventory = Get-TpmAutoSyncZipInventory -ZipPath $fx.Zip -SkipHash
        $good = @([pscustomobject]@{ Name = 'game.exe'; Size = '7'; Sha1 = '' }, [pscustomobject]@{ Name = 'data/level.bin'; Size = '9'; Sha1 = '' })
        (Test-TpmZipFilesAgainstDatList -DatFiles $good -Inventory $inventory).Matches | Should -BeTrue
        $wrongSize = Test-TpmZipFilesAgainstDatList -DatFiles @([pscustomobject]@{ Name = 'game.exe'; Size = '8'; Sha1 = '' }) -Inventory $inventory
        $wrongSize.Matches | Should -BeFalse
        $wrongSize.Summary | Should -Match 'size differs'
        $missing = Test-TpmZipFilesAgainstDatList -DatFiles @([pscustomobject]@{ Name = 'gone.bin'; Size = '1'; Sha1 = '' }) -Inventory $inventory
        $missing.Summary | Should -Match 'missing from the ZIP'
    }

    It 'offers, restores and deletes only folders that have TPM''s own record' {
        $fx = New-F412Fixture
        Mock Get-TpmDatFilesForGame { $null }
        Mock Read-TpmResetRestoreAnswer { 'YES' }
        $null = Invoke-TpmRebuildOneGame -Game (New-F412Game -Fixture $fx) -InstallFolder $fx.Games -ZipSources @($fx.Zips) -SyncStatePath $fx.SyncState
        $stranger = Join-Path $fx.KeptRoot 'Something I put here'
        New-Item -ItemType Directory -Path $stranger -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $stranger 'mine.txt'), 'mine')

        $listed = @(Get-TpmRebuildKeptFolders -InstallFolder $fx.Games)

        $listed.Count | Should -Be 1
        $listed[0].Path | Should -Not -Be $stranger
        $notKept = [pscustomobject]@{ Name = 'Something I put here'; Path = $stranger; RecordPath = ($stranger + '.tpm.json'); Record = $null }
        (Remove-TpmRebuildKeptFolder -Kept $notKept -InstallFolder $fx.Games).Outcome | Should -Be 'FAILED_BEFORE_MUTATION'
        Test-Path -LiteralPath (Join-Path $stranger 'mine.txt') | Should -BeTrue
    }
}
