#Requires -Module Pester

# Issue #349: CPS3 Supplementary (TeknoCPS cache/NVRAM) installer.
# Every fixture here is synthetic (disposable TestDrive folders, tiny byte
# arrays, hand-built manifests). No real game data is read or committed.
# The one optional real-data test (the last Describe) is fixture-only by
# default: it runs only when the tester opts in for that run with its own
# TPM_REAL_SOURCE_TESTS=1 AND sets TPM_CPS3_REAL_SOURCE to a folder or .zip
# they already own (Tests\TpmRealDataOptIn.ps1 decides; TPM_REAL_DATA_TESTS=1 is not enough). A TPM_CPS3_REAL_SOURCE
# that is merely inherited from the environment never starts it. The test
# only reads the source, installs into a disposable TestDrive TeknoParrot
# folder, and fails if the source was added to, removed from or rewritten.
#
# Contract under test: the WHOLE source (installable files, README and the
# held-back member) must match the manifest exactly or nothing is written.
#
# The production script is not a module, so BeforeAll parses it with the AST
# and dot-sources only its function definitions (same pattern as the main suite).

BeforeDiscovery {
    . (Join-Path $PSScriptRoot 'TpmRealDataOptIn.ps1')
    $script:Cps3RealSource = Get-TpmRealDataSource -VariableName 'TPM_CPS3_REAL_SOURCE'
}

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw "Failed to parse TeknoParrot-Manager.ps1: $($parseErrors -join '; ')" }
    $functionAsts = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $extractedFunctionsPath = Join-Path $TestDrive ("tpm-cps3-functions-{0}.ps1" -f ([guid]::NewGuid().ToString('N')))
    ($functionAsts | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $extractedFunctionsPath -Encoding utf8
    . $extractedFunctionsPath
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    . (Join-Path $PSScriptRoot 'TpmRealDataOptIn.ps1')

    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false
    $script:logPath = Join-Path $TestDrive 'cps3-tests.log'
    $script:logWarnShown = $false

    # A plain function (not a Mock) keeps real dynamic scoping: the offer's action
    # block reads caller locals, exactly as it does under the production group runner.
    function Invoke-TpmProgressGroup {
        param([Parameter(Mandatory)][string]$Title, [Parameter(Mandatory)][scriptblock]$Action)
        & $Action
    }

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    function New-Cps3Bytes {
        param([int]$Length, [int]$Seed)
        $bytes = New-Object byte[] $Length
        for ($i = 0; $i -lt $Length; $i++) { $bytes[$i] = [byte](($i * 7 + $Seed) % 251) }
        return , $bytes
    }

    function New-Cps3Entry {
        param([string]$Kind, [string]$Name, [byte[]]$Bytes)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { $hash = (-join ($sha.ComputeHash($Bytes) | ForEach-Object { $_.ToString('X2') })) } finally { $sha.Dispose() }
        $folder = 'cps3-install'
        if ($Kind -eq 'nvram') { $folder = 'nvram' } elseif ($Kind -eq 'readme') { $folder = '' }
        $relative = if ($folder) { 'TeknoCPS/{0}/{1}' -f $folder, $Name } else { $Name }
        return [pscustomobject]@{
            Kind = $Kind; Name = $Name; Length = [int64]$Bytes.Length; Sha256 = $hash
            Folder = $folder; RelativePath = $relative
        }
    }

    # Manifest order is the install order: aaaa(0000) bbbb(0001) game1(0002) game2(0003).
    # README and hold are validated but never installed.
    $script:cps3Bytes = [ordered]@{
        'aaaa.simms' = (New-Cps3Bytes -Length 3000 -Seed 11)
        'bbbb.simms' = (New-Cps3Bytes -Length 2000 -Seed 23)
        'game1.nv'   = (New-Cps3Bytes -Length 128 -Seed 5)
        'game2.nv'   = (New-Cps3Bytes -Length 128 -Seed 9)
        'README.txt' = (New-Cps3Bytes -Length 88 -Seed 3)
        'held.simms' = (New-Cps3Bytes -Length 1500 -Seed 31)
    }
    $script:cps3Entries = @(
        (New-Cps3Entry -Kind 'cache' -Name 'aaaa.simms' -Bytes $script:cps3Bytes['aaaa.simms']),
        (New-Cps3Entry -Kind 'cache' -Name 'bbbb.simms' -Bytes $script:cps3Bytes['bbbb.simms']),
        (New-Cps3Entry -Kind 'nvram' -Name 'game1.nv' -Bytes $script:cps3Bytes['game1.nv']),
        (New-Cps3Entry -Kind 'nvram' -Name 'game2.nv' -Bytes $script:cps3Bytes['game2.nv']),
        (New-Cps3Entry -Kind 'readme' -Name 'README.txt' -Bytes $script:cps3Bytes['README.txt']),
        (New-Cps3Entry -Kind 'hold' -Name 'held.simms' -Bytes $script:cps3Bytes['held.simms'])
    )
    $script:cps3Installable = @('aaaa.simms', 'bbbb.simms', 'game1.nv', 'game2.nv')

    function New-Cps3Fixture {
        param([string]$Name)
        $root = Join-Path $TestDrive $Name
        $tp = Join-Path $root 'tp'
        $src = Join-Path $root 'src'
        New-Item -ItemType Directory -Path $tp, $src -Force | Out-Null
        return [pscustomobject]@{ Root = $root; Tp = $tp; Src = $src }
    }

    # Writes the full synthetic set under $Src; -Omit skips names, -Override replaces bytes.
    function Write-Cps3SourceFolder {
        param([string]$Src, [hashtable]$Override = @{}, [string[]]$Omit = @())
        foreach ($entry in $script:cps3Entries) {
            if ($Omit -contains $entry.Name) { continue }
            $target = Join-Path $Src ($entry.RelativePath.Replace('/', '\'))
            New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($target)) -Force | Out-Null
            $bytes = if ($Override.ContainsKey($entry.Name)) { $Override[$entry.Name] } else { $script:cps3Bytes[$entry.Name] }
            [System.IO.File]::WriteAllBytes($target, $bytes)
        }
    }

    function New-Cps3Zip {
        param([string]$Path, [object[]]$Members)
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew)
        $archive = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($member in $Members) {
                $zipEntry = $archive.CreateEntry([string]$member.Name)
                $entryStream = $zipEntry.Open()
                try { $entryStream.Write($member.Bytes, 0, $member.Bytes.Length) } finally { $entryStream.Dispose() }
            }
        } finally { $archive.Dispose(); $stream.Dispose() }
    }

    function Get-Cps3ZipMembers {
        param([string[]]$Omit = @())
        $members = @()
        foreach ($entry in $script:cps3Entries) {
            if ($Omit -contains $entry.Name) { continue }
            $members += , @{ Name = $entry.RelativePath; Bytes = $script:cps3Bytes[$entry.Name] }
        }
        return $members
    }

    function Get-Cps3Dest {
        param($Fixture, $Entry)
        return (Join-Path $Fixture.Tp ('TeknoCPS\' + $Entry.Folder + '\' + $Entry.Name))
    }

    function Get-Cps3Tree {
        param([string]$Root)
        if (-not (Test-Path -LiteralPath $Root)) { return @() }
        return @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Sort-Object FullName | ForEach-Object {
            '{0}|{1}' -f $_.FullName.Substring($Root.Length), (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        })
    }

    function Assert-Cps3Installed {
        param($Fixture, [string[]]$Names)
        foreach ($entry in $script:cps3Entries) {
            if ($Names -notcontains $entry.Name) { continue }
            (Get-FileHash -LiteralPath (Get-Cps3Dest $Fixture $entry) -Algorithm SHA256).Hash | Should -Be $entry.Sha256
        }
    }

    function Assert-Cps3Refused {
        param($Result, $Fixture)
        $Result.Outcome | Should -Be 'FAILED_BEFORE_MUTATION'
        $Result.ReasonCode | Should -Be 'SOURCE_INVENTORY_INVALID'
        @($Result.Installed).Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $Fixture.Tp -Force).Count | Should -Be 0
    }
}

