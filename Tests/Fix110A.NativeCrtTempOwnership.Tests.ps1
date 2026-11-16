#Requires -Module Pester

# FIX110A (S-5): the native-CRT clean-up removes only a temporary file the atomic writer proves it created and kept.
#   Before, every "<profile>.<32 hex>.tmp" file that was not in a listing taken before the write was treated as this call's
#   output. A temporary file of another atomic writer that appeared during that time was deleted before its publication.
#   Now Write-TpmAtomicTextFile reports the exact path of the temp it created and still holds (-RetainedTempPaths), and the
#   clean-up removes those paths and nothing else.
# The production script is parsed and only its function definitions are dot-sourced; no top-level product code runs.
# Everything lives under TestDrive with synthetic files. Each It names the product change that makes it fail.
# What this CANNOT prove: a real second writer racing in real time.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX110A tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $functionFile = Join-Path $TestDrive 'tpm-fix110a-crt-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:F110RealWrite = (Get-Command -Name Write-TpmAtomicTextFile -CommandType Function).ScriptBlock
    $script:F110Utf8 = New-Object System.Text.UTF8Encoding $false

    function New-F110Profile {
        $folder = Join-Path $TestDrive ('f110-crt-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        [void][System.IO.Directory]::CreateDirectory($folder)
        $path = Join-Path $folder 'Game.xml'
        $lines = @(
            '<?xml version="1.0" encoding="utf-8"?>',
            '<GameProfile>',
            '  <GameName>Fixture</GameName>',
            '  <ConfigValues>',
            '    <FieldInformation>',
            '      <CategoryName>Video</CategoryName>',
            '      <FieldName>CRT Shader</FieldName>',
            '      <FieldValue>Lottes</FieldValue>',
            '    </FieldInformation>',
            '  </ConfigValues>',
            '</GameProfile>'
        )
        [System.IO.File]::WriteAllText($path, (($lines -join "`r`n") + "`r`n"), $script:F110Utf8)
        return $path
    }
}

Describe 'FIX110A S-5: Write-TpmAtomicTextFile reports the temp it created and kept' {
    BeforeEach { Mock Write-Log {} }

    It 'reports nothing after a good write' {
        # Mutation: always add the temp path -> a finished write reports a path that no longer exists.
        $path = New-F110Profile
        $kept = New-Object 'System.Collections.Generic.List[string]'
        Write-TpmAtomicTextFile -Path $path -Text 'new text' -RetainedTempPaths $kept
        $kept.Count | Should -Be 0
        [System.IO.File]::ReadAllText($path) | Should -BeExactly 'new text'
    }

    It 'reports nothing when a failed write removed its own temp' {
        # Mutation: report the temp before the writer's own clean-up ran -> a removed file is reported.
        $path = New-F110Profile
        $kept = New-Object 'System.Collections.Generic.List[string]'
        { Write-TpmAtomicTextFile -Path $path -Text 'new text' -Validate { param($t) $false } -RetainedTempPaths $kept } | Should -Throw
        $kept.Count | Should -Be 0
    }

    It 'reports the exact path of a temp it had to keep' {
        # Mutation: do not report the kept temp (or report another path) -> the caller cannot tell which file is the writer's.
        $path = New-F110Profile
        $kept = New-Object 'System.Collections.Generic.List[string]'
        Mock Invoke-TpmAtomicFileReplace {
            [System.IO.File]::Delete($Destination)
            throw (New-Object System.IO.IOException 'simulated ReplaceFile failure')
        }
        { Write-TpmAtomicTextFile -Path $path -Text 'new text' -RetainedTempPaths $kept } | Should -Throw
        $kept.Count | Should -Be 1
        [System.IO.Path]::GetFileName($kept[0]) | Should -Match ('^Game\.xml\.[0-9a-f]{32}\.tmp$')
        [System.IO.File]::ReadAllText($kept[0]) | Should -BeExactly 'new text'
    }
}

