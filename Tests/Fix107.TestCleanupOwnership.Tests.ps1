#Requires -Module Pester

# FIX107 (NEW-B1): test cleanup must only delete what the test itself created.
# Old fixtures took a before/after snapshot of the shared %TEMP%\TeknoParrotManagerStaging folder and deleted every
# new dgVoodoo2-* / ReShade-* directory, which could destroy the staging or rollback backup of a real TeknoParrot
# Manager run happening at the same time. The product reads $env:TEMP each time New-TpmStagingDirectory runs, so the
# fixtures now point $env:TEMP at a private TestDrive directory and delete only that private root.
# Each It names the change that makes it fail.

BeforeAll {
    $script:Fix107TestsRoot = $PSScriptRoot
    $script:Fix107ProductPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:Fix107ProductPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX107 tests could not parse the production script.' }
    $stagingFunction = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'New-TpmStagingDirectory' }, $true)
    if (-not $stagingFunction) { throw 'FIX107 tests could not find New-TpmStagingDirectory.' }
    . ([scriptblock]::Create($stagingFunction.Extent.Text))

    # Returns one text line per unsafe shared-TEMP cleanup found in a script file: a loop or pipeline that deletes
    # whatever a wildcard Get-ChildItem -Filter finds, or any "$before... -notcontains" snapshot difference.
    function Find-Fix107UnsafeCleanup([string]$Path) {
        $t = $null
        $e = $null
        $a = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$t, [ref]$e)
        $found = New-Object System.Collections.Generic.List[string]
        $wildcardListing = "Get-ChildItem[^\r\n]*-Filter\s+['""][^'""]*\*"
        $deleteText = '(::|\.)Delete\s*\(|Remove-Item'
        foreach ($loop in $a.FindAll({ param($n) $n -is [System.Management.Automation.Language.ForEachStatementAst] }, $true)) {
            if ($loop.Condition.Extent.Text -match $wildcardListing -and $loop.Body.Extent.Text -match $deleteText) {
                $found.Add(('{0}:{1} foreach deletes a wildcard Get-ChildItem listing' -f $Path, $loop.Extent.StartLineNumber))
            }
        }
        foreach ($pipe in $a.FindAll({ param($n) $n -is [System.Management.Automation.Language.PipelineAst] -and $n.PipelineElements.Count -gt 1 }, $true)) {
            $first = $pipe.PipelineElements[0].Extent.Text
            $rest = @($pipe.PipelineElements | Select-Object -Skip 1 | ForEach-Object { $_.Extent.Text }) -join ' '
            if ($first -match $wildcardListing -and $rest -match 'Remove-Item') {
                $found.Add(('{0}:{1} wildcard Get-ChildItem piped to Remove-Item' -f $Path, $pipe.Extent.StartLineNumber))
            }
        }
        foreach ($cmd in $a.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
            if ($cmd.Extent.Text -match '\$before\w*\s+-notcontains') {
                $found.Add(('{0}:{1} before/after snapshot difference' -f $Path, $cmd.Extent.StartLineNumber))
            }
        }
        foreach ($cmd in $a.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Remove-Item' }, $true)) {
            if ($cmd.Extent.Text -match '(?i)(env:TEMP|env:TMP|GetTempPath)[^\r\n]*\*') {
                $found.Add(('{0}:{1} Remove-Item with a wildcard under the shared TEMP' -f $Path, $cmd.Extent.StartLineNumber))
            }
        }
        return @($found)
    }
}

Describe 'FIX107 NEW-B1 test cleanup ownership' {
    It 'finds no shared-TEMP pattern or before/after cleanup in any test script' {
        # Mutation: restoring a "$beforeStages ... -notcontains ... Directory.Delete" cleanup (or a
        # foreach over Get-ChildItem -Filter 'dgVoodoo2-*' that deletes) in any Tests\*.ps1 makes this fail.
        $hits = @(Get-ChildItem -LiteralPath $script:Fix107TestsRoot -Filter '*.ps1' -File | Where-Object { $_.Name -ne 'Fix107.TestCleanupOwnership.Tests.ps1' } | ForEach-Object { Find-Fix107UnsafeCleanup -Path $_.FullName })
        ($hits -join [Environment]::NewLine) | Should -BeNullOrEmpty
    }

    It 'the scanner really flags the old unsafe cleanup shapes and accepts an owned-root cleanup' {
        # Mutation: loosening Find-Fix107UnsafeCleanup (for example dropping the -notcontains rule) makes this fail.
        $bad = Join-Path $TestDrive 'bad-old-cleanup.ps1'
        $oldText = @'
$stagingRoot = Join-Path $env:TEMP 'TeknoParrotManagerStaging'
$beforeStages = @(Get-ChildItem -LiteralPath $stagingRoot -Directory -Filter 'dgVoodoo2-*' | Select-Object -ExpandProperty FullName)
$leftoverStages = @(Get-ChildItem -LiteralPath $stagingRoot -Directory -Filter 'dgVoodoo2-*' | Where-Object { $beforeStages -notcontains $_.FullName })
foreach ($stagePath in @(Get-ChildItem -LiteralPath $stagingRoot -Directory -Filter 'ReShade-*')) { [System.IO.Directory]::Delete($stagePath.FullName, $true) }
Get-ChildItem -LiteralPath $stagingRoot -Directory -Filter 'dgVoodoo2-*' | Remove-Item -Recurse -Force
Remove-Item -Path (Join-Path ([System.IO.Path]::GetTempPath()) 'tpm-*') -Recurse -Force
'@
        [System.IO.File]::WriteAllText($bad, $oldText)
        @(Find-Fix107UnsafeCleanup -Path $bad).Count | Should -Be 4

        $good = Join-Path $TestDrive 'good-owned-cleanup.ps1'
        $goodText = @'
$stagingRoot = Join-Path $env:TEMP 'TeknoParrotManagerStaging'
$newStages = @(Get-ChildItem -LiteralPath $stagingRoot -Directory -Filter 'dgVoodoo2-*' -ErrorAction SilentlyContinue)
if (Test-Path -LiteralPath $stagingRoot) { [System.IO.Directory]::Delete($stagingRoot, $true) }
'@
        [System.IO.File]::WriteAllText($good, $goodText)
        @(Find-Fix107UnsafeCleanup -Path $good).Count | Should -Be 0
    }

    It 'the product builds the staging root from $env:TEMP at call time, so a private TEMP fully owns the staging directory' {
        # Mutation: making New-TpmStagingDirectory use a fixed path, [IO.Path]::GetTempPath() cached at load, or any
        # root other than $env:TEMP makes the private-TEMP fixtures unsafe, and this test fails.
        $savedTemp = $env:TEMP
        $privateTemp = Join-Path $TestDrive ('own-temp-' + [guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($privateTemp)
        try {
            $env:TEMP = $privateTemp
            $dir = New-TpmStagingDirectory -Label 'dgVoodoo2'
        } finally {
            $env:TEMP = $savedTemp
        }
        $privateRoot = [System.IO.Path]::GetFullPath((Join-Path $privateTemp 'TeknoParrotManagerStaging')).TrimEnd('\')
        ([System.IO.Path]::GetFullPath($dir)).StartsWith($privateRoot + '\', [System.StringComparison]::OrdinalIgnoreCase) | Should -BeTrue
        Test-Path -LiteralPath $dir -PathType Container | Should -BeTrue
        $env:TEMP | Should -BeExactly $savedTemp
    }
}