Describe 'CPS3 supplementary manifest' {
    It 'pins the full 103-member set: 18 documented caches, 83 NVRAM files, README, and the held-back undocumented cache' {
        $manifest = @(Get-TpmCps3SupplementaryManifest)
        $manifest.Count | Should -Be 103
        @($manifest | Where-Object { $_.Kind -eq 'cache' }).Count | Should -Be 18
        @($manifest | Where-Object { $_.Kind -eq 'nvram' }).Count | Should -Be 83
        @($manifest | Where-Object { $_.Kind -eq 'readme' }).Count | Should -Be 1
        @($manifest | Where-Object { $_.Kind -eq 'hold' }).Count | Should -Be 1
        @($manifest.RelativePath | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object -Unique).Count | Should -Be 103
        foreach ($entry in $manifest) {
            $entry.Sha256 | Should -Match '^[0-9A-F]{64}$'
            $entry.Length | Should -BeGreaterThan 0
            $entry.RelativePath | Should -Not -Match '\.\.|\\'
            if ($entry.Kind -eq 'cache' -or $entry.Kind -eq 'hold') { $entry.Name | Should -Match '^[0-9a-f]{40}\.simms$' }
            elseif ($entry.Kind -eq 'nvram') { $entry.Name | Should -Match '^[0-9a-z]+\.nv$' }
        }
        $readme = @($manifest | Where-Object { $_.Kind -eq 'readme' })[0]
        $readme.RelativePath | Should -Be 'README.txt'
        $readme.Length | Should -Be 388
        @($manifest | Where-Object { $_.Kind -eq 'hold' })[0].Name | Should -Be 'aeeba2be4de91a71890bfb47347c8b4cf217c5aa.simms'
    }
}

Describe 'CPS3 supplementary source resolution' {
    It 'accepts a folder holding TeknoCPS and a .zip; rejects the TeknoCPS folder alone and other locations' {
        $f = New-Cps3Fixture 'resolve'
        Write-Cps3SourceFolder -Src $f.Src
        $root = Resolve-TpmCps3SupplementarySource -Path $f.Src
        $root.Valid | Should -BeTrue
        $root.Kind | Should -Be 'Folder'
        (Resolve-TpmCps3SupplementarySource -Path (Join-Path $f.Src 'TeknoCPS')).Valid | Should -BeFalse
        $zipPath = Join-Path $f.Root 'set.zip'
        New-Cps3Zip -Path $zipPath -Members (Get-Cps3ZipMembers)
        (Resolve-TpmCps3SupplementarySource -Path $zipPath).Kind | Should -Be 'Archive'
        $other = Join-Path $f.Root 'set.7z'
        [System.IO.File]::WriteAllText($other, 'x')
        (Resolve-TpmCps3SupplementarySource -Path $other).Valid | Should -BeFalse
        (Resolve-TpmCps3SupplementarySource -Path (Join-Path $f.Root 'missing')).Valid | Should -BeFalse
        (Resolve-TpmCps3SupplementarySource -Path $f.Root).Valid | Should -BeFalse
        (Resolve-TpmCps3SupplementarySource -Path '').Valid | Should -BeFalse
    }
}

Describe 'CPS3 supplementary member-name safety' {
    It 'flags traversal-like, rooted, backslash, drive and empty-segment names and accepts plain relative names' {
        foreach ($bad in @('../x.simms', 'TeknoCPS/../x.simms', '/x.simms', 'TeknoCPS\nvram\x.nv', 'C:/x.nv', 'TeknoCPS//x.nv', './x.nv', 'TeknoCPS/nvram/x.nv.', '')) {
            (Test-TpmCps3UnsafeMemberName -Name $bad) | Should -BeTrue
        }
        foreach ($good in @('README.txt', 'TeknoCPS/nvram/x.nv', 'TeknoCPS/cps3-install/abc.simms')) {
            (Test-TpmCps3UnsafeMemberName -Name $good) | Should -BeFalse
        }
    }
}

