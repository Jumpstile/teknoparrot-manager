#Requires -Module Pester

# Regression suite for Test-XmlFolder in scripts\Invoke-TPM-InstallHealthCheck.ps1
# (issue #77). The script has a mandatory top-level -TeknoParrotRoot parameter, so
# it cannot be dot-sourced directly without launching the full health check --
# instead, BeforeAll parses it with the PowerShell AST and defines only the
# Test-XmlFolder function body in this session, mirroring the pattern already
# used by Tests\TeknoParrot-Manager.Tests.ps1.
#
# ASCII-only source, per CLAUDE.md: PS 5.1 reads a BOM-less UTF-8 file as
# Windows-1252, so any literal multi-byte character in this file's own source
# (not file content built at runtime) risks a parse error under the project's
# target interpreter. Every non-ASCII test value below is built from [char]
# codepoints at runtime instead of being written as a literal character here.
#
# Run with: Invoke-Pester -Path .\Tests\InstallHealthCheck.Tests.ps1
# Must also be run and pass under Windows PowerShell 5.1 specifically, not
# only pwsh -- this project's production script and its tests both target
# PS 5.1 as the primary interpreter.

# Codepoint-built non-ASCII strings -- see file header. $script:AccentedFolderName
# is deliberately assigned here at top-level script scope, NOT inside BeforeAll:
# Pester v5 re-executes a container's Describe-block body (including the
# foreach loop below that builds one It per folder name) as part of running
# each contained test, and that Describe-body code can see top-level script
# variables. A first draft of this file assigned it inside BeforeAll instead,
# and the loop below silently captured an empty string, because BeforeAll has
# not run yet at the point Describe-body code executes -- caught by
# inspecting the actual It titles Pester produced ("... folder named '' as
# valid"), not by the tests themselves, since Join-Path $TestDrive ''
# harmlessly resolved to $TestDrive and still "passed".
#
# $script:KatakanaGameName is the opposite case and MUST be assigned inside
# BeforeAll instead: it is read only from directly inside a plain It body
# (not from Describe-body/foreach code), and It bodies run in Pester's own
# scope chain, which does NOT inherit a container's top-level script scope at
# all -- only $script: values assigned in an enclosing BeforeAll/BeforeEach.
# Confirmed empirically: an isolated repro assigning a top-level $script:
# variable (or even a top-level function) with no BeforeAll produced $null/
# "not recognized" when read from inside a plain It, while the identical
# value assigned inside BeforeAll was visible correctly.
#
# 0x00E9 = e-acute (accented Latin, a realistic folder-name character);
# 0x30B2/0x30FC/0x30E0 = katakana "ge-mu" ("game"), a realistic non-Latin
# folder-name/content case.
$script:AccentedFolderName = "Games " + [string][char]0x00E9 + "dition"

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "..\scripts\Invoke-TPM-InstallHealthCheck.ps1"
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Failed to parse Invoke-TPM-InstallHealthCheck.ps1: $($parseErrors -join '; ')"
    }
    $functionAsts = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functionAsts) {
        if ($fn.Name -eq 'Test-XmlFolder') {
            . ([scriptblock]::Create($fn.Extent.Text))
        }
    }

    $script:KatakanaGameName = [string]([char]0x30B2) + [string]([char]0x30FC) + [string]([char]0x30E0)
}

