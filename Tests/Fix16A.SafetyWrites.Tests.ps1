#Requires -Module Pester

# FIX16A safety-write regressions (ASTRA-01/02/03/04/05/06). The production
# script is parsed and only the functions under test plus their direct
# helpers are dot-sourced; dependencies outside this scope are inert stubs.
BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:sourcePath = Join-Path $script:repoRoot 'TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:sourcePath,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if ($parseErrors.Count -gt 0) {
        throw "Failed to parse TeknoParrot-Manager.ps1: $($parseErrors -join '; ')"
    }

    $wanted = @(
        'Measure-PathWriteThroughput',
        'Test-TpmNoReparsePath','Test-TpmPathLengthAllowed',
        'Assert-TpmNoReparseWriteTarget',
        'Invoke-TpmAtomicFileReplace',
        'Write-TpmAtomicTextFile',
        'Save-Xml',
        'Save-Config',
        'Get-TpmConfigDocument',
        'ConvertTo-TpmConfigFieldMap',
        'Set-TpmConfigBaseline',
        'Read-TpmConfigFile',
        'Merge-TpmConfigFileChanges',
        'Get-TpmConfigDocumentToSave',
        'Publish-TpmConfigDocument',
        'Get-TpmAutoSyncSha256',
        'Get-TpmAutoSyncTextSha256',
        'ConvertTo-TpmAutoSyncLongPath',
        'Get-TpmReShadeStatePath',
        'Write-TpmReShadeState',
        'New-ManagerUpdateBackup',
        'Test-ManagerUpdatePackageIsSingleScript',
        'Test-PostgresInstallationsRegistry',
        'Get-PostgresPartialInstallInventory',
        'Show-PostgresPartialInstallRefusal',
        'Install-Postgres83'
    )
    $functions = @(
        $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -in $wanted
        }, $true)
    )
    if ($functions.Count -ne $wanted.Count) {
        throw "Expected $($wanted.Count) function definitions; found $($functions.Count): $(($functions | ForEach-Object { $_.Name }) -join ', ')"
    }

    $functionPath = Join-Path $TestDrive ('f16sw-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.ps1')
    ($functions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" |
        Set-Content -LiteralPath $functionPath -Encoding utf8
    . $functionPath
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')

    Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

    # Dependencies outside these fixes. Signatures mirror production so
    # Mock parameter binding behaves the same.
    function Write-Log {
        param([string]$msg)
    }
    function Write-TpmCompactExtractionProgress {
        param([string]$Phase = 'Extracting', [string]$Label, [long]$Current, [long]$Total, [datetime]$StartedAt = (Get-Date), [int]$Width = 0, [switch]$Complete, [switch]$Substage, [string]$Outcome = 'Final', [switch]$ReturnText, [switch]$Completed, [string]$Unit = 'Items')
    }
    function Test-RunningAsAdministrator { return $false }
    function Read-ConfirmedPostgresPassword {
        param([string]$WhatFor)
        throw 'Read-ConfirmedPostgresPassword stub must be mocked.'
    }
    function Get-PostgresGuideRelease { throw 'Get-PostgresGuideRelease stub must be mocked.' }
    function Invoke-PostgresMsiPackage {
        param([string]$MsiPath, [string]$PropertyValues)
        throw 'Invoke-PostgresMsiPackage stub must be mocked.'
    }
    # LocalAccounts cmdlets are absent on some hosts; give Mock a target.
    if (-not (Get-Command -Name Get-LocalUser -ErrorAction SilentlyContinue)) {
        function Get-LocalUser { param([string]$Name) }
    }
    if (-not (Get-Command -Name Remove-LocalUser -ErrorAction SilentlyContinue)) {
        function Remove-LocalUser { param($Name) }
    }

    function New-Fix16aDir {
        param([string]$Prefix = 'd')
        $dir = Join-Path $TestDrive ($Prefix + [guid]::NewGuid().ToString('N').Substring(0, 8))
        [void][System.IO.Directory]::CreateDirectory($dir)
        return $dir
    }
    function Get-Fix16aHex {
        param([string]$Path)
        return [System.BitConverter]::ToString([System.IO.File]::ReadAllBytes($Path))
    }
    function New-Fix16aZip {
        param([string]$Path, [string[]]$Entries)
        $zip = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($name in $Entries) {
                $entry = $zip.CreateEntry($name)
                if ($name.EndsWith('/')) { continue }
                $stream = $entry.Open()
                try {
                    $bytes = [System.Text.Encoding]::ASCII.GetBytes("# $name`r`n")
                    $stream.Write($bytes, 0, $bytes.Length)
                } finally {
                    $stream.Dispose()
                }
            }
        } finally {
            $zip.Dispose()
        }
    }
    function Set-Fix16aConfigState {
        param([string]$ConfigPath, [string]$TpRoot)
        $script:configPath = $ConfigPath
        $script:tpRoot = $TpRoot
        $script:zipSource = 'D:\Zips'
        $script:zipSourceSupplementary = $null
        $script:gamesInstallFolder = 'D:\Games'
        $script:retroBat = $null
        $script:rsSourceDll = $null
        $script:dgSourceDir = $null
        $script:eggmanDatZip = $null
        $script:datFilePath = $null
        $script:supplementaryDatPath = $null
        $script:includeSupplementary = $false
        $script:lbRoot = $null
        $script:postgresSuperPasswordEncrypted = 'ENCRYPTED-KEEP'
        $script:checkForUpdatesOnStartup = $true
        $script:unattendedModeSaved = $null
    }
}