Describe 'CPS3 supplementary install' {
    BeforeEach {
        $script:cps3Progress = New-Object System.Collections.Generic.List[object]
        Mock Write-TpmCompactExtractionProgress {
            [void]$script:cps3Progress.Add([pscustomobject]@{ Label = $Label; Current = $Current; Total = $Total; Complete = [bool]$Complete })
        }
        Mock Write-Log {}
    }

    It 'installs only the installable members from a complete folder; README and the held-back cache are validated but never copied' {
        $f = New-Cps3Fixture 'folder-install'
        Write-Cps3SourceFolder -Src $f.Src
        $r = Invoke-TpmCps3SupplementaryInstall -SourcePath $f.Src -TpRoot $f.Tp -Manifest $script:cps3Entries
        $r.Outcome | Should -Be 'SUCCEEDED'
        $r.Complete | Should -BeTrue
        @($r.Installed | Sort-Object) | Should -Be $script:cps3Installable
        Assert-Cps3Installed -Fixture $f -Names $script:cps3Installable
        @(Get-ChildItem -LiteralPath $f.Tp -Recurse -File -Force | Sort-Object Name | ForEach-Object Name) | Should -Be $script:cps3Installable
        Test-Path -LiteralPath (Join-Path $f.Tp 'TeknoCPS\.tpm-cps3-stage') | Should -BeFalse
        (Get-FileHash -LiteralPath (Join-Path $f.Src 'TeknoCPS\cps3-install\aaaa.simms') -Algorithm SHA256).Hash | Should -Be $script:cps3Entries[0].Sha256
    }

    It 'reports progress against the real counts and closes each bar' {
        $f = New-Cps3Fixture 'progress'
        Write-Cps3SourceFolder -Src $f.Src
        [void](Invoke-TpmCps3SupplementaryInstall -SourcePath $f.Src -TpRoot $f.Tp -Manifest $script:cps3Entries)
        $check = @($script:cps3Progress | Where-Object { $_.Label -eq 'CPS3 file check' })
        $check[-1].Complete | Should -BeTrue
        $check[-1].Current | Should -Be 4
        $check[-1].Total | Should -Be 4
        # A folder source is verified (not extracted); the row is labeled accordingly.
        $verify = @($script:cps3Progress | Where-Object { $_.Label -eq 'CPS3 source verification' })
        $verify.Count | Should -BeGreaterThan 0
        $verify[-1].Complete | Should -BeTrue
        $verify[-1].Current | Should -Be 6
        $verify[-1].Total | Should -Be 6
    }

    It 'installs the same set from a complete .zip' {
        $f = New-Cps3Fixture 'zip-install'
        $zipPath = Join-Path $f.Root 'set.zip'
        New-Cps3Zip -Path $zipPath -Members (Get-Cps3ZipMembers)
        $r = Invoke-TpmCps3SupplementaryInstall -SourcePath $zipPath -TpRoot $f.Tp -Manifest $script:cps3Entries
        $r.Outcome | Should -Be 'SUCCEEDED'
        @($r.Installed | Sort-Object) | Should -Be $script:cps3Installable
        Assert-Cps3Installed -Fixture $f -Names $script:cps3Installable
        @(Get-ChildItem -LiteralPath $f.Tp -Recurse -File -Force | Sort-Object Name | ForEach-Object Name) | Should -Be $script:cps3Installable
        @(Get-ChildItem -LiteralPath (Join-Path $f.Tp 'TeknoCPS') -Force | ForEach-Object Name) | Should -Not -Contain '.tpm-cps3-stage'
    }

    It 'makes no writes on a second run and treats browsing the TeknoParrot folder itself as a no-op' {
        $f = New-Cps3Fixture 'rerun'
        Write-Cps3SourceFolder -Src $f.Src
        [void](Invoke-TpmCps3SupplementaryInstall -SourcePath $f.Src -TpRoot $f.Tp -Manifest $script:cps3Entries)
        $before = Get-Cps3Tree -Root $f.Tp
        $times = @($script:cps3Installable | ForEach-Object { $name = $_; (Get-Item -LiteralPath (Get-Cps3Dest $f ($script:cps3Entries | Where-Object { $_.Name -eq $name })[0])).LastWriteTimeUtc.Ticks })
        $again = Invoke-TpmCps3SupplementaryInstall -SourcePath $f.Src -TpRoot $f.Tp -Manifest $script:cps3Entries
        $again.Outcome | Should -Be 'NO_OP'
        @($again.Installed).Count | Should -Be 0
        @($again.AlreadyPresent).Count | Should -Be 4
        $fromTp = Invoke-TpmCps3SupplementaryInstall -SourcePath $f.Tp -TpRoot $f.Tp -Manifest $script:cps3Entries
        $fromTp.Outcome | Should -Be 'NO_OP'
        (Get-Cps3Tree -Root $f.Tp) | Should -Be $before
        @($script:cps3Installable | ForEach-Object { $name = $_; (Get-Item -LiteralPath (Get-Cps3Dest $f ($script:cps3Entries | Where-Object { $_.Name -eq $name })[0])).LastWriteTimeUtc.Ticks }) | Should -Be $times
    }

    It 'never overwrites an existing different NVRAM file' {
        $f = New-Cps3Fixture 'nv-preserved'
        Write-Cps3SourceFolder -Src $f.Src
        $nvDir = Join-Path $f.Tp 'TeknoCPS\nvram'
        New-Item -ItemType Directory -Path $nvDir -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $nvDir 'game1.nv'), [byte[]](9, 9, 9))
        $r = Invoke-TpmCps3SupplementaryInstall -SourcePath $f.Src -TpRoot $f.Tp -Manifest $script:cps3Entries -ReplaceDifferingCache
        $r.Outcome | Should -Be 'SUCCEEDED'
        @($r.PreservedExisting) | Should -Be @('game1.nv')
        @($r.Installed | Sort-Object) | Should -Be @('aaaa.simms', 'bbbb.simms', 'game2.nv')
        [System.IO.File]::ReadAllBytes((Join-Path $nvDir 'game1.nv')) | Should -Be ([byte[]](9, 9, 9))
    }

    It 'keeps a different existing cache, reports the result as not Complete, and replaces it only when explicitly requested' {
        $f = New-Cps3Fixture 'cache-conflict'
        Write-Cps3SourceFolder -Src $f.Src
        $cacheDir = Join-Path $f.Tp 'TeknoCPS\cps3-install'
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $cacheDir 'bbbb.simms'), [byte[]](1, 2, 3))
        $first = Invoke-TpmCps3SupplementaryInstall -SourcePath $f.Src -TpRoot $f.Tp -Manifest $script:cps3Entries
        $first.Outcome | Should -Be 'SUCCEEDED'
        $first.Complete | Should -BeFalse
        @($first.Conflicts) | Should -Be @('bbbb.simms')
        @($first.Installed | Sort-Object) | Should -Be @('aaaa.simms', 'game1.nv', 'game2.nv')
        [System.IO.File]::ReadAllBytes((Join-Path $cacheDir 'bbbb.simms')) | Should -Be ([byte[]](1, 2, 3))
        $second = Invoke-TpmCps3SupplementaryInstall -SourcePath $f.Src -TpRoot $f.Tp -Manifest $script:cps3Entries -ReplaceDifferingCache
        $second.Outcome | Should -Be 'SUCCEEDED'
        $second.Complete | Should -BeTrue
        @($second.Replaced) | Should -Be @('bbbb.simms')
        @($second.Installed).Count | Should -Be 0
        Assert-Cps3Installed -Fixture $f -Names @('bbbb.simms')
    }

    It 'refuses the whole set and changes nothing when an installable file has the right size but the wrong bytes' {
        $f = New-Cps3Fixture 'bad-hash'
        $flipped = [byte[]]$script:cps3Bytes['aaaa.simms'].Clone()
        $flipped[10] = [byte](($flipped[10] + 1) % 256)
        Write-Cps3SourceFolder -Src $f.Src -Override @{ 'aaaa.simms' = $flipped }
        $r = Invoke-TpmCps3SupplementaryInstall -SourcePath $f.Src -TpRoot $f.Tp -Manifest $script:cps3Entries
        Assert-Cps3Refused -Result $r -Fixture $f
        @($r.Mismatched) | Should -Be @('aaaa.simms')
        $r.Complete | Should -BeFalse
    }

    It 'refuses the whole set when only the README or the held-back cache is wrong' {
        foreach ($name in @('README.txt', 'held.simms')) {
            $f = New-Cps3Fixture ('bad-validate-only-' + $name)
            $flipped = [byte[]]$script:cps3Bytes[$name].Clone()
            $flipped[0] = [byte](($flipped[0] + 1) % 256)
            Write-Cps3SourceFolder -Src $f.Src -Override @{ $name = $flipped }
            $r = Invoke-TpmCps3SupplementaryInstall -SourcePath $f.Src -TpRoot $f.Tp -Manifest $script:cps3Entries
            Assert-Cps3Refused -Result $r -Fixture $f
            @($r.Mismatched) | Should -Be @($name)
        }
    }

    It 'refuses a file of the wrong size before hashing, and leaves existing destination files byte-identical' {
        $f = New-Cps3Fixture 'bad-size'
        Write-Cps3SourceFolder -Src $f.Src -Override @{ 'game1.nv' = [byte[]](1, 2, 3) }
        $nvDir = Join-Path $f.Tp 'TeknoCPS\nvram'
        New-Item -ItemType Directory -Path $nvDir -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $nvDir 'game2.nv'), [byte[]](7, 7))
        $before = Get-Cps3Tree -Root $f.Tp
        $r = Invoke-TpmCps3SupplementaryInstall -SourcePath $f.Src -TpRoot $f.Tp -Manifest $script:cps3Entries
        $r.Outcome | Should -Be 'FAILED_BEFORE_MUTATION'
        $r.ReasonCode | Should -Be 'SOURCE_INVENTORY_INVALID'
        @($r.Mismatched) | Should -Be @('game1.nv')
        (Get-Cps3Tree -Root $f.Tp) | Should -Be $before
    }

    It 'refuses a set with a missing member, including a missing README' {
        foreach ($omit in @('game2.nv', 'README.txt', 'held.simms')) {
            $f = New-Cps3Fixture ('missing-' + $omit)
            Write-Cps3SourceFolder -Src $f.Src -Omit @($omit)
            $r = Invoke-TpmCps3SupplementaryInstall -SourcePath $f.Src -TpRoot $f.Tp -Manifest $script:cps3Entries
            Assert-Cps3Refused -Result $r -Fixture $f
            @($r.Missing) | Should -Be @($omit)
        }
    }

    It 'refuses a folder with any extra member, in TeknoCPS or at the top level' {
        $cases = @(
            @{ Rel = 'TeknoCPS\cps3-install\zzzz.simms'; Expect = 'TeknoCPS/cps3-install/zzzz.simms' },
            @{ Rel = 'TeknoCPS\nvram\extra.sav'; Expect = 'TeknoCPS/nvram/extra.sav' },
            @{ Rel = 'notes.txt'; Expect = 'notes.txt' },
            @{ Rel = 'other\file.bin'; Expect = 'other/' }
        )
        foreach ($case in $cases) {
            $f = New-Cps3Fixture ('extra-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            Write-Cps3SourceFolder -Src $f.Src
            $extra = Join-Path $f.Src $case.Rel
            New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($extra)) -Force | Out-Null
            [System.IO.File]::WriteAllBytes($extra, [byte[]](1, 2, 3))
            $r = Invoke-TpmCps3SupplementaryInstall -SourcePath $f.Src -TpRoot $f.Tp -Manifest $script:cps3Entries
            Assert-Cps3Refused -Result $r -Fixture $f
            @($r.Extra) | Should -Be @($case.Expect)
        }
    }

    It 'reports a folder with none of the files plainly and changes nothing' {
        $f = New-Cps3Fixture 'nothing-found'
        New-Item -ItemType Directory -Path (Join-Path $f.Src 'TeknoCPS\cps3-install') -Force | Out-Null
        $r = Invoke-TpmCps3SupplementaryInstall -SourcePath $f.Src -TpRoot $f.Tp -Manifest $script:cps3Entries
        $r.Outcome | Should -Be 'NO_OP'
        $r.ReasonCode | Should -Be 'SOURCE_HAS_NO_CPS3_FILES'
        @(Get-ChildItem -LiteralPath $f.Tp -Force).Count | Should -Be 0
        $r.Complete | Should -BeFalse
        @($r.Missing).Count | Should -Be 0
    }

    It 'refuses a ZIP with a member name Windows PowerShell 5.1 cannot read, instead of calling it empty' {
        # Who gets hurt: a user with such a ZIP was told "No CPS3 files were found" although the ZIP holds them. Mutation: read .Entries instead of get_Entries().
        $f = New-Cps3Fixture 'illegal-member'
        $zipPath = Join-Path $f.Root 'set.zip'
        # Windows PowerShell 5.1 refuses to create such a name, so the ZIP is written with a legal name and two characters are swapped in the file.
        New-Cps3Zip -Path $zipPath -Members @(@{ Name = 'TeknoCPS/cps3-install/a_b_c.simms'; Bytes = [byte[]](1, 2, 3) })
        $latin1 = [System.Text.Encoding]::GetEncoding(28591)
        [System.IO.File]::WriteAllBytes($zipPath, $latin1.GetBytes($latin1.GetString([System.IO.File]::ReadAllBytes($zipPath)).Replace('a_b_c', 'a<b|c')))
        $r = Invoke-TpmCps3SupplementaryInstall -SourcePath $zipPath -TpRoot $f.Tp -Manifest $script:cps3Entries
        $r.Outcome | Should -Be 'FAILED_BEFORE_MUTATION'
        $r.ReasonCode | Should -Not -Be 'SOURCE_HAS_NO_CPS3_FILES'
        @(Get-ChildItem -LiteralPath $f.Tp -Force).Count | Should -Be 0
    }

    It 'accepts a set zipped by Explorer (one outer folder) and installs it' {
        # Who gets hurt: a user who right-clicked the set folder and chose "Compress to ZIP file" was refused. Mutation: do not strip the one outer folder -> every file reads as missing.
        $f = New-Cps3Fixture 'wrapped-zip'
        $zipPath = Join-Path $f.Root 'set.zip'
        New-Cps3Zip -Path $zipPath -Members @($script:cps3Entries | ForEach-Object { @{ Name = ('MySet/' + $_.RelativePath); Bytes = $script:cps3Bytes[$_.Name] } })
        $r = Invoke-TpmCps3SupplementaryInstall -SourcePath $zipPath -TpRoot $f.Tp -Manifest $script:cps3Entries
        $r.Outcome | Should -Be 'SUCCEEDED'
        Assert-Cps3Installed -Fixture $f -Names $script:cps3Installable
    }

    It 'still refuses two outer folders, and says in one plain sentence that the layout is wrong, with counts and no file names' {
        # Mutation: strip every leading folder, or print the file names on the screen.
        $f = New-Cps3Fixture 'double-wrapped-zip'
        $zipPath = Join-Path $f.Root 'set.zip'
        New-Cps3Zip -Path $zipPath -Members @($script:cps3Entries | ForEach-Object { @{ Name = ('Outer/Inner/' + $_.RelativePath); Bytes = $script:cps3Bytes[$_.Name] } })
        $r = Invoke-TpmCps3SupplementaryInstall -SourcePath $zipPath -TpRoot $f.Tp -Manifest $script:cps3Entries
        Assert-Cps3Refused -Result $r -Fixture $f
        $r.Summary | Should -Match 'extra outer folder'
        $r.Summary | Should -Match '6 expected file\(s\) are missing and 6 other item\(s\)'
        $r.Summary | Should -Match 'Nothing was changed\.$'
        $r.Summary | Should -Not -MatchExactly 'aaaa\.simms|Outer|Inner'
    }

    It 'says plainly that files are missing when a wrapped set lacks one' {
        # Mutation: keep the old "not the complete expected file set" wording with no hint of what is wrong.
        $f = New-Cps3Fixture 'wrapped-missing'
        $zipPath = Join-Path $f.Root 'set.zip'
        New-Cps3Zip -Path $zipPath -Members @($script:cps3Entries | Where-Object { $_.Name -ne 'game2.nv' } | ForEach-Object { @{ Name = ('MySet/' + $_.RelativePath); Bytes = $script:cps3Bytes[$_.Name] } })
        $r = Invoke-TpmCps3SupplementaryInstall -SourcePath $zipPath -TpRoot $f.Tp -Manifest $script:cps3Entries
        Assert-Cps3Refused -Result $r -Fixture $f
        $r.Summary | Should -Match '^The set is not complete or has files that do not belong \(1 expected file\(s\) missing\)\. Nothing was changed\.$'
    }

    It 'refuses unusable sources before touching the TeknoParrot folder' {
        $f = New-Cps3Fixture 'unusable'
        $badZip = Join-Path $f.Root 'bad.zip'
        [System.IO.File]::WriteAllText($badZip, 'this is not a zip archive')
        foreach ($case in @(
            @{ Path = (Join-Path $f.Root 'missing'); Reason = 'SOURCE_UNUSABLE' },
            @{ Path = $f.Root; Reason = 'SOURCE_UNUSABLE' },
            @{ Path = $badZip; Reason = 'ARCHIVE_UNREADABLE' }
        )) {
            $r = Invoke-TpmCps3SupplementaryInstall -SourcePath $case.Path -TpRoot $f.Tp -Manifest $script:cps3Entries
            $r.Outcome | Should -Be 'FAILED_BEFORE_MUTATION'
            $r.ReasonCode | Should -Be $case.Reason
            @(Get-ChildItem -LiteralPath $f.Tp -Force).Count | Should -Be 0
        }
        $missingTp = Invoke-TpmCps3SupplementaryInstall -SourcePath $f.Src -TpRoot (Join-Path $f.Root 'no-such-tp') -Manifest $script:cps3Entries
        $missingTp.Outcome | Should -Be 'FAILED_BEFORE_MUTATION'
        $missingTp.ReasonCode | Should -Be 'TP_ROOT_INVALID'
    }

    It 'refuses a .zip with a missing, extra, or wrong-hash member and writes nothing' {
        $flipped = [byte[]]$script:cps3Bytes['bbbb.simms'].Clone()
        $flipped[5] = [byte](($flipped[5] + 1) % 256)
        $cases = @(
            @{ Name = 'missing'; Members = (Get-Cps3ZipMembers -Omit @('README.txt')) },
            @{ Name = 'extra'; Members = @((Get-Cps3ZipMembers) + , @{ Name = 'TeknoCPS/cps3-install/zzzz.simms'; Bytes = [byte[]](1, 2, 3) }) },
            @{ Name = 'hash'; Members = @(@((Get-Cps3ZipMembers) | Where-Object { $_.Name -ne 'TeknoCPS/cps3-install/bbbb.simms' }) + , @{ Name = 'TeknoCPS/cps3-install/bbbb.simms'; Bytes = $flipped }) }
        )
        foreach ($case in $cases) {
            $f = New-Cps3Fixture ('zip-refused-' + $case.Name)
            $zipPath = Join-Path $f.Root 'set.zip'
            New-Cps3Zip -Path $zipPath -Members $case.Members
            $r = Invoke-TpmCps3SupplementaryInstall -SourcePath $zipPath -TpRoot $f.Tp -Manifest $script:cps3Entries
            Assert-Cps3Refused -Result $r -Fixture $f
        }
    }

    It 'refuses duplicate or case-colliding archive members' {
        $f = New-Cps3Fixture 'zip-duplicate'
        $members = @(Get-Cps3ZipMembers)
        $members += , @{ Name = 'teknocps/cps3-install/AAAA.SIMMS'; Bytes = [byte[]](1, 2, 3) }
        $zipPath = Join-Path $f.Root 'dup.zip'
        New-Cps3Zip -Path $zipPath -Members $members
        $r = Invoke-TpmCps3SupplementaryInstall -SourcePath $zipPath -TpRoot $f.Tp -Manifest $script:cps3Entries
        Assert-Cps3Refused -Result $r -Fixture $f
        @($r.Ambiguous) | Should -Be @('aaaa.simms')
        $r.Complete | Should -BeFalse
    }

    It 'refuses traversal-style archive member names and never writes outside the TeknoParrot folder' {
        $f = New-Cps3Fixture 'zip-traversal'
        $members = @(Get-Cps3ZipMembers)
        $members += , @{ Name = '../evil.simms'; Bytes = [byte[]](1, 2, 3) }
        $members += , @{ Name = 'TeknoCPS/cps3-install/../../evil.simms'; Bytes = [byte[]](1, 2, 3) }
        $members += , @{ Name = '..\evil2.simms'; Bytes = [byte[]](1, 2, 3) }
        $zipPath = Join-Path $f.Root 'traversal.zip'
        New-Cps3Zip -Path $zipPath -Members $members
        $r = Invoke-TpmCps3SupplementaryInstall -SourcePath $zipPath -TpRoot $f.Tp -Manifest $script:cps3Entries
        Assert-Cps3Refused -Result $r -Fixture $f
        @($r.Unsafe).Count | Should -Be 3
        @(Get-ChildItem -LiteralPath $f.Root -Recurse -File -Force | Where-Object { $_.Name -like 'evil*' }).Count | Should -Be 0
    }

    It 'fails before any change when free space is insufficient' {
        $f = New-Cps3Fixture 'no-space'
        Write-Cps3SourceFolder -Src $f.Src
        Mock Get-TpmCps3FreeBytes { [int64]1 }
        $r = Invoke-TpmCps3SupplementaryInstall -SourcePath $f.Src -TpRoot $f.Tp -Manifest $script:cps3Entries
        $r.Outcome | Should -Be 'FAILED_BEFORE_MUTATION'
        $r.ReasonCode | Should -Be 'INSUFFICIENT_SPACE'
        @(Get-ChildItem -LiteralPath $f.Tp -Force).Count | Should -Be 0
    }

    It 'rolls back every promoted file, never claims success, and keeps existing NVRAM when a later promotion fails' {
        $f = New-Cps3Fixture 'promotion-failure'
        Write-Cps3SourceFolder -Src $f.Src
        $nvDir = Join-Path $f.Tp 'TeknoCPS\nvram'
        New-Item -ItemType Directory -Path $nvDir -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $nvDir 'game1.nv'), [byte[]](9, 9, 9))
        Mock Move-Item {
            param($LiteralPath, $Destination)
            if ($LiteralPath -like '*0001.payload') { throw 'simulated second promotion failure' }
            [System.IO.File]::Move($LiteralPath, $Destination)
        }
        $r = Invoke-TpmCps3SupplementaryInstall -SourcePath $f.Src -TpRoot $f.Tp -Manifest $script:cps3Entries
        $r.Outcome | Should -Be 'ROLLED_BACK_VERIFIED'
        $r.Complete | Should -BeFalse
        @($r.Installed).Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $f.Tp -Recurse -File -Force | ForEach-Object Name) | Should -Be @('game1.nv')
        [System.IO.File]::ReadAllBytes((Join-Path $nvDir 'game1.nv')) | Should -Be ([byte[]](9, 9, 9))
    }

    It 'never overwrites or removes a file created at the target after the boundary check, and never reports success' {
        foreach ($case in @(
            @{ Name = 'game2.nv'; Outcome = 'ROLLED_BACK_VERIFIED' },
            @{ Name = 'aaaa.simms'; Outcome = 'FAILED_BEFORE_MUTATION' }
        )) {
            $f = New-Cps3Fixture ('race-' + $case.Name)
            Write-Cps3SourceFolder -Src $f.Src
            $entry = @($script:cps3Entries | Where-Object { $_.Name -eq $case.Name })[0]
            $script:cps3RaceTarget = Get-Cps3Dest $f $entry
            $script:cps3RaceBytes = [byte[]](42, 42, 42, 42)
            # The competing writer creates the target after the boundary check, right before TPM promotes into it.
            Mock Assert-TpmNoReparseWriteTarget {
                if ([System.IO.Path]::GetFullPath($Path) -ieq [System.IO.Path]::GetFullPath($script:cps3RaceTarget) -and -not (Test-Path -LiteralPath $script:cps3RaceTarget)) {
                    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($script:cps3RaceTarget))
                    [System.IO.File]::WriteAllBytes($script:cps3RaceTarget, $script:cps3RaceBytes)
                }
            }
            $r = Invoke-TpmCps3SupplementaryInstall -SourcePath $f.Src -TpRoot $f.Tp -Manifest $script:cps3Entries
            $r.Outcome | Should -Be $case.Outcome
            $r.Outcome | Should -Not -Be 'SUCCEEDED'
            $r.Complete | Should -BeFalse
            @($r.Installed).Count | Should -Be 0
            [System.IO.File]::ReadAllBytes($script:cps3RaceTarget) | Should -Be $script:cps3RaceBytes
            @(Get-ChildItem -LiteralPath $f.Tp -Recurse -File -Force | ForEach-Object Name) | Should -Be @($case.Name)
            @($r.Transaction.Warnings).Count | Should -Be 1
        }
    }
}

