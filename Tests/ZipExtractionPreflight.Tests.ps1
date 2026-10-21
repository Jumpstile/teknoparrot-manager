#Requires -Module Pester

# Expand-ZipFileSafe entry-name validation and whole-archive preflight.
# Governing source: PKWARE APPNOTE.TXT 6.3.10 section 4.4.17.1 ("The path
# stored MUST NOT contain a drive or device letter, or a leading slash").
# Inventory rows: ZIP-S01..ZIP-S05, INV-ZIP-01..INV-ZIP-03
# (docs/RC8-REMEDIATION-INVENTORY.md). Synthetic archives only.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'ZIP preflight test bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'tpm-zip-functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    . $functionFile
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $script:logPath = Join-Path $TestDrive 'test.log'

    function New-RawZip {
        # Writes entries with the exact raw names given (no normalization).
        # A name ending in '/' is written as a directory entry with no data.
        # .NET Framework's CreateEntry refuses names containing characters
        # such as '<' or a tab, so such names are written under an
        # equal-length ASCII placeholder and the placeholder bytes are then
        # replaced in both the local header and the central directory.
        param([string]$Path, [string[]]$Names)
        $invalid = [char[]]('<>|?*"' + [string][char]9)
        $patches = New-Object System.Collections.Generic.List[object]
        $fs = [IO.File]::Open($Path, [IO.FileMode]::CreateNew)
        try {
            $zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
            try {
                foreach ($name in $Names) {
                    $stored = $name
                    if ($name.IndexOfAny($invalid) -ge 0) {
                        $stored = 'PLACEHOLDER-' + [guid]::NewGuid().ToString('N')
                        $stored = $stored.Substring(0, [Math]::Min($stored.Length, $name.Length)).PadRight($name.Length, 'Q')
                        [void]$patches.Add([pscustomobject]@{ From = $stored; To = $name })
                    }
                    $entry = $zip.CreateEntry($stored)
                    if (-not $name.EndsWith('/')) {
                        $writer = New-Object System.IO.StreamWriter($entry.Open())
                        $payload = if ($stored -ceq $name) { "payload:$name" } else { 'payload:patched' }
                        try { $writer.Write($payload) } finally { $writer.Dispose() }
                    }
                }
            } finally { $zip.Dispose() }
        } finally { $fs.Dispose() }
        if ($patches.Count -gt 0) {
            $latin = [Text.Encoding]::GetEncoding(28591)
            $text = $latin.GetString([IO.File]::ReadAllBytes($Path))
            foreach ($p in $patches) {
                $count = ([regex]::Matches($text, [regex]::Escape($p.From))).Count
                if ($count -ne 2) { throw "Placeholder for '$($p.To)' occurred $count times; expected 2." }
                $text = $text.Replace($p.From, $p.To)
            }
            [IO.File]::WriteAllBytes($Path, $latin.GetBytes($text))
        }
    }

    function New-ZipCase {
        param([string]$BaseRoot = $TestDrive)
        $root = Join-Path $BaseRoot ('zip-' + [guid]::NewGuid().ToString('N'))
        $dest = Join-Path $root 'dest'
        [void][IO.Directory]::CreateDirectory($dest)
        # Pre-existing content proves "unchanged" rather than merely "empty".
        [IO.File]::WriteAllText((Join-Path $dest 'existing.txt'), 'original-bytes')
        [void][IO.Directory]::CreateDirectory((Join-Path $dest 'existing-dir'))
        return [pscustomobject]@{ Root = $root; Dest = $dest; Zip = (Join-Path $root 'case.zip') }
    }

    function Get-TreeSnapshot {
        param([string]$Path)
        $long = '\\?\' + $Path
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            return @(Get-ChildItem -LiteralPath $long -Recurse -Force | Sort-Object FullName | ForEach-Object {
                $rel = $_.FullName.Substring($long.Length)
                if ($_.PSIsContainer) { "D|$rel" }
                else { "F|$rel|" + [BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($_.FullName))) }
            }) -join "`n"
        } finally { $sha.Dispose() }
    }
}