Describe 'Measure-PathWriteThroughput unique probe file (ASTRA-02)' {
    It 'returns null for a missing directory and creates nothing' {
        $parent = New-Fix16aDir -Prefix 'm'
        $missing = Join-Path $parent 'nope'

        $result = Measure-PathWriteThroughput -path $missing

        $result | Should -BeNullOrEmpty
        Test-Path -LiteralPath $missing | Should -BeFalse
        @(Get-ChildItem -LiteralPath $parent -Force).Count | Should -Be 0
    }

    It 'leaves a pre-existing file with the old fixed probe name byte-identical and removes its own probe' {
        $dir = New-Fix16aDir -Prefix 'm'
        $legacy = Join-Path $dir '._tp_write_test_tmp'
        [System.IO.File]::WriteAllBytes($legacy, [byte[]](0x4B, 0x45, 0x45, 0x50, 0x00, 0xFF))
        $before = Get-Fix16aHex -Path $legacy
        # Prove the probe really wrote its full sample, and that even a very fast disk
        # gives a speed (a quick write is never reported as "could not be measured").
        $script:fix16aWriteClose = New-Object System.Collections.Generic.List[object]
        Mock Write-TpmCompactExtractionProgress { if ($Complete) { [void]$script:fix16aWriteClose.Add([pscustomobject]@{ Current = $Current; Outcome = $Outcome }) } }

        $speed = Measure-PathWriteThroughput -path $dir

        $speed | Should -BeGreaterThan 0
        @($script:fix16aWriteClose | Where-Object { $_.Current -eq 10MB -and $_.Outcome -eq 'Final' }).Count | Should -Be 1
        Get-Fix16aHex -Path $legacy | Should -Be $before
        (@(Get-ChildItem -LiteralPath $dir -Force | ForEach-Object { $_.Name }) -join '|') | Should -Be '._tp_write_test_tmp'
    }

    It 'probes through a GUID-named temp file that no longer exists afterwards' {
        $dir = New-Fix16aDir -Prefix 'm'
        $script:fix16aProbePaths = New-Object System.Collections.Generic.List[string]
        Mock Assert-TpmNoReparseWriteTarget { [void]$script:fix16aProbePaths.Add($Path) }

        $null = Measure-PathWriteThroughput -path $dir

        $script:fix16aProbePaths.Count | Should -Be 1
        Split-Path -Leaf $script:fix16aProbePaths[0] | Should -Match '^\._tp_write_test_[0-9a-f]{32}\.tmp$'
        Split-Path -Parent $script:fix16aProbePaths[0] | Should -Be $dir
        Test-Path -LiteralPath $script:fix16aProbePaths[0] | Should -BeFalse
        @(Get-ChildItem -LiteralPath $dir -Force).Count | Should -Be 0
    }

    It 'returns null and creates no file when the reparse-point guard refuses the target' {
        $dir = New-Fix16aDir -Prefix 'm'
        $keep = Join-Path $dir 'keep.bin'
        [System.IO.File]::WriteAllBytes($keep, [byte[]](1, 2, 3))
        Mock Assert-TpmNoReparseWriteTarget { throw 'refused: reparse point' }

        $result = Measure-PathWriteThroughput -path $dir

        $result | Should -BeNullOrEmpty
        (@(Get-ChildItem -LiteralPath $dir -Force | ForEach-Object { $_.Name }) -join '|') | Should -Be 'keep.bin'
        Get-Fix16aHex -Path $keep | Should -Be '01-02-03'
    }

    It 'fails instead of truncating when a file appears at the probe name before it is opened (CreateNew)' {
        $dir = New-Fix16aDir -Prefix 'm'
        $script:fix16aPlanted = $null
        Mock Assert-TpmNoReparseWriteTarget {
            [System.IO.File]::WriteAllBytes($Path, [byte[]](0xDE, 0xAD, 0xBE, 0xEF))
            $script:fix16aPlanted = $Path
        }

        $result = Measure-PathWriteThroughput -path $dir

        $result | Should -BeNullOrEmpty
        $script:fix16aPlanted | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $script:fix16aPlanted -PathType Leaf | Should -BeTrue
        Get-Fix16aHex -Path $script:fix16aPlanted | Should -Be 'DE-AD-BE-EF'
    }
}