Describe 'Shared file transaction ADD promotion safety' {
    BeforeEach {
        Mock Write-TpmCompactExtractionProgress {}
        Mock Write-Log {}
    }

    It 'does not remove a promoted file that a competing writer replaced with identical bytes before rollback' {
        $root = Join-Path $TestDrive ('batch-proof-' + [guid]::NewGuid().ToString('N'))
        $srcDir = Join-Path $root 'src'
        $dstDir = Join-Path $root 'dst'
        New-Item -ItemType Directory -Path $srcDir, $dstDir -Force | Out-Null
        $bytes = [byte[]](1, 2, 3, 4, 5)
        $source = Join-Path $srcDir 'a.bin'
        [System.IO.File]::WriteAllBytes($source, $bytes)
        $hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        $script:batchProofDest = Join-Path $dstDir 'a.bin'
        $script:batchProofBytes = $bytes
        $op = [pscustomobject]@{ ItemId = 'a.bin'; Operation = 'ADD'; SourcePath = $source; DestinationPath = $script:batchProofDest; RootPath = $root; ExpectedSourceHash = $hash; ExpectedFinalHash = $hash }
        # After TPM promoted the file, a competing writer replaces it with the same bytes (new identity), then the transaction fails and rolls back.
        $commit = {
            [System.IO.File]::WriteAllBytes($script:batchProofDest, $script:batchProofBytes)
            [System.IO.File]::SetLastWriteTimeUtc($script:batchProofDest, [datetime]::UtcNow.AddHours(5))
            throw 'simulated commit failure'
        }
        $r = Invoke-TpmTransactionalFileBatch -WorkflowKey 'Cps3Supplementary' -OperationKey 'ProofTest' -Operations @($op) -StagingDir (Join-Path $root 'stage') -CommitAction $commit
        $r.Outcome | Should -Be 'ACTION_REQUIRED'
        @($r.Rollback.FailedItems) | Should -Be @('a.bin')
        Test-Path -LiteralPath $script:batchProofDest | Should -BeTrue
        [System.IO.File]::ReadAllBytes($script:batchProofDest) | Should -Be $bytes
    }
}