Describe "Test-XmlFolder -LiteralPath / encoding safety (issue #77)" {
    # These folder names are exactly the class of literal characters that break
    # naive Test-Path/Get-ChildItem wildcard handling ([, ], *, ?) or that used
    # to be handled correctly only by accident (apostrophes, ampersands,
    # Unicode, embedded spaces). Every one of these must validate correctly
    # since the health check walks real TeknoParrot install folders users
    # control the naming of.
    $specialFolderNameFactories = @(
        { 'Games [TeknoParrot]' }
        { "O'Brien's Arcade" }
        { 'Games & More' }
        { $script:AccentedFolderName }
        { 'Games With Spaces' }
        { 'Games (RC2.1) [v1.0]' }
    )

    foreach ($factory in $specialFolderNameFactories) {
        $folderName = & $factory
        It "reports a real XML file inside a literal folder named '$folderName' as valid" {
            $dir = Join-Path $TestDrive $folderName
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $dir 'Game.xml') -Value '<GameProfile><GameName>Test</GameName></GameProfile>' -Encoding UTF8

            $result = Test-XmlFolder -Name 'Special' -Path $dir

            $result.FileCount | Should -Be 1
            $result.InvalidCount | Should -Be 0
        }
    }

    It "returns FileCount 0 for a folder that does not exist, without throwing" {
        $dir = Join-Path $TestDrive "does-not-exist-[folder]"
        { Test-XmlFolder -Name 'Missing' -Path $dir } | Should -Not -Throw
        $result = Test-XmlFolder -Name 'Missing' -Path $dir
        $result.FileCount | Should -Be 0
        $result.InvalidCount | Should -Be 0
    }

    It "reports the real parse exception (not a swallowed generic string) for a genuinely malformed XML file" {
        $dir = Join-Path $TestDrive ("badxml-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'Broken.xml') -Value '<GameProfile><Unclosed>' -Encoding UTF8

        $result = Test-XmlFolder -Name 'Broken' -Path $dir

        $result.InvalidCount | Should -Be 1
        $result.Invalid[0].Error | Should -Not -BeNullOrEmpty
        $result.Invalid[0].Error | Should -Not -Be 'PARSE_ERROR'
    }

    It "successfully parses a BOM-less UTF-8 XML file that a Get-Content -Raw + [xml] cast would misread" {
        # This is the exact false-WARN mechanism confirmed in issue #77:
        # Get-Content -Raw hands the parser a string already decoded by
        # PowerShell's own encoding heuristics, which can disagree with the
        # file's actual encoding for BOM-less content. XmlDocument.Load()
        # reads bytes directly and resolves encoding itself, matching
        # production Read-Xml.
        $dir = Join-Path $TestDrive ("bomless-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $path = Join-Path $dir 'NoBom.xml'
        $bytes = [System.Text.Encoding]::UTF8.GetBytes('<GameProfile><GameName>NoBom</GameName></GameProfile>')
        [System.IO.File]::WriteAllBytes($path, $bytes)

        $result = Test-XmlFolder -Name 'BomLess' -Path $dir

        $result.FileCount | Should -Be 1
        $result.InvalidCount | Should -Be 0
    }

    It "successfully parses a valid UTF-8 XML file that DOES carry a BOM" {
        # XmlDocument.Load() must handle both ends of the encoding-detection
        # spectrum correctly: BOM present (this test) and BOM absent (above).
        # A regression that only fixed the BOM-less case would still be a
        # partial fix.
        $dir = Join-Path $TestDrive ("withbom-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $path = Join-Path $dir 'WithBom.xml'
        $utf8Bom = New-Object System.Text.UTF8Encoding $true
        [System.IO.File]::WriteAllText($path, '<GameProfile><GameName>WithBom</GameName></GameProfile>', $utf8Bom)

        $firstThreeBytes = [System.IO.File]::ReadAllBytes($path) | Select-Object -First 3
        ($firstThreeBytes -join ',') | Should -Be '239,187,191'

        $result = Test-XmlFolder -Name 'WithBom' -Path $dir

        $result.FileCount | Should -Be 1
        $result.InvalidCount | Should -Be 0
    }

    It "successfully parses a valid BOM-less UTF-8 XML file whose CONTENT is non-ASCII" {
        # Distinct from the BOM-less test above: that one used ASCII-only
        # XML content bytes. This proves the actual multi-byte character
        # data inside the file (a real-world case: a game name imported from
        # a non-English TeknoParrot profile) round-trips correctly through
        # XmlDocument.Load() with no BOM to anchor the encoding.
        $dir = Join-Path $TestDrive ("bomless-nonascii-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $path = Join-Path $dir 'NonAsciiContent.xml'
        $xml = "<GameProfile><GameName>{0}</GameName></GameProfile>" -f $script:KatakanaGameName
        $bytesNoBom = [System.Text.Encoding]::UTF8.GetBytes($xml)
        [System.IO.File]::WriteAllBytes($path, $bytesNoBom)

        $result = Test-XmlFolder -Name 'NonAsciiContent' -Path $dir

        $result.FileCount | Should -Be 1
        $result.InvalidCount | Should -Be 0

        $doc = New-Object System.Xml.XmlDocument
        $doc.Load($path)
        $doc.GameProfile.GameName | Should -Be $script:KatakanaGameName
    }

    It "treats a literal '*' in the requested path as literal, not a wildcard match against an unrelated real folder" {
        # NTFS forbids '*' in an actual folder name, so there is no way to
        # create a directory literally named this -- the point of this test
        # is that Test-XmlFolder's internal Test-Path -LiteralPath call must
        # never wildcard-expand the string and accidentally match a
        # different, real sibling folder. A decoy folder that WOULD match
        # the pattern under non-literal expansion proves the guard is real,
        # not just "the path doesn't exist so of course it returns nothing."
        $parent = Join-Path $TestDrive ("star-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        $decoy = Join-Path $parent 'NoSuchAnyFolder'
        New-Item -ItemType Directory -Path $decoy -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $decoy 'Decoy.xml') -Value '<GameProfile/>' -Encoding UTF8

        $literalStarPath = Join-Path $parent 'NoSuch*Folder'

        { Test-XmlFolder -Name 'StarPath' -Path $literalStarPath } | Should -Not -Throw
        $result = Test-XmlFolder -Name 'StarPath' -Path $literalStarPath
        $result.FileCount | Should -Be 0
        $result.InvalidCount | Should -Be 0
    }

    It "treats a literal '?' in the requested path as literal, not a wildcard match against an unrelated real folder" {
        # Same guarantee as the '*' case above, for the single-character
        # wildcard. NTFS also forbids '?' in a real folder name.
        $parent = Join-Path $TestDrive ("question-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        $decoy = Join-Path $parent 'NoSuchXFolder'
        New-Item -ItemType Directory -Path $decoy -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $decoy 'Decoy.xml') -Value '<GameProfile/>' -Encoding UTF8

        $literalQuestionPath = Join-Path $parent 'NoSuch?Folder'

        { Test-XmlFolder -Name 'QuestionPath' -Path $literalQuestionPath } | Should -Not -Throw
        $result = Test-XmlFolder -Name 'QuestionPath' -Path $literalQuestionPath
        $result.FileCount | Should -Be 0
        $result.InvalidCount | Should -Be 0
    }
}