Describe 'Write-TpmAtomicTextFile (ASTRA-03/06)' {
    It 'publishes a new file as UTF-8 without BOM and leaves no temp file' {
        $dir = New-Fix16aDir -Prefix 'a'
        $target = Join-Path $dir 'state.json'

        Write-TpmAtomicTextFile -Path $target -Text '{"a":1}'

        [System.BitConverter]::ToString([System.IO.File]::ReadAllBytes($target)) | Should -Be ([System.BitConverter]::ToString([System.Text.Encoding]::ASCII.GetBytes('{"a":1}')))
        (@(Get-ChildItem -LiteralPath $dir -Force | ForEach-Object { $_.Name }) -join '|') | Should -Be 'state.json'
    }

    It 'replaces an existing file with the new text and leaves no temp file' {
        $dir = New-Fix16aDir -Prefix 'a'
        $target = Join-Path $dir 'state.json'
        [System.IO.File]::WriteAllText($target, 'old')

        Write-TpmAtomicTextFile -Path $target -Text 'new' -Validate { param([string]$Written) $Written -eq 'new' }

        [System.IO.File]::ReadAllText($target) | Should -Be 'new'
        (@(Get-ChildItem -LiteralPath $dir -Force | ForEach-Object { $_.Name }) -join '|') | Should -Be 'state.json'
    }

    It 'throws when the folder does not exist and creates nothing' {
        $dir = New-Fix16aDir -Prefix 'a'
        $missingDir = Join-Path $dir 'missing'
        $target = Join-Path $missingDir 'state.json'

        { Write-TpmAtomicTextFile -Path $target -Text 'x' } | Should -Throw '*folder does not exist*'

        Test-Path -LiteralPath $missingDir | Should -BeFalse
    }

    It 'throws on validation failure and keeps the previous bytes without leaving a temp file' {
        $dir = New-Fix16aDir -Prefix 'a'
        $target = Join-Path $dir 'state.json'
        [System.IO.File]::WriteAllBytes($target, [byte[]](0x7B, 0x7D, 0x0D, 0x0A))
        $before = Get-Fix16aHex -Path $target

        { Write-TpmAtomicTextFile -Path $target -Text 'broken' -Validate { param([string]$Written) $false } } | Should -Throw '*failed validation*'

        Get-Fix16aHex -Path $target | Should -Be $before
        (@(Get-ChildItem -LiteralPath $dir -Force | ForEach-Object { $_.Name }) -join '|') | Should -Be 'state.json'
    }

    It 'keeps the previous bytes and removes its temp file when publishing fails' {
        $dir = New-Fix16aDir -Prefix 'a'
        $target = Join-Path $dir 'state.json'
        [System.IO.File]::WriteAllText($target, 'previous')
        $before = Get-Fix16aHex -Path $target
        $lock = [System.IO.File]::Open($target, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        try {
            { Write-TpmAtomicTextFile -Path $target -Text 'replacement' } | Should -Throw
        } finally {
            $lock.Dispose()
        }

        Get-Fix16aHex -Path $target | Should -Be $before
        (@(Get-ChildItem -LiteralPath $dir -Force | ForEach-Object { $_.Name }) -join '|') | Should -Be 'state.json'
    }

    It 'keeps the validated temp and names it when the replace fails after the previous file was removed (FIX21A R2)' {
        $dir = New-Fix16aDir -Prefix 'a'
        $target = Join-Path $dir 'state.json'
        $full = [System.IO.Path]::GetFullPath($target)
        $script:fix16aReplaceTarget = $full
        [System.IO.File]::WriteAllText($target, 'previous')
        $sibling = Join-Path $dir 'keep.txt'
        [System.IO.File]::WriteAllBytes($sibling, [byte[]](0x4B, 0x45, 0x45, 0x50))
        $script:fix16aReplaceSource = $null
        Mock Invoke-TpmAtomicFileReplace {
            $script:fix16aReplaceSource = $Source
            [System.IO.File]::Delete($Destination)
            throw (New-Object System.IO.IOException 'simulated ReplaceFile 1176')
        }

        $err = $null
        try {
            Write-TpmAtomicTextFile -Path $target -Text 'new text' -Validate { param([string]$Written) $Written -eq 'new text' }
        } catch {
            $err = $_
        }

        Should -Invoke Invoke-TpmAtomicFileReplace -Times 1 -Exactly -ParameterFilter { $Destination -eq $script:fix16aReplaceTarget }
        $kept = $script:fix16aReplaceSource
        [System.IO.Path]::GetDirectoryName($kept) | Should -Be ([System.IO.Path]::GetDirectoryName($full))
        [System.IO.Path]::GetFileName($kept) | Should -Match '^state\.json\.[0-9a-f]{32}\.tmp$'
        ($null -eq $err) | Should -BeFalse
        $err.Exception.GetType().FullName | Should -Be 'System.Management.Automation.RuntimeException'
        $err.Exception.Message | Should -BeExactly ("atomic file write to '$full' failed after the previous file was removed; the validated new content was kept at '$kept'. simulated ReplaceFile 1176")
        Test-Path -LiteralPath $kept -PathType Leaf | Should -BeTrue
        Get-Fix16aHex -Path $kept | Should -Be ([System.BitConverter]::ToString([System.Text.Encoding]::ASCII.GetBytes('new text')))
        Test-Path -LiteralPath $full | Should -BeFalse
        Get-Fix16aHex -Path $sibling | Should -Be '4B-45-45-50'
        (@(Get-ChildItem -LiteralPath $dir -Force | ForEach-Object { $_.Name } | Sort-Object) -join '|') | Should -Be ('keep.txt|' + [System.IO.Path]::GetFileName($kept))
    }

    It 'Save-Xml keeps the new profile file when the replace fails after the old profile was removed' {
        $dir = New-Fix16aDir -Prefix 'a'
        $target = Join-Path $dir 'Game.xml'
        $script:fix16aXmlSource = $null
        [System.IO.File]::WriteAllText($target, '<GameProfile><A>old</A></GameProfile>')
        $doc = New-Object System.Xml.XmlDocument
        $doc.LoadXml('<GameProfile><A>new</A></GameProfile>')
        Mock Invoke-TpmAtomicFileReplace {
            $script:fix16aXmlSource = $Source
            [System.IO.File]::Delete($Destination)
            throw (New-Object System.IO.IOException 'simulated ReplaceFile 1176')
        }

        $err = $null
        try { Save-Xml $doc $target } catch { $err = $_ }

        ($null -eq $err) | Should -BeFalse
        $kept = $script:fix16aXmlSource
        $err.Exception.Message | Should -Match 'was kept at'
        Test-Path -LiteralPath $kept -PathType Leaf | Should -BeTrue
        [System.IO.File]::ReadAllText($kept) | Should -Match '<A>new</A>'
    }

    It 'Save-Xml removes its temp file and keeps the old profile when the replace fails and the old profile is still there' {
        $dir = New-Fix16aDir -Prefix 'a'
        $target = Join-Path $dir 'Game.xml'
        [System.IO.File]::WriteAllText($target, '<GameProfile><A>old</A></GameProfile>')
        $doc = New-Object System.Xml.XmlDocument
        $doc.LoadXml('<GameProfile><A>new</A></GameProfile>')
        Mock Invoke-TpmAtomicFileReplace { throw (New-Object System.IO.IOException 'simulated sharing violation') }

        { Save-Xml $doc $target } | Should -Throw

        [System.IO.File]::ReadAllText($target) | Should -Match '<A>old</A>'
        (@(Get-ChildItem -LiteralPath $dir -Force | ForEach-Object { $_.Name }) -join '|') | Should -Be 'Game.xml'
    }

    It 'rethrows the replace error, keeps the previous bytes and removes only its own temp when the target still exists (FIX21A R2)' {
        $dir = New-Fix16aDir -Prefix 'a'
        $target = Join-Path $dir 'state.json'
        $full = [System.IO.Path]::GetFullPath($target)
        $script:fix16aReplaceTarget = $full
        [System.IO.File]::WriteAllText($target, 'previous')
        $before = Get-Fix16aHex -Path $target
        $sibling = Join-Path $dir 'keep.txt'
        [System.IO.File]::WriteAllBytes($sibling, [byte[]](0x4B, 0x45, 0x45, 0x50))
        $script:fix16aReplaceSource = $null
        Mock Invoke-TpmAtomicFileReplace {
            $script:fix16aReplaceSource = $Source
            throw (New-Object System.IO.IOException 'simulated ReplaceFile 1176')
        }

        $err = $null
        try {
            Write-TpmAtomicTextFile -Path $target -Text 'replacement'
        } catch {
            $err = $_
        }

        Should -Invoke Invoke-TpmAtomicFileReplace -Times 1 -Exactly -ParameterFilter { $Destination -eq $script:fix16aReplaceTarget }
        ($null -eq $err) | Should -BeFalse
        $err.Exception.GetBaseException().GetType().FullName | Should -Be 'System.IO.IOException'
        $err.Exception.GetBaseException().Message | Should -BeExactly 'simulated ReplaceFile 1176'
        $err.Exception.Message | Should -Not -Match 'validated new content was kept'
        [System.IO.Path]::GetFileName($script:fix16aReplaceSource) | Should -Match '^state\.json\.[0-9a-f]{32}\.tmp$'
        Test-Path -LiteralPath $script:fix16aReplaceSource | Should -BeFalse
        Get-Fix16aHex -Path $target | Should -Be $before
        Get-Fix16aHex -Path $sibling | Should -Be '4B-45-45-50'
        (@(Get-ChildItem -LiteralPath $dir -Force | ForEach-Object { $_.Name } | Sort-Object) -join '|') | Should -Be 'keep.txt|state.json'
    }

    It 'refuses to write through a junction folder' {
        $dir = New-Fix16aDir -Prefix 'a'
        $real = Join-Path $dir 'real'
        [void][System.IO.Directory]::CreateDirectory($real)
        $link = Join-Path $dir 'link'
        try {
            New-Item -ItemType Junction -Path $link -Value $real -ErrorAction Stop | Out-Null
        } catch {
            Set-ItResult -Skipped -Because "a junction could not be created on this host: $($_.Exception.Message)"
            return
        }
        try {
            { Write-TpmAtomicTextFile -Path (Join-Path $link 'state.json') -Text 'x' } | Should -Throw '*reparse point*'
            @(Get-ChildItem -LiteralPath $real -Force).Count | Should -Be 0
        } finally {
            [System.IO.Directory]::Delete($link)
        }
    }
}

Describe 'Save-Config atomic settings save (ASTRA-06)' {
    It 'returns true and writes a config that parses with TeknoParrotRoot' {
        $dir = New-Fix16aDir -Prefix 'c'
        $cfgPath = Join-Path $dir 'cfg.json'
        Set-Fix16aConfigState -ConfigPath $cfgPath -TpRoot 'D:\TeknoParrot'

        $result = Save-Config

        $result | Should -BeTrue
        $parsed = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json
        $parsed.TeknoParrotRoot | Should -Be 'D:\TeknoParrot'
        $parsed.PostgresSuperPasswordEncrypted | Should -Be 'ENCRYPTED-KEEP'
        (@(Get-ChildItem -LiteralPath $dir -Force | ForEach-Object { $_.Name }) -join '|') | Should -Be 'cfg.json'
    }

    It 'returns false and keeps the previous config bytes when the write fails' {
        $dir = New-Fix16aDir -Prefix 'c'
        $cfgPath = Join-Path $dir 'cfg.json'
        [System.IO.File]::WriteAllText($cfgPath, '{"TeknoParrotRoot":"C:\\Old"}')
        $before = Get-Fix16aHex -Path $cfgPath
        Set-Fix16aConfigState -ConfigPath $cfgPath -TpRoot 'D:\New'
        Mock Write-TpmAtomicTextFile { throw 'disk full' }
        Mock Write-Log {}

        $result = Save-Config

        $result | Should -BeFalse
        Get-Fix16aHex -Path $cfgPath | Should -Be $before
        Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $msg -like '*could not save*disk full*' }
    }

    It 'returns false and creates nothing when the config folder is missing' {
        $dir = New-Fix16aDir -Prefix 'c'
        $missingDir = Join-Path $dir 'gone'
        Set-Fix16aConfigState -ConfigPath (Join-Path $missingDir 'cfg.json') -TpRoot 'D:\TeknoParrot'

        $result = Save-Config

        $result | Should -BeFalse
        Test-Path -LiteralPath $missingDir | Should -BeFalse
    }
}