Describe 'CPS3 supplementary optional offer' {
    BeforeEach {
        Mock Write-TpmCompactExtractionProgress {}
        Mock Write-Log {}
        Mock Write-Host {}
        Mock Read-TpmYesNo { 'N' }
        Mock Read-TpmChoice { 'F' }
        Mock Read-PathWithBrowse { $script:cps3OfferSource }
        Mock Get-TpmCps3SupplementaryManifest { $script:cps3Entries }
    }

    It 'asks nothing when no CPS3 profile is registered' {
        $f = New-Cps3Fixture 'offer-none'
        $profiles = Join-Path $f.Root 'UserProfiles'
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $profiles 'OtherGame.xml'), '<GameProfile />')
        (Invoke-TpmCps3SupplementaryOffer -TpRoot $f.Tp -UserProfilesDir $profiles) | Should -BeNullOrEmpty
        Should -Invoke Read-TpmYesNo -Times 0 -Exactly
    }

    It 'changes nothing and never opens a browser when the user declines' {
        $f = New-Cps3Fixture 'offer-decline'
        $profiles = Join-Path $f.Root 'UserProfiles'
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $profiles 'cps_sfiii3.xml'), '<GameProfile />')
        (Invoke-TpmCps3SupplementaryOffer -TpRoot $f.Tp -UserProfilesDir $profiles) | Should -BeNullOrEmpty
        Should -Invoke Read-TpmYesNo -Times 1 -Exactly
        Should -Invoke Read-PathWithBrowse -Times 0 -Exactly
        @(Get-ChildItem -LiteralPath $f.Tp -Force).Count | Should -Be 0
    }

    It 'installs from the chosen folder after the user accepts' {
        $f = New-Cps3Fixture 'offer-accept'
        $profiles = Join-Path $f.Root 'UserProfiles'
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $profiles 'cps_jojo.xml'), '<GameProfile />')
        Write-Cps3SourceFolder -Src $f.Src
        $script:cps3OfferSource = $f.Src
        Mock Read-TpmYesNo { 'Y' }
        $r = Invoke-TpmCps3SupplementaryOffer -TpRoot $f.Tp -UserProfilesDir $profiles
        $r.Outcome | Should -Be 'SUCCEEDED'
        Assert-Cps3Installed -Fixture $f -Names $script:cps3Installable
    }

    It 'refuses an incomplete chosen folder and changes nothing' {
        $f = New-Cps3Fixture 'offer-incomplete'
        $profiles = Join-Path $f.Root 'UserProfiles'
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $profiles 'cps_jojo.xml'), '<GameProfile />')
        Write-Cps3SourceFolder -Src $f.Src -Omit @('game2.nv')
        $script:cps3OfferSource = $f.Src
        Mock Read-TpmYesNo { 'Y' }
        $r = Invoke-TpmCps3SupplementaryOffer -TpRoot $f.Tp -UserProfilesDir $profiles
        Assert-Cps3Refused -Result $r -Fixture $f
    }

    It 'replaces a differing cache only after a second explicit confirmation' {
        foreach ($case in @(@{ Answer = 'N'; Replaced = $false }, @{ Answer = 'Y'; Replaced = $true })) {
            $f = New-Cps3Fixture ('offer-conflict-' + $case.Answer)
            $profiles = Join-Path $f.Root 'UserProfiles'
            New-Item -ItemType Directory -Path $profiles -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $profiles 'cps_redearth.xml'), '<GameProfile />')
            Write-Cps3SourceFolder -Src $f.Src
            $cacheDir = Join-Path $f.Tp 'TeknoCPS\cps3-install'
            New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
            [System.IO.File]::WriteAllBytes((Join-Path $cacheDir 'bbbb.simms'), [byte[]](1, 2, 3))
            $script:cps3OfferSource = $f.Src
            $script:cps3Answers = New-Object System.Collections.Generic.Queue[string]
            foreach ($a in @('Y', $case.Answer)) { $script:cps3Answers.Enqueue($a) }
            Mock Read-TpmYesNo { $script:cps3Answers.Dequeue() }
            [void](Invoke-TpmCps3SupplementaryOffer -TpRoot $f.Tp -UserProfilesDir $profiles)
            if ($case.Replaced) {
                (Get-FileHash -LiteralPath (Join-Path $cacheDir 'bbbb.simms') -Algorithm SHA256).Hash | Should -Be $script:cps3Entries[1].Sha256
            } else {
                [System.IO.File]::ReadAllBytes((Join-Path $cacheDir 'bbbb.simms')) | Should -Be ([byte[]](1, 2, 3))
            }
        }
    }

    It 'never says the files were not installed when the final state is unverified, and still says so after a verified rollback' {
        $f = New-Cps3Fixture 'offer-honest-wording'
        $profiles = Join-Path $f.Root 'UserProfiles'
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $profiles 'cps_jojo.xml'), '<GameProfile />')
        $script:cps3OfferSource = $f.Src
        foreach ($case in @(
            @{ Outcome = 'ACTION_REQUIRED'; NotInstalledText = $false },
            @{ Outcome = 'ROLLED_BACK_VERIFIED'; NotInstalledText = $true }
        )) {
            $script:cps3Outcome = $case.Outcome
            $script:cps3HostLines = New-Object System.Collections.Generic.List[string]
            Mock Write-Host { [void]$script:cps3HostLines.Add([string]$Object) }
            Mock Read-TpmYesNo { 'Y' }
            Mock Invoke-TpmCps3SupplementaryInstall {
                [pscustomobject]@{
                    Outcome = $script:cps3Outcome; ReasonCode = 'TEST'; Summary = 'TPM stopped before it could verify the final state.'
                    Transaction = [pscustomobject]@{ Rollback = [pscustomobject]@{ FailedItems = @('aaaa.simms') } }
                    Installed = @(); Replaced = @(); AlreadyPresent = @(); PreservedExisting = @(); Conflicts = @(); Blocked = @()
                    Missing = @(); Extra = @(); Unsafe = @(); Ambiguous = @(); Mismatched = @(); Complete = $false
                }
            }
            [void](Invoke-TpmCps3SupplementaryOffer -TpRoot $f.Tp -UserProfilesDir $profiles)
            $text = $script:cps3HostLines -join "`n"
            if ($case.NotInstalledText) {
                $text | Should -Match 'were not installed'
            } else {
                $text | Should -Not -Match 'not installed'
                $text | Should -Match 'could not verify the final state'
                $text | Should -Match 'aaaa\.simms'
            }
        }
    }
}

