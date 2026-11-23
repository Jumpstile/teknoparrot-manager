#Requires -Module Pester

# FIX404: AutoSync must not read a game ZIP's data twice just to check it (a 6 GB ZIP took 40 minutes).
# The ZIP's file checksums now come from the one extraction pass; a separate checksum pass over the ZIP
# only happens when an existing game folder might already match it. Isolated fake ZIPs under $TestDrive only.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX404 bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'fix404-autosync-functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    $progressModuleDirectory = Join-Path $TestDrive 'scripts'
    [void][IO.Directory]::CreateDirectory($progressModuleDirectory)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Destination (Join-Path $progressModuleDirectory 'TpmProgress.psm1') -Force
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $script:DisplayVersion = 'v1.0 RC9.1'
    $script:ScriptVersion = '1.0'
    $script:ReleaseCandidateLabel = 'RC9.1'
    $script:ActiveTpmWorkflowStatus = $null
    $script:PostgresRecoveryStatus = $null
    $script:PostgresRecoveryResumeState = $null
    $script:TpmWorkflowRendering = $false
    $script:logPath = Join-Path $TestDrive 'fix404-autosync.log'
    $script:logWarnShown = $false
    $script:RawThrillsPathLimits = @{}
    $script:FileVersionPins = @{}
    $script:GpuIncompatibleGames = @{}
    # The real functions, so a mock can count a call and still do the real work.
    $script:realZipInventory = ${function:Get-TpmAutoSyncZipInventory}
    $script:realExpandZip = ${function:Expand-ZipFileSafe}

    function New-Fix404Fixture {
        $root = Join-Path $TestDrive ('f404-' + [guid]::NewGuid().ToString('N').Substring(0, 10))
        $fx = [pscustomobject]@{
            Root = $root; Games = (Join-Path $root 'Games'); Zips = (Join-Path $root 'Zips')
            State = (Join-Path $root 'State'); Backups = (Join-Path $root 'Backups')
            SyncState = (Join-Path $root 'Games\TeknoParrot-Manager.syncstate.json')
            Target = (Join-Path $root 'Games\Papa Game')
            Zip = (Join-Path $root 'Zips\Papa Game.zip')
        }
        New-Item -ItemType Directory -Path $fx.Games, $fx.Zips, $fx.State, $fx.Backups -Force | Out-Null
        # An existing folder is replaced only when its extra files can be kept in Backups.
        $script:TpmOwnedLayout = [pscustomobject]@{ State = $fx.State; Backups = $fx.Backups }
        return $fx
    }

    function New-Fix404Zip {
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

    function Invoke-Fix404Transaction {
        param($Fixture, [switch]$NewTarget)
        return (Invoke-TpmAutoSyncDirectoryTransaction -ZipPath $Fixture.Zip -InstallFolder $Fixture.Games -TargetDir $Fixture.Target `
            -RawName 'Papa Game' -SyncStatePath $Fixture.SyncState -SyncState @{} -NewTarget:$NewTarget)
    }

    function Get-Fix404TreeDigest {
        param([string]$Path)
        if (-not (Test-Path -LiteralPath $Path)) { return '<absent>' }
        $prefix = [IO.Path]::GetFullPath($Path).TrimEnd('\')
        return ((Get-ChildItem -LiteralPath $Path -Recurse -Force | Sort-Object FullName | ForEach-Object {
            $relative = $_.FullName.Substring($prefix.Length)
            if ($_.PSIsContainer) { $relative + '|dir' } else { $relative + '|' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
        }) -join "`n")
    }
}

AfterAll {
    $script:TpmOwnedLayout = $null
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    $script:TpmProgressModuleImported = $false
    $script:TpmProgressModuleLoadedPath = ''
}

Describe 'FIX404 AutoSync reads a game ZIP once' {
    BeforeEach {
        Mock Get-TpmAutoSyncZipInventory { & $script:realZipInventory @PesterBoundParameters }
        Mock Expand-ZipFileSafe { & $script:realExpandZip @PesterBoundParameters }
    }
    AfterEach { $script:TpmOwnedLayout = $null }

    It 'extracts a new game folder with no separate checksum pass over the ZIP' {
        # Mutation: hash every ZIP entry in the inventory before extracting (the old behavior) -> a second full read.
        $fx = New-Fix404Fixture
        New-Fix404Zip -Path $fx.Zip -Entries ([ordered]@{ 'game.exe' = 'new exe'; 'data/level.bin' = 'new level' })

        $tx = Invoke-Fix404Transaction -Fixture $fx -NewTarget

        $tx.TransactionResult.Outcome | Should -Be 'SUCCEEDED'
        [IO.File]::ReadAllText((Join-Path $fx.Target 'game.exe')) | Should -BeExactly 'new exe'
        [IO.File]::ReadAllText((Join-Path $fx.Target 'data\level.bin')) | Should -BeExactly 'new level'
        Should -Invoke Get-TpmAutoSyncZipInventory -Times 1 -Exactly -ParameterFilter { $SkipHash }
        Should -Invoke Get-TpmAutoSyncZipInventory -Times 0 -Exactly -ParameterFilter { -not $SkipHash }
        Should -Invoke Expand-ZipFileSafe -Times 1 -Exactly
    }

    It 'replaces a folder with different file sizes with no separate checksum pass over the ZIP, and keeps the old save' {
        # Mutation: always hash the ZIP before extraction -> the ZIP is read twice when it replaces a folder.
        $fx = New-Fix404Fixture
        New-Fix404Zip -Path $fx.Zip -Entries ([ordered]@{ 'game.exe' = 'new exe, longer than the old one' })
        New-Item -ItemType Directory -Path $fx.Target -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $fx.Target 'game.exe'), 'old')
        [IO.File]::WriteAllText((Join-Path $fx.Target 'save.dat'), 'my-save')

        $tx = Invoke-Fix404Transaction -Fixture $fx

        $tx.TransactionResult.Outcome | Should -Be 'SUCCEEDED'
        [IO.File]::ReadAllText((Join-Path $fx.Target 'game.exe')) | Should -BeExactly 'new exe, longer than the old one'
        $saved = @(Get-ChildItem -LiteralPath $fx.Backups -Recurse -File | Where-Object { $_.Name -eq 'save.dat' })
        $saved.Count | Should -Be 1
        [IO.File]::ReadAllText($saved[0].FullName) | Should -BeExactly 'my-save'
        Should -Invoke Get-TpmAutoSyncZipInventory -Times 0 -Exactly -ParameterFilter { -not $SkipHash }
        Should -Invoke Expand-ZipFileSafe -Times 1 -Exactly
    }

    It 'checks a folder that already matches the ZIP with one pass over the ZIP and extracts nothing' {
        # Mutation: extract the ZIP again for a folder that is already right -> the extra full write and read come back.
        $fx = New-Fix404Fixture
        New-Fix404Zip -Path $fx.Zip -Entries ([ordered]@{ 'game.exe' = 'same exe'; 'data/level.bin' = 'same level' })
        New-Item -ItemType Directory -Path (Join-Path $fx.Target 'data') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $fx.Target 'game.exe'), 'same exe')
        [IO.File]::WriteAllText((Join-Path $fx.Target 'data\level.bin'), 'same level')
        $before = Get-Fix404TreeDigest $fx.Target

        $tx = Invoke-Fix404Transaction -Fixture $fx

        $tx.TransactionResult.Outcome | Should -Be 'SUCCEEDED'
        Get-Fix404TreeDigest $fx.Target | Should -Be $before
        Should -Invoke Get-TpmAutoSyncZipInventory -Times 1 -Exactly -ParameterFilter { -not $SkipHash }
        Should -Invoke Expand-ZipFileSafe -Times 0 -Exactly
    }

    It 'still stops and keeps the old folder when a staged file does not match what was read from the ZIP' {
        # Mutation: trust the checksums reported by extraction without comparing them to the staged files -> a bad write is installed.
        $fx = New-Fix404Fixture
        New-Fix404Zip -Path $fx.Zip -Entries ([ordered]@{ 'game.exe' = 'new exe' })
        New-Item -ItemType Directory -Path $fx.Target -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $fx.Target 'game.exe'), 'old')
        [IO.File]::WriteAllText((Join-Path $fx.Target 'save.dat'), 'my-save')
        $before = Get-Fix404TreeDigest $fx.Target
        $goodHash = (-join ([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes('new exe')) | ForEach-Object { $_.ToString('x2') })).ToUpperInvariant()
        Mock Expand-ZipFileSafe {
            param([string]$ZipPath, [string]$DestDir, [string]$GameName, [hashtable]$EntryHashes)
            [void][IO.Directory]::CreateDirectory($DestDir)
            [IO.File]::WriteAllText((Join-Path $DestDir 'game.exe'), 'tampered on the way to disk')
            $EntryHashes['game.exe'] = $goodHash
        }

        $tx = Invoke-Fix404Transaction -Fixture $fx

        $tx.TransactionResult.Outcome | Should -Not -Be 'SUCCEEDED'
        Get-Fix404TreeDigest $fx.Target | Should -Be $before
    }

    It 'still catches a damaged ZIP before anything is changed' {
        # Mutation: skip reading the ZIP's central directory (or swallow its error) -> a broken ZIP replaces a good folder.
        $fx = New-Fix404Fixture
        New-Fix404Zip -Path $fx.Zip -Entries ([ordered]@{ 'game.exe' = ('x' * 5000); 'data/level.bin' = ('y' * 5000) })
        $bytes = [IO.File]::ReadAllBytes($fx.Zip)
        [IO.File]::WriteAllBytes($fx.Zip, [byte[]]@($bytes[0..([int]($bytes.Length / 2))]))
        New-Item -ItemType Directory -Path $fx.Target -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $fx.Target 'game.exe'), 'old')
        [IO.File]::WriteAllText((Join-Path $fx.Target 'save.dat'), 'my-save')
        $before = Get-Fix404TreeDigest $fx.Target

        $tx = Invoke-Fix404Transaction -Fixture $fx

        $tx.TransactionResult.Outcome | Should -Not -Be 'SUCCEEDED'
        Get-Fix404TreeDigest $fx.Target | Should -Be $before
        Should -Invoke Expand-ZipFileSafe -Times 0 -Exactly
    }
}