Describe 'Write-TpmReShadeState unique temp publish (ASTRA-03)' {
    It 'never writes or follows a pre-existing profiles.json.tmp and leaves no new temp file' {
        $root = Join-Path (New-Fix16aDir -Prefix 'r') 'st'
        [void][System.IO.Directory]::CreateDirectory($root)
        $oldTmp = Join-Path $root 'profiles.json.tmp'
        [System.IO.File]::WriteAllBytes($oldTmp, [byte[]](0x50, 0x4C, 0x41, 0x4E, 0x54))
        $before = Get-Fix16aHex -Path $oldTmp
        $state = [pscustomobject]@{ Profiles = [pscustomobject]@{ GameA = 'P1' }; Favorites = @('F1'); History = [pscustomobject]@{} }

        $result = Write-TpmReShadeState -State $state -StateRoot $root

        $result | Should -BeTrue
        Get-Fix16aHex -Path $oldTmp | Should -Be $before
        $written = [System.IO.File]::ReadAllText((Join-Path $root 'profiles.json')) | ConvertFrom-Json
        $written.Profiles.GameA | Should -Be 'P1'
        (@(Get-ChildItem -LiteralPath $root -Force | ForEach-Object { $_.Name } | Sort-Object) -join '|') | Should -Be 'profiles.json|profiles.json.tmp'
    }

    It 'creates a missing state root and replaces an existing state on the next write' {
        $root = Join-Path (New-Fix16aDir -Prefix 'r') 'st'

        Write-TpmReShadeState -State ([pscustomobject]@{ Profiles = [pscustomobject]@{ GameA = 'P1' } }) -StateRoot $root | Should -BeTrue
        Write-TpmReShadeState -State ([pscustomobject]@{ Profiles = [pscustomobject]@{ GameA = 'P2' } }) -StateRoot $root | Should -BeTrue

        $written = [System.IO.File]::ReadAllText((Join-Path $root 'profiles.json')) | ConvertFrom-Json
        $written.Profiles.GameA | Should -Be 'P2'
        (@(Get-ChildItem -LiteralPath $root -Force | ForEach-Object { $_.Name }) -join '|') | Should -Be 'profiles.json'
    }
}