# Optional real-data smoke, fixture-only by default: needs TPM_REAL_SOURCE_TESTS=1 and TPM_CPS3_REAL_SOURCE (a folder or .zip you already own).
# Reads the source only (and proves it was not changed) and installs into a disposable TestDrive TeknoParrot folder.
Describe 'CPS3 supplementary install against a user-supplied real set' {
    It 'validates the full 103-member set, installs the pinned files, re-runs as a no-op, and leaves an existing .nv untouched' -Skip:(-not $script:Cps3RealSource) {
        Mock Write-TpmCompactExtractionProgress {}
        Mock Write-Log {}
        $f = New-Cps3Fixture 'real-set'
        $nvDir = Join-Path $f.Tp 'TeknoCPS\nvram'
        New-Item -ItemType Directory -Path $nvDir -Force | Out-Null
        $sentinel = [byte[]](1, 2, 3, 4)
        [System.IO.File]::WriteAllBytes((Join-Path $nvDir 'sfiii3.nv'), $sentinel)
        $manifest = @(Get-TpmCps3SupplementaryManifest)
        $installable = @($manifest | Where-Object { $_.Kind -eq 'cache' -or $_.Kind -eq 'nvram' })
        $sourceBefore = Get-TpmSourceStamp -Path $env:TPM_CPS3_REAL_SOURCE
        $r = Invoke-TpmCps3SupplementaryInstall -SourcePath $env:TPM_CPS3_REAL_SOURCE -TpRoot $f.Tp
        $r.Outcome | Should -Be 'SUCCEEDED'
        @($r.Installed).Count | Should -Be ($installable.Count - 1)
        @($r.PreservedExisting) | Should -Be @('sfiii3.nv')
        foreach ($entry in $installable) {
            if ($entry.Name -eq 'sfiii3.nv') { continue }
            (Get-FileHash -LiteralPath (Join-Path $f.Tp ('TeknoCPS\' + $entry.Folder + '\' + $entry.Name)) -Algorithm SHA256).Hash | Should -Be $entry.Sha256
        }
        Test-Path -LiteralPath (Join-Path $f.Tp 'README.txt') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $f.Tp 'TeknoCPS\cps3-install\aeeba2be4de91a71890bfb47347c8b4cf217c5aa.simms') | Should -BeFalse
        [System.IO.File]::ReadAllBytes((Join-Path $nvDir 'sfiii3.nv')) | Should -Be $sentinel
        $before = Get-Cps3Tree -Root $f.Tp
        $again = Invoke-TpmCps3SupplementaryInstall -SourcePath $env:TPM_CPS3_REAL_SOURCE -TpRoot $f.Tp
        $again.Outcome | Should -Be 'NO_OP'
        (Get-Cps3Tree -Root $f.Tp) | Should -Be $before
        (Get-TpmSourceStamp -Path $env:TPM_CPS3_REAL_SOURCE) | Should -Be $sourceBefore -Because 'the real source must never be written to'
    }
}
