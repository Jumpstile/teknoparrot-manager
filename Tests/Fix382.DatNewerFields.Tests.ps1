#Requires -Module Pester

# Issue 382: the dat reader ignored the newer per-game fields (GameProfile2, Executable2, TestMenuExecutable). A game that uses them
# lost its second executable. The reader now keeps them next to ProfileCode and Executable; a game without them reads exactly as
# before (the new values are empty text). Synthetic dat text only. Mutation: remove the new arms in Build-DatIndexFromStream -> fails.

BeforeAll {
    $scriptPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX382 bootstrap could not parse the production script.' }
    $names = @('Build-DatIndexFromStream', 'Get-NormalizedGameKey')
    $text = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $names -contains $args[0].Name }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $file = Join-Path $TestDrive 'fix382-functions.ps1'
    [System.IO.File]::WriteAllText($file, $text, (New-Object System.Text.UTF8Encoding $false))
    . $file
    function Write-Log { param([string]$msg) }
    function Write-TpmCompactExtractionProgress { param($Phase, $Label, $Current, $Total, $StartedAt, [switch]$Complete, $Outcome) }

    function Read-F382Dat {
        param([string]$Xml)
        $stream = New-Object System.IO.MemoryStream (, [System.Text.Encoding]::UTF8.GetBytes($Xml))
        try { return (Build-DatIndexFromStream -stream $stream) } finally { $stream.Dispose() }
    }
    $script:F382Dat = @'
<?xml version="1.0"?>
<datafile>
  <header><TPUISchemaVersion>1</TPUISchemaVersion></header>
  <game name="Two Part Game">
    <GameProfile>TWOPART</GameProfile><Executable>first.exe</Executable>
    <GameProfile2>TWOPART2</GameProfile2><Executable2>second.exe</Executable2>
    <TestMenuExecutable>testmenu.exe</TestMenuExecutable>
    <rom name="a.bin" size="1" crc="00000001" />
    <rom name="b.bin" size="1" crc="00000002" />
  </game>
  <game name="Plain Game">
    <GameProfile>PLAIN</GameProfile><Executable>plain.exe</Executable>
    <rom name="c.bin" size="1" crc="00000003" />
  </game>
</datafile>
'@
}

Describe 'The dat reader keeps the newer game fields (issue 382)' {
    BeforeEach { Mock Write-Log { } ; Mock Write-Host { } }

    It 'reads the second profile, the second executable and the test menu executable' {
        $index = Read-F382Dat -Xml $script:F382Dat
        $game = $index[(Get-NormalizedGameKey 'Two Part Game')]
        $game.ProfileCode | Should -Be 'TWOPART'
        $game.Executable | Should -Be 'first.exe'
        $game.ProfileCode2 | Should -Be 'TWOPART2'
        $game.Executable2 | Should -Be 'second.exe'
        $game.TestMenuExecutable | Should -Be 'testmenu.exe'
    }

    It 'a game without the newer fields reads as before, with empty new values and nothing taken from the game before it' {
        $index = Read-F382Dat -Xml $script:F382Dat
        $plain = $index[(Get-NormalizedGameKey 'Plain Game')]
        $plain.ProfileCode | Should -Be 'PLAIN'
        $plain.Executable | Should -Be 'plain.exe'
        $plain.OriginalName | Should -Be 'Plain Game'
        $plain.ProfileCode2 | Should -BeExactly ''
        $plain.Executable2 | Should -BeExactly ''
        $plain.TestMenuExecutable | Should -BeExactly ''
        $index.Count | Should -Be 2
    }
}

Describe 'The dat reader and the format version, missing elements and romzip/romnest (issue 382)' {
    BeforeEach { Mock Write-Log { } ; Mock Write-Host { } }

    It 'warns once in plain words about an unknown format version and still reads every game' {
        # Mutation: remove the check -> no warning; make it throw or return early -> the games are not read.
        $index = Read-F382Dat -Xml ($script:F382Dat -replace '<TPUISchemaVersion>1<', '<TPUISchemaVersion>7<')
        Should -Invoke Write-Host -Times 2 -Exactly -ParameterFilter { $Object -match 'version 7|Check for a newer Manager' }
        Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $msg -match 'TPUISchemaVersion 7' }
        $index.Count | Should -Be 2
        $index[(Get-NormalizedGameKey 'Two Part Game')].Executable2 | Should -Be 'second.exe'
    }

    It 'says nothing for version 1 and for a dat with no version at all' {
        $null = Read-F382Dat -Xml $script:F382Dat
        $null = Read-F382Dat -Xml ($script:F382Dat -replace '<header>.*</header>', '')
        Should -Invoke Write-Host -Times 0 -Exactly
    }

    It 'reads a game with missing elements as empty values, skips a game with no profile, and passes over romzip and romnest' {
        $xml = @'
<?xml version="1.0"?>
<datafile>
  <header><TPUISchemaVersion>1</TPUISchemaVersion></header>
  <game name="Only Profile"><GameProfile>ONLYPROF</GameProfile></game>
  <game name="No Profile"><Executable>none.exe</Executable></game>
  <game name="Mame Style">
    <GameProfile>MAMESTYLE</GameProfile><Executable>mame.exe</Executable>
    <romzip archive="mame.zip" mode="members" count="2" format="storezip"/>
    <romnest archive="mame.zip" name="a.bin" size="1" crc="00000001" sha1="00"/>
    <romnest archive="mame.zip" name="b.bin" size="1" crc="00000002" sha1="01"/>
  </game>
  <game name="After Mame"><GameProfile>AFTER</GameProfile><Executable>after.exe</Executable></game>
</datafile>
'@
        $index = Read-F382Dat -Xml $xml
        $index.Count | Should -Be 3
        $index[(Get-NormalizedGameKey 'Only Profile')].Executable | Should -BeExactly ''
        $index[(Get-NormalizedGameKey 'Only Profile')].ProfileCode2 | Should -BeExactly ''
        $index.ContainsKey((Get-NormalizedGameKey 'No Profile')) | Should -BeFalse
        $index[(Get-NormalizedGameKey 'Mame Style')].Executable | Should -Be 'mame.exe'
        $index[(Get-NormalizedGameKey 'After Mame')].ProfileCode | Should -Be 'AFTER'
    }
}
