#Requires -Module Pester

# Issue #401: a game saved on a drive that is not connected must not print a raw red error for every game in the patch engine.
#   - The path check stops with one plain sentence that names the drive.
#   - The result screen turns that sentence into plain advice that points to the Library health check.
#   - The ZIP folder question says how to skip.
# Only the two functions are loaded from the engine file. Nothing real is read or written.

BeforeAll {
    $enginePath = (Resolve-Path (Join-Path $PSScriptRoot '..\scripts\TpmRequiredPatchEngine.ps1')).Path
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($enginePath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'The engine file could not be parsed.' }
    $wanted = @('Resolve-TpmPatchPath', 'Get-TpmRequiredPatchPlainReason')
    $text = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -in $wanted }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $file = Join-Path $TestDrive 'engine-two-functions.ps1'
    [System.IO.File]::WriteAllText($file, $text, (New-Object System.Text.UTF8Encoding $false))
    . $file
    $script:EngineText = [System.IO.File]::ReadAllText($enginePath)
    $script:FreeLetter = @('Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z') | Where-Object { -not (Test-Path -LiteralPath ($_ + ':\') -ErrorAction SilentlyContinue) } | Select-Object -First 1
}

Describe 'Required patches on a game drive that is not connected (#401)' {
    It 'stops with one plain sentence naming the drive and prints no red error' {
        if (-not $script:FreeLetter) { Set-ItResult -Skipped -Because 'every test drive letter is in use'; return }
        $root = '{0}:\Games\Some Game' -f $script:FreeLetter
        $caught = [ref]''
        # Everything the call prints (including red errors) is collected here; the caught sentence is not printed.
        $printed = & { try { Resolve-TpmPatchPath $root 'game.exe' } catch { $caught.Value = $_.Exception.Message } } 2>&1
        $caught.Value | Should -Be ('The drive {0}: is not connected.' -f $script:FreeLetter)
        @($printed | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count | Should -Be 0
    }

    It 'turns that sentence into plain advice that points to the Library health check' {
        $plain = Get-TpmRequiredPatchPlainReason -Status 'FAILED' -Reason 'The drive L: is not connected.'
        $plain | Should -Match 'not connected'
        $plain | Should -Match 'Library health check'
    }

    It 'tells the user how to skip when the patch ZIP folder is asked for' {
        $script:EngineText | Should -Match 'Press Enter with nothing typed to skip this patch'
    }
}