Describe 'Expand-ZipFileSafe raw entry-name validation (APPNOTE 4.4.17.1)' {
    It 'rejects raw entry <Name> before normalization and leaves the destination unchanged' -TestCases @(
        @{ Name = '/slash.txt' }
        @{ Name = '\back.txt' }
        @{ Name = '//server/share/unc.txt' }
        @{ Name = '\\server\share\unc2.txt' }
        @{ Name = '/' }
        @{ Name = 'C:/evil.txt' }
        @{ Name = 'C:evil.txt' }
        @{ Name = 'c:\evil.txt' }
        @{ Name = 'stream.txt:hidden' }
        @{ Name = '../evil.txt' }
        @{ Name = 'sub/../../evil.txt' }
        @{ Name = 'sub\..\..\evil.txt' }
        @{ Name = './dot.txt' }
        @{ Name = 'a//b.txt' }
        @{ Name = 'trailingdot./b.txt' }
        @{ Name = 'trailingspace /b.txt' }
        @{ Name = 'bad<name.txt' }
        @{ Name = 'bad|name.txt' }
        @{ Name = 'bad?name.txt' }
        @{ Name = "tab`tname.txt" }
    ) {
        param($Name)
        $c = New-ZipCase
        New-RawZip -Path $c.Zip -Names @($Name)
        $before = Get-TreeSnapshot $c.Dest
        { Expand-ZipFileSafe -ZipPath $c.Zip -DestDir $c.Dest } | Should -Throw
        Get-TreeSnapshot $c.Dest | Should -Be $before
        Test-Path -LiteralPath (Join-Path $c.Root 'evil.txt') | Should -BeFalse
    }

    It 'still accepts ordinary relative names including interior backslash separators: <Name>' -TestCases @(
        @{ Name = 'plain.txt'; Relative = 'plain.txt' }
        @{ Name = 'sub/folder/file.txt'; Relative = 'sub\folder\file.txt' }
        @{ Name = 'win\style\file.txt'; Relative = 'win\style\file.txt' }
        @{ Name = 'name with spaces/v1.2 (rev a).txt'; Relative = 'name with spaces\v1.2 (rev a).txt' }
        @{ Name = '.hidden/.config'; Relative = '.hidden\.config' }
        @{ Name = '..data/file.txt'; Relative = '..data\file.txt' }
    ) {
        param($Name, $Relative)
        $c = New-ZipCase
        New-RawZip -Path $c.Zip -Names @($Name)
        Expand-ZipFileSafe -ZipPath $c.Zip -DestDir $c.Dest
        [IO.File]::ReadAllText((Join-Path $c.Dest $Relative)) | Should -Be "payload:$Name"
        [IO.File]::ReadAllText((Join-Path $c.Dest 'existing.txt')) | Should -Be 'original-bytes'
    }

    # Device names are checked with the pure validator only: no archive is
    # extracted and no file or device with these names is ever opened.
    It 'rejects reserved Windows device name <Label>' -TestCases @(
        @{ Label = 'CON'; Name = 'CON' }
        @{ Label = 'con.txt'; Name = 'con.txt' }
        @{ Label = 'PRN'; Name = 'PRN' }
        @{ Label = 'aux.log'; Name = 'aux.log' }
        @{ Label = 'sub/NUL'; Name = 'sub/NUL' }
        @{ Label = 'NUL.tar.gz'; Name = 'NUL.tar.gz' }
        @{ Label = 'COM1'; Name = 'COM1' }
        @{ Label = 'com9.txt'; Name = 'com9.txt' }
        @{ Label = 'LPT1/inner.txt'; Name = 'LPT1/inner.txt' }
        @{ Label = 'lpt9.log'; Name = 'lpt9.log' }
        @{ Label = 'COM superscript one'; Name = ('COM' + [char]0x00B9) }
        @{ Label = 'COM superscript two with extension'; Name = ('com' + [char]0x00B2 + '.txt') }
        @{ Label = 'LPT superscript three'; Name = ('LPT' + [char]0x00B3) }
        @{ Label = 'LPT superscript one in a directory'; Name = ('dir/lpt' + [char]0x00B9 + '.dat') }
    ) {
        param($Label, $Name)
        { ConvertTo-SafeZipEntryRelativePath -EntryName $Name } | Should -Throw '*reserved Windows device name*'
    }

    It 'accepts non-reserved near-miss name <Label>' -TestCases @(
        @{ Label = 'COM0'; Name = 'COM0'; Relative = 'COM0' }
        @{ Label = 'LPT0.txt'; Name = 'LPT0.txt'; Relative = 'LPT0.txt' }
        @{ Label = 'COM10'; Name = 'COM10'; Relative = 'COM10' }
        @{ Label = 'lpt10.txt'; Name = 'lpt10.txt'; Relative = 'lpt10.txt' }
        @{ Label = 'console.txt'; Name = 'console.txt'; Relative = 'console.txt' }
        @{ Label = 'nul2/file.txt'; Name = 'nul2/file.txt'; Relative = 'nul2\file.txt' }
        @{ Label = 'COMA'; Name = 'COMA'; Relative = 'COMA' }
        @{ Label = 'COM superscript four (not reserved)'; Name = ('COM' + [char]0x2074); Relative = ('COM' + [char]0x2074) }
    ) {
        param($Label, $Name, $Relative)
        $info = ConvertTo-SafeZipEntryRelativePath -EntryName $Name
        $info.RelativePath | Should -BeExactly $Relative
        $info.IsDirectory | Should -BeFalse
    }
}