Describe 'New-ManagerUpdateBackup unique backup folders (ASTRA-05)' {
    It 'creates two distinct verified backups within the same second' {
        $dir = New-Fix16aDir -Prefix 'b'
        $source = Join-Path $dir 'TeknoParrot-Manager.ps1'
        [System.IO.File]::WriteAllText($source, '$ScriptVersion = "1.0"')
        $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        Mock Get-Date { New-Object System.DateTime -ArgumentList 2026, 10, 31, 12, 34, 56 }

        $first = New-ManagerUpdateBackup -Path $source
        $second = New-ManagerUpdateBackup -Path $source

        $firstDir = Split-Path -Parent $first
        $secondDir = Split-Path -Parent $second
        $firstDir | Should -Not -Be $secondDir
        foreach ($backupDir in @($firstDir, $secondDir)) {
            Split-Path -Parent $backupDir | Should -Be (Join-Path $dir 'UpdateBackups')
        }
        Split-Path -Leaf $firstDir | Should -BeExactly 'TeknoParrotManager_2026-10-31_12-34-56'
        Split-Path -Leaf $secondDir | Should -BeExactly 'TeknoParrotManager_2026-10-31_12-34-56_2'
        (Get-FileHash -LiteralPath $first -Algorithm SHA256).Hash | Should -Be $sourceHash
        (Get-FileHash -LiteralPath $second -Algorithm SHA256).Hash | Should -Be $sourceHash
        @(Get-ChildItem -LiteralPath (Join-Path $dir 'UpdateBackups') -Directory).Count | Should -Be 2
    }

    It 'never reuses an occupied backup folder and leaves its contents untouched' {
        $dir = New-Fix16aDir -Prefix 'b'
        $source = Join-Path $dir 'TeknoParrot-Manager.ps1'
        [System.IO.File]::WriteAllText($source, '$ScriptVersion = "3.0"')
        $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        $occupied = Join-Path (Join-Path $dir 'UpdateBackups') 'TeknoParrotManager_2026-10-31_12-34-56'
        [void][System.IO.Directory]::CreateDirectory($occupied)
        $earlier = Join-Path $occupied 'TeknoParrot-Manager.ps1'
        [System.IO.File]::WriteAllText($earlier, 'earlier backup bytes')
        $earlierHash = (Get-FileHash -LiteralPath $earlier -Algorithm SHA256).Hash
        Mock Get-Date { New-Object System.DateTime -ArgumentList 2026, 10, 31, 12, 34, 56 }

        $backup = New-ManagerUpdateBackup -Path $source

        Split-Path -Leaf (Split-Path -Parent $backup) | Should -BeExactly 'TeknoParrotManager_2026-10-31_12-34-56_2'
        (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash | Should -Be $sourceHash
        (Get-FileHash -LiteralPath $earlier -Algorithm SHA256).Hash | Should -Be $earlierHash
        @(Get-ChildItem -LiteralPath $occupied -Force).Count | Should -Be 1
    }

    It 'keeps a required-patch recovery backup within the Windows MAX_PATH limit' {
        # Shape of the deepest test-PC required-patch fixture (FIX25): a 174-character
        # recovery run backing up original-0.bin. A GUID folder suffix made this
        # 275 characters, which Windows PowerShell 5.1 cannot create or copy to
        # unless Windows long-path support is enabled (it is off by default).
        $base = New-Fix16aDir -Prefix 'p'
        $padding = 174 - $base.Length - 1
        if ($padding -lt 1) {
            Set-ItResult -Skipped -Because "the test drive path is too long to build a 174-character run folder: $base"
            return
        }
        $run = Join-Path $base ('r' * $padding)
        [void][System.IO.Directory]::CreateDirectory($run)
        $source = Join-Path $run 'original-0.bin'
        [System.IO.File]::WriteAllText($source, 'synthetic original bytes')
        $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash

        $backup = New-ManagerUpdateBackup -Path $source

        $backup.Length | Should -BeLessOrEqual 259
        Split-Path -Parent (Split-Path -Parent $backup) | Should -Be (Join-Path $run 'UpdateBackups')
        (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash | Should -Be $sourceHash
    }

    It 'resolves a relative path against the PowerShell location' {
        $dir = New-Fix16aDir -Prefix 'b'
        $source = Join-Path $dir 'TeknoParrot-Manager.ps1'
        [System.IO.File]::WriteAllText($source, '$ScriptVersion = "2.0"')
        $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash

        Push-Location -LiteralPath $dir
        try {
            $backup = New-ManagerUpdateBackup -Path 'TeknoParrot-Manager.ps1'
        } finally {
            Pop-Location
        }

        Split-Path -Parent (Split-Path -Parent $backup) | Should -Be (Join-Path $dir 'UpdateBackups')
        Split-Path -Leaf $backup | Should -Be 'TeknoParrot-Manager.ps1'
        (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash | Should -Be $sourceHash
    }
}

Describe 'Test-ManagerUpdatePackageIsSingleScript (ASTRA-04)' {
    It 'accepts a ZIP whose only file is the root TeknoParrot-Manager.ps1' {
        $zip = Join-Path (New-Fix16aDir -Prefix 'z') 'p.zip'
        New-Fix16aZip -Path $zip -Entries @('TeknoParrot-Manager.ps1')

        $result = Test-ManagerUpdatePackageIsSingleScript -ZipPath $zip

        $result.SingleScript | Should -BeTrue
        $result.ExtraEntryCount | Should -Be 0
    }

    It 'rejects a ZIP that also ships a module and reports it' {
        $zip = Join-Path (New-Fix16aDir -Prefix 'z') 'p.zip'
        New-Fix16aZip -Path $zip -Entries @('TeknoParrot-Manager.ps1', 'scripts/TpmRequiredPatchEngine.ps1')

        $result = Test-ManagerUpdatePackageIsSingleScript -ZipPath $zip

        $result.SingleScript | Should -BeFalse
        $result.ExtraEntryCount | Should -Be 1
        (@($result.ExtraEntrySample) -join '|') | Should -Be 'scripts/TpmRequiredPatchEngine.ps1'
    }

    It 'ignores directory entries' {
        $zip = Join-Path (New-Fix16aDir -Prefix 'z') 'p.zip'
        New-Fix16aZip -Path $zip -Entries @('scripts/', 'TeknoParrot-Manager.ps1', 'tools/')

        $result = Test-ManagerUpdatePackageIsSingleScript -ZipPath $zip

        $result.SingleScript | Should -BeTrue
        $result.ExtraEntryCount | Should -Be 0
    }

    It 'counts a nested TeknoParrot-Manager.ps1 as an extra entry' {
        $zip = Join-Path (New-Fix16aDir -Prefix 'z') 'p.zip'
        New-Fix16aZip -Path $zip -Entries @('x/TeknoParrot-Manager.ps1')

        $result = Test-ManagerUpdatePackageIsSingleScript -ZipPath $zip

        $result.SingleScript | Should -BeFalse
        $result.ExtraEntryCount | Should -Be 1
        (@($result.ExtraEntrySample) -join '|') | Should -Be 'x/TeknoParrot-Manager.ps1'
    }

    It 'matches the script name case-sensitively' {
        $zip = Join-Path (New-Fix16aDir -Prefix 'z') 'p.zip'
        New-Fix16aZip -Path $zip -Entries @('teknoparrot-manager.ps1')

        $result = Test-ManagerUpdatePackageIsSingleScript -ZipPath $zip

        $result.SingleScript | Should -BeFalse
        $result.ExtraEntryCount | Should -Be 1
    }

    It 'rejects a ZIP that has no TeknoParrot-Manager.ps1 at all' -TestCases @(
        @{ Name = 'an empty ZIP'; Entries = @() }
        @{ Name = 'a ZIP with only a folder'; Entries = @('scripts/') }
    ) {
        $zip = Join-Path (New-Fix16aDir -Prefix 'z') 'p.zip'
        New-Fix16aZip -Path $zip -Entries $Entries

        $result = Test-ManagerUpdatePackageIsSingleScript -ZipPath $zip

        $result.SingleScript | Should -BeFalse -Because $Name
        $result.ExtraEntryCount | Should -Be 0
    }

    It 'caps the extra-entry sample at five while counting all extras' {
        $zip = Join-Path (New-Fix16aDir -Prefix 'z') 'p.zip'
        New-Fix16aZip -Path $zip -Entries @('TeknoParrot-Manager.ps1', 'e1.ps1', 'e2.ps1', 'e3.ps1', 'e4.ps1', 'e5.ps1', 'e6.ps1', 'e7.ps1')

        $result = Test-ManagerUpdatePackageIsSingleScript -ZipPath $zip

        $result.SingleScript | Should -BeFalse
        $result.ExtraEntryCount | Should -Be 7
        (@($result.ExtraEntrySample) -join '|') | Should -Be 'e1.ps1|e2.ps1|e3.ps1|e4.ps1|e5.ps1'
    }

    It 'throws when the ZIP file is missing' {
        $zip = Join-Path (New-Fix16aDir -Prefix 'z') 'absent.zip'

        { Test-ManagerUpdatePackageIsSingleScript -ZipPath $zip } | Should -Throw '*not found*'
    }
}

Describe 'PostgreSQL leftover inventory is read-only (ASTRA-01)' {
    BeforeEach {
        $script:PostgresInstallDir = 'C:\TPM-Test\PostgreSQL\8.3'
        $script:PostgresServiceName = 'TPMTestPostgres'
        $script:fix16aPgProfileList = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
        $script:fix16aHostLines = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { [void]$script:fix16aHostLines.Add([string]$Object) }
        Mock Start-Process {}
        Mock Remove-Item {}
        Mock Remove-ItemProperty {}
        Mock Remove-LocalUser {}
        Mock Stop-Service {}
    }

    Context 'with PostgreSQL 8.3 leftovers present' {
        BeforeEach {
            Mock Get-ItemProperty {
                param($Path, $Name, $ErrorAction)
                if ($Name -eq 'ProfileImagePath') {
                    if ($Path -eq 'HKLM:\ProfileList\S-1-5-PG') { return [pscustomobject]@{ ProfileImagePath = 'C:\Users\postgres' } }
                    return [pscustomobject]@{ ProfileImagePath = 'C:\Users\Someone' }
                }
                $joined = @($Path) -join ';'
                if ($joined -like '*\PostgreSQL\Installations\*') {
                    return [pscustomobject]@{ 'Base Directory' = 'C:\TPM-Test\PostgreSQL\8.3\' }
                }
                return @(
                    [pscustomobject]@{ DisplayName = 'PostgreSQL 8.3'; InstallLocation = 'C:\TPM-Test\PostgreSQL\8.3' },
                    [pscustomobject]@{ DisplayName = 'Unrelated Tool 2.0'; InstallLocation = 'D:\Tools' }
                )
            }
            Mock Get-ChildItem {
                param($Path, $ErrorAction)
                if ($Path -eq $script:fix16aPgProfileList) {
                    return @(
                        [pscustomobject]@{ PSPath = 'HKLM:\ProfileList\S-1-5-PG'; PSChildName = 'S-1-5-PG' },
                        [pscustomobject]@{ PSPath = 'HKLM:\ProfileList\S-1-5-OTHER'; PSChildName = 'S-1-5-OTHER' }
                    )
                }
            }
            Mock Get-Service { [pscustomobject]@{ Name = 'TPMTestPostgres'; Status = 'Stopped' } }
            Mock Get-LocalUser { [pscustomobject]@{ Name = 'postgres'; SID = 'S-1-5-21-1-2-3-1001' } }
            Mock Test-Path {
                param($LiteralPath)
                $LiteralPath -eq $script:PostgresInstallDir
            }
        }

        It 'lists every kind of leftover and removes, stops, or uninstalls nothing' {
            $inventory = Get-PostgresPartialInstallInventory

            $inventory.Found | Should -BeTrue
            $kinds = @($inventory.Objects | ForEach-Object { [string]$_.Kind } | Sort-Object)
            ($kinds -join '|') | Should -Be 'Folder|InstallationRegistration|InstalledProgram|Service|UserProfile|WindowsAccount'
            $descriptions = @($inventory.Objects | ForEach-Object { [string]$_.Description })
            $descriptions | Should -Contain "Installed program 'PostgreSQL 8.3' (C:\TPM-Test\PostgreSQL\8.3)"
            $descriptions | Should -Contain "Windows service 'TPMTestPostgres' (Stopped)"
            $descriptions | Should -Contain "Folder 'C:\TPM-Test\PostgreSQL\8.3'"
            $descriptions | Should -Contain "Windows account 'postgres' (SID S-1-5-21-1-2-3-1001)"
            $descriptions | Should -Contain "User profile 'C:\Users\postgres' (registered as S-1-5-PG)"
            # FIX128: every object also carries a plain description for the screen (no registry path, account SID or service name); the
            # technical Description above goes to the log. Mutation: leave PlainDescription off an object, or copy Description into it.
            $plain = @($inventory.Objects | ForEach-Object { [string]$_.PlainDescription })
            @($plain | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count | Should -Be 0
            $plain | Should -Contain "The PostgreSQL program 'PostgreSQL 8.3' (C:\TPM-Test\PostgreSQL\8.3)"
            $plain | Should -Contain 'A PostgreSQL entry in the Windows settings'
            $plain | Should -Contain 'The PostgreSQL background service (it is Stopped)'
            $plain | Should -Contain "The PostgreSQL folder 'C:\TPM-Test\PostgreSQL\8.3'"
            $plain | Should -Contain "The Windows user account named 'postgres'"
            $plain | Should -Contain "The Windows profile folder 'C:\Users\postgres' of the 'postgres' user"
            @($plain | Where-Object { $_ -match 'HKLM|S-1-5|SID|TPMTestPostgres' }).Count | Should -Be 0
            @($descriptions | Where-Object { $_ -like '*Unrelated Tool*' -or $_ -like '*Someone*' }).Count | Should -Be 0
            Should -Invoke Start-Process -Times 0 -Exactly
            Should -Invoke Remove-Item -Times 0 -Exactly
            Should -Invoke Remove-ItemProperty -Times 0 -Exactly
            Should -Invoke Remove-LocalUser -Times 0 -Exactly
            Should -Invoke Stop-Service -Times 0 -Exactly
        }

        It 'Install-Postgres83 refuses before prompting, downloading, or installing' {
            Mock Test-RunningAsAdministrator { $true }
            Mock Read-ConfirmedPostgresPassword { 'pw' }
            Mock Get-PostgresGuideRelease { $null }
            Mock Invoke-PostgresMsiPackage { $true }
            Mock Write-Log {}

            $result = Install-Postgres83

            $result | Should -BeFalse
            Should -Invoke Read-ConfirmedPostgresPassword -Times 0 -Exactly
            Should -Invoke Get-PostgresGuideRelease -Times 0 -Exactly
            Should -Invoke Invoke-PostgresMsiPackage -Times 0 -Exactly
            Should -Invoke Start-Process -Times 0 -Exactly
            Should -Invoke Remove-Item -Times 0 -Exactly
            Should -Invoke Remove-LocalUser -Times 0 -Exactly
            Should -Invoke Stop-Service -Times 0 -Exactly
            $script:fix16aHostLines | Should -Contain '  PostgreSQL setup stopped before installing anything.'
            # FIX128: the screen lists the plain description; the SID is in the log (see the S8 tests in Fix128.PostgresFailureScreens.Tests.ps1).
            $script:fix16aHostLines | Should -Contain "    - The Windows user account named 'postgres'"
            $script:fix16aHostLines | Should -Not -Contain "    - Windows account 'postgres' (SID S-1-5-21-1-2-3-1001)"
            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $msg -like '*refused*nothing removed*' }
        }
    }

    Context 'with nothing present' {
        BeforeEach {
            Mock Get-ItemProperty { @() }
            Mock Get-ChildItem { @() }
            Mock Get-Service { @() }
            Mock Get-LocalUser { $null }
            Mock Test-Path { $false }
        }

        It 'reports no leftovers' {
            $inventory = Get-PostgresPartialInstallInventory

            $inventory.Found | Should -BeFalse
            @($inventory.Objects).Count | Should -Be 0
            Should -Invoke Remove-Item -Times 0 -Exactly
            Should -Invoke Stop-Service -Times 0 -Exactly
        }
    }
}
