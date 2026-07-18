#Requires -Module Pester

# Regression suite for Test-XmlFolder in scripts\Invoke-TPM-InstallHealthCheck.ps1
# (issue #77). The script has a mandatory top-level -TeknoParrotRoot parameter, so
# it cannot be dot-sourced directly without launching the full health check --
# instead, BeforeAll parses it with the PowerShell AST and defines only the
# Test-XmlFolder function body in this session, mirroring the pattern already
# used by Tests\TeknoParrot-Manager.Tests.ps1.
#
# Run with: Invoke-Pester -Path .\Tests\InstallHealthCheck.Tests.ps1

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
}

Describe "Test-XmlFolder -LiteralPath / encoding safety (issue #77)" {
    # These folder names are exactly the class of literal characters that break
    # naive Test-Path/Get-ChildItem wildcard handling ([, ], *, ?) or that used
    # to be handled correctly only by accident (apostrophes, ampersands,
    # Unicode, embedded spaces). Every one of these must validate correctly
    # since the health check walks real TeknoParrot install folders users
    # control the naming of.
    $specialFolderNames = @(
        'Games [TeknoParrot]'
        "O'Brien's Arcade"
        'Games & More'
        'ゲーム フォルダ'
        'Games With Spaces'
        'Games (RC2.1) [v1.0]'
    )

    foreach ($folderName in $specialFolderNames) {
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
}