Describe 'Expand-ZipFileSafe whole-archive preflight' {
    It 'writes nothing when hostile entry <Hostile> appears after valid entries' -TestCases @(
        @{ Hostile = '../evil.txt' }
        @{ Hostile = '/rooted.txt' }
        @{ Hostile = '\\server\share\unc.txt' }
        @{ Hostile = 'C:/evil.txt' }
        @{ Hostile = 'bad|name.txt' }
    ) {
        param($Hostile)
        $c = New-ZipCase
        New-RawZip -Path $c.Zip -Names @('good1.txt', 'dir/good2.txt', 'newdir/', $Hostile)
        $before = Get-TreeSnapshot $c.Dest
        { Expand-ZipFileSafe -ZipPath $c.Zip -DestDir $c.Dest } | Should -Throw
        Get-TreeSnapshot $c.Dest | Should -Be $before
    }

    It 'does not create a missing destination when preflight rejects the archive' {
        $root = Join-Path $TestDrive ('zip-' + [guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($root)
        $zip = Join-Path $root 'case.zip'
        New-RawZip -Path $zip -Names @('ok.txt', '../evil.txt')
        $dest = Join-Path $root 'not-yet'
        { Expand-ZipFileSafe -ZipPath $zip -DestDir $dest } | Should -Throw
        Test-Path -LiteralPath $dest | Should -BeFalse
    }

    It 'rejects archive-internal collision <Case> without writing' -TestCases @(
        @{ Case = 'duplicate file, same case'; Names = @('dup.txt', 'dup.txt') }
        @{ Case = 'duplicate file, different case'; Names = @('dup.txt', 'DUP.txt') }
        @{ Case = 'duplicate file, different separator'; Names = @('a/b.txt', 'a\b.txt') }
        @{ Case = 'file then nested file under it'; Names = @('x', 'x/y.txt') }
        @{ Case = 'nested file then file at parent'; Names = @('x/y.txt', 'X') }
        @{ Case = 'directory entry then file of same name'; Names = @('x/', 'x') }
    ) {
        param($Case, $Names)
        $c = New-ZipCase
        New-RawZip -Path $c.Zip -Names $Names
        $before = Get-TreeSnapshot $c.Dest
        { Expand-ZipFileSafe -ZipPath $c.Zip -DestDir $c.Dest } | Should -Throw
        Get-TreeSnapshot $c.Dest | Should -Be $before
    }

    It 'rejects a destination collision where <Case> without writing' -TestCases @(
        @{ Case = 'an existing directory occupies a file target'; Names = @('first.txt', 'existing-dir') }
        @{ Case = 'an existing file occupies a needed directory'; Names = @('first.txt', 'existing.txt/inner.txt') }
        @{ Case = 'an existing file occupies an explicit directory entry'; Names = @('first.txt', 'existing.txt/') }
    ) {
        param($Case, $Names)
        $c = New-ZipCase
        New-RawZip -Path $c.Zip -Names $Names
        $before = Get-TreeSnapshot $c.Dest
        { Expand-ZipFileSafe -ZipPath $c.Zip -DestDir $c.Dest } | Should -Throw
        Get-TreeSnapshot $c.Dest | Should -Be $before
    }
}

Describe 'Expand-ZipFileSafe preserved compatibility' {
    It 'extracts explicit directories, implicit parents, and nested empty directories (issue #369 shape)' {
        $c = New-ZipCase
        New-RawZip -Path $c.Zip -Names @('game.exe', 'cache/empty/', 'a/b/c/', 'explicit/', 'explicit/file.txt', 'implicit/deep/file.txt', 'explicit/')
        Expand-ZipFileSafe -ZipPath $c.Zip -DestDir $c.Dest
        [IO.File]::ReadAllText((Join-Path $c.Dest 'game.exe')) | Should -Be 'payload:game.exe'
        Test-Path -LiteralPath (Join-Path $c.Dest 'cache\empty') -PathType Container | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $c.Dest 'a\b\c') -PathType Container | Should -BeTrue
        @(Get-ChildItem -LiteralPath (Join-Path $c.Dest 'a\b\c') -Force).Count | Should -Be 0
        [IO.File]::ReadAllText((Join-Path $c.Dest 'explicit\file.txt')) | Should -Be 'payload:explicit/file.txt'
        [IO.File]::ReadAllText((Join-Path $c.Dest 'implicit\deep\file.txt')) | Should -Be 'payload:implicit/deep/file.txt'
    }

    It 'replaces an existing file at a file target, as before' {
        $c = New-ZipCase
        New-RawZip -Path $c.Zip -Names @('existing.txt')
        Expand-ZipFileSafe -ZipPath $c.Zip -DestDir $c.Dest
        [IO.File]::ReadAllText((Join-Path $c.Dest 'existing.txt')) | Should -Be 'payload:existing.txt'
    }

    It 'merges into an existing directory without disturbing unrelated content' {
        $c = New-ZipCase
        New-RawZip -Path $c.Zip -Names @('existing-dir/new.txt')
        Expand-ZipFileSafe -ZipPath $c.Zip -DestDir $c.Dest
        [IO.File]::ReadAllText((Join-Path $c.Dest 'existing-dir\new.txt')) | Should -Be 'payload:existing-dir/new.txt'
        [IO.File]::ReadAllText((Join-Path $c.Dest 'existing.txt')) | Should -Be 'original-bytes'
    }

    It 'extracts a path longer than MAX_PATH' {
        # Keep this long tree outside TestDrive. Pester's recursive cleanup uses
        # ordinary paths and fails after the test has created a MAX_PATH-exceeding entry.
        # This test owns the short temporary root and removes it through the extended API.
        $shortRoot = Join-Path ([IO.Path]::GetFullPath($env:TEMP)) ('tpm-zip-maxpath-' + [guid]::NewGuid().ToString('N'))
        if ($shortRoot.Length -gt 120) { throw "Temporary fixture root is not short enough: $shortRoot" }
        [void][IO.Directory]::CreateDirectory($shortRoot)
        $extendedPrefix = ([string][char]92) + ([string][char]92) + '?' + [char]92
        try {
            $c = New-ZipCase -BaseRoot $shortRoot
            $segment = 'd' * 60
            $name = (@($segment) * 5 -join '/') + '/long-file-name.txt'
            New-RawZip -Path $c.Zip -Names @($name)
            Expand-ZipFileSafe -ZipPath $c.Zip -DestDir $c.Dest
            $long = $extendedPrefix + (Join-Path $c.Dest ($name.Replace('/', [string][char]92)))
            $long.Length | Should -BeGreaterThan 260
            [IO.File]::ReadAllText($long) | Should -Be "payload:$name"
        } finally {
            $longRoot = $extendedPrefix + $shortRoot
            if ([IO.Directory]::Exists($longRoot)) { [IO.Directory]::Delete($longRoot, $true) }
        }
    }

    It 'still rejects a corrupt archive' {
        $c = New-ZipCase
        [IO.File]::WriteAllText($c.Zip, 'not a zip')
        { Expand-ZipFileSafe -ZipPath $c.Zip -DestDir $c.Dest } | Should -Throw
    }
}
