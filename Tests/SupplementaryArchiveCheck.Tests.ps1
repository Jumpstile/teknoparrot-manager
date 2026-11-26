#Requires -Module Pester

# Supplementary archives: a player's ZIP is used only when it is the exact version the supplementary list describes,
# and the supplementary list never hides a collection game. Isolated files under $TestDrive only.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'The production script did not parse.' }
    $wanted = @('Get-NormalizedGameKey', 'Build-DatIndexFromStream', 'Merge-TpmSupplementaryDatIndex', 'Test-TpmZipLaunchFileAgainstDat')
    $functionFile = Join-Path $TestDrive 'supp-functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $wanted -contains $args[0].Name }, $true) |
        ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    . $functionFile
    function Write-TpmCompactExtractionProgress { param([Parameter(ValueFromRemainingArguments)]$Rest) }
    function Write-Log { param([Parameter(ValueFromRemainingArguments)]$Rest) }
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    function Get-SuppSha1 { param([byte[]]$Bytes) $h = [Security.Cryptography.SHA1]::Create(); try { return ([BitConverter]::ToString($h.ComputeHash($Bytes)) -replace '-', '').ToLowerInvariant() } finally { $h.Dispose() } }

    function New-SuppZip {
        param([string]$Path, [System.Collections.IDictionary]$Entries)
        $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew)
        try {
            $archive = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create)
            try {
                foreach ($name in $Entries.Keys) {
                    $entry = $archive.CreateEntry([string]$name)
                    $s = $entry.Open()
                    try { $b = [byte[]]$Entries[$name]; $s.Write($b, 0, $b.Length) } finally { $s.Dispose() }
                }
            } finally { $archive.Dispose() }
        } finally { $stream.Dispose() }
    }

    $script:RightExe = [Text.Encoding]::ASCII.GetBytes('the real game file, version 1.00.00')
    $script:WrongExe = [byte[]]$script:RightExe.Clone(); $script:WrongExe[0] = 88   # same name and length, different bytes
    $script:Sha1 = Get-SuppSha1 $script:RightExe
}

Describe 'Supplementary list launch file' {
    It 'is read for each supplementary game, whatever the letter case of the file name' {
        $xml = @"
<?xml version="1.0"?>
<datafile><game name="Fake Game (1.00.00)(2020)[Sega ALLS][TP]"><GameProfile>FakeGame</GameProfile><Executable>game.exe</Executable>
<rom name="data/a.bin" size="3" sha1="aa"/><rom name="Game.exe" size="$($script:RightExe.Length)" crc="00000000" sha1="$($script:Sha1)"/></game></datafile>
"@
        $sink = @{}
        $stream = New-Object IO.MemoryStream (, [Text.Encoding]::UTF8.GetBytes($xml))
        $index = Build-DatIndexFromStream $stream -LaunchFileSink $sink
        $index.Count | Should -Be 1
        $sink['Fake Game (1.00.00)(2020)[Sega ALLS][TP]'].Sha1 | Should -Be $script:Sha1
        [int]$sink['Fake Game (1.00.00)(2020)[Sega ALLS][TP]'].Size | Should -Be $script:RightExe.Length
    }
}

Describe 'A player ZIP against the supplementary list' {
    BeforeEach {
        $script:dir = Join-Path $TestDrive ('z-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $script:dir | Out-Null
        $script:launch = [pscustomobject]@{ Name = 'game.exe'; Size = [string]$script:RightExe.Length; Crc = ''; Md5 = ''; Sha1 = $script:Sha1; Sha256 = '' }
    }

    It 'accepts the ZIP whose game file has the listed size and hash' {
        $zip = Join-Path $script:dir 'good.zip'
        New-SuppZip -Path $zip -Entries ([ordered]@{ 'Game.exe' = $script:RightExe; 'data/a.bin' = [byte[]](1, 2, 3) })
        (Test-TpmZipLaunchFileAgainstDat -ZipPath $zip -LaunchFile $script:launch).Matches | Should -BeTrue
    }

    It 'refuses another version of the game even when the file name and size are the same' {
        $zip = Join-Path $script:dir 'wrong.zip'
        New-SuppZip -Path $zip -Entries ([ordered]@{ 'game.exe' = $script:WrongExe })
        $r = Test-TpmZipLaunchFileAgainstDat -ZipPath $zip -LaunchFile $script:launch
        $r.Matches | Should -BeFalse
        $r.Reason | Should -Match 'not the file the list describes'
    }

    It 'refuses a ZIP that does not hold the game file' {
        $zip = Join-Path $script:dir 'nofile.zip'
        New-SuppZip -Path $zip -Entries ([ordered]@{ 'readme.txt' = [byte[]](65) })
        $r = Test-TpmZipLaunchFileAgainstDat -ZipPath $zip -LaunchFile $script:launch
        $r.Matches | Should -BeFalse
        $r.Reason | Should -Match 'does not hold game.exe'
    }

    It 'refuses a ZIP that is not there and creates nothing' {
        $r = Test-TpmZipLaunchFileAgainstDat -ZipPath (Join-Path $script:dir 'absent.zip') -LaunchFile $script:launch
        $r.Matches | Should -BeFalse
        @(Get-ChildItem -LiteralPath $script:dir -Force).Count | Should -Be 0
    }
}

Describe 'Supplementary list next to the collection list' {
    It 'keeps the collection game, with its own game file, when a supplementary game reads the same' {
        $entry = { param($name, $exe) [pscustomobject]@{ Alternates = (New-Object System.Collections.Generic.List[object]); ProfileCode = 'VF3TB'; Executable = $exe; OriginalName = $name; ProfileCode2 = ''; Executable2 = ''; TestMenuExecutable = '' } }
        $main = & $entry 'Virtua Fighter 3tb Online (APM3)(1.01.00)(2023-12-01)(JPN)[Sega ALLS][TP]' 'new.exe'
        $supp = & $entry 'Virtua Fighter 3tb Online (APM3)(1.00.00)(2023-11-28)(JPN)[Sega ALLS][TP]' 'old.exe'
        $key = Get-NormalizedGameKey $main.OriginalName
        (Get-NormalizedGameKey $supp.OriginalName) | Should -Be $key
        $datIndex = @{ $key = $main }
        $codes = New-Object 'System.Collections.Generic.HashSet[string]'
        Merge-TpmSupplementaryDatIndex -DatIndex $datIndex -SuppIndex @{ $key = $supp } -SuppCodes $codes
        $datIndex[$key].Executable | Should -Be 'old.exe'
        @($datIndex[$key].Alternates | Where-Object { $_.OriginalName -eq $main.OriginalName }).Executable | Should -Be 'new.exe'
        $codes.Contains('VF3TB') | Should -BeTrue
    }
}