Describe 'FIX110A S-5: the native-CRT clean-up removes only the temp files the writer reported' {
    BeforeEach {
        Mock Write-Log {}
        $script:F110Path = New-F110Profile
        $script:F110Own = $script:F110Path + '.' + ('b' * 32) + '.tmp'
        $script:F110Foreign = $script:F110Path + '.' + ('c' * 32) + '.tmp'
    }

    It 'removes its own temp and keeps another writer''s temp that appeared during the write' {
        # Mutation: choose the files to remove by a before/after folder listing again -> the other writer's temp (new since the listing) is deleted.
        $original = [System.IO.File]::ReadAllBytes($script:F110Path)
        $script:F110Calls = 0
        Mock Write-TpmAtomicTextFile {
            $script:F110Calls++
            if ($script:F110Calls -eq 1) {
                [System.IO.File]::WriteAllText($Path, 'partial garbage', $script:F110Utf8)
                [System.IO.File]::WriteAllText($script:F110Own, 'leftover of the failed write', $script:F110Utf8)
                $RetainedTempPaths.Add($script:F110Own)
                # Another atomic writer's temp appears while this write is in progress; it is not reported by this writer.
                [System.IO.File]::WriteAllText($script:F110Foreign, 'someone else''s unpublished content', $script:F110Utf8)
                throw 'simulated failure after the previous file was removed'
            }
            & $script:F110RealWrite @PesterBoundParameters
        }
        $result = Set-TpmReShadeNativeCrtOff -ProfilePath $script:F110Path -FieldPath 'Video / CRT Shader' -ExpectedValue 'Lottes' -OffValue 'None'
        $result.RolledBack | Should -BeTrue
        [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($script:F110Path)) | Should -BeExactly ([System.Convert]::ToBase64String($original))
        Test-Path -LiteralPath $script:F110Own | Should -BeFalse
        Test-Path -LiteralPath $script:F110Foreign | Should -BeTrue
        [System.IO.File]::ReadAllText($script:F110Foreign) | Should -BeExactly 'someone else''s unpublished content'
        @($result.TempRemoved) | Should -Be @($script:F110Own)
        @($result.TempKept).Count | Should -Be 0
    }

    It 'removes nothing when the writer reported nothing, even if a similar file exists' {
        # Mutation: remove every "<profile>.<32 hex>.tmp" beside the profile -> the similar file is deleted.
        [System.IO.File]::WriteAllText($script:F110Foreign, 'not reported by the writer', $script:F110Utf8)
        Mock Write-TpmAtomicTextFile { throw 'simulated failure before anything was written' }
        $result = Set-TpmReShadeNativeCrtOff -ProfilePath $script:F110Path -FieldPath 'Video / CRT Shader' -ExpectedValue 'Lottes' -OffValue 'None'
        $result.Succeeded | Should -BeFalse
        Test-Path -LiteralPath $script:F110Foreign | Should -BeTrue
        @($result.TempRemoved).Count | Should -Be 0
    }

    It 'keeps and names a temp it cannot judge when even the rollback fails' {
        # Mutation: delete the reported temp of an unverified rollback -> the only copy of the new content is gone.
        Mock Write-TpmAtomicTextFile {
            [System.IO.File]::WriteAllText($Path, 'partial garbage', $script:F110Utf8)
            [System.IO.File]::WriteAllText($script:F110Own, 'maybe the only copy of the new content', $script:F110Utf8)
            if (-not $RetainedTempPaths.Contains($script:F110Own)) { $RetainedTempPaths.Add($script:F110Own) }
            throw 'simulated failure'
        }
        $result = Set-TpmReShadeNativeCrtOff -ProfilePath $script:F110Path -FieldPath 'Video / CRT Shader' -ExpectedValue 'Lottes' -OffValue 'None'
        $result.NeedsRestore | Should -BeTrue
        Test-Path -LiteralPath $script:F110Own | Should -BeTrue
        @($result.TempKept) | Should -Be @($script:F110Own)
    }
}
