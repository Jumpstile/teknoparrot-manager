#Requires -Module Pester

# TPM Certification Suite Phase 1 (issue #88): idempotency / repeat-run
# coverage. Replaces the specific human-tester behavior of "run it again to
# make sure nothing changed" -- a real user re-running a setup step is not
# an edge case, it is routine, and a state-writing operation that drifts on
# a second identical run (duplicated entries, corrupted structure, doubled
# writes) would be exactly the kind of bug a scripted single-run test never
# catches.
#
# Set-Pcsx2CursorPaths is the target: a real, already-shipped production
# function (the issue #79 pcsx2x6 fix) that rewrites PCSX2.ini's cursor_path
# entries. It is deterministic, has no network dependency, and operates on a
# single file under $TestDrive -- a clean, safe subject for this pattern.
#
# Run with: Invoke-Pester -Path .\Tests\VirtualBetaTester.Idempotency.Tests.ps1

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "..\TeknoParrot-Manager.ps1"
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Failed to parse TeknoParrot-Manager.ps1: $($parseErrors -join '; ')"
    }
    $functionAsts = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $extractedFunctionsPath = Join-Path $TestDrive ("vbt-idempotency-functions-" + [guid]::NewGuid().ToString('N') + '.ps1')
    ($functionAsts | ForEach-Object { $_.Extent.Text }) -join "`n`n" | Set-Content -LiteralPath $extractedFunctionsPath -Encoding utf8
    . $extractedFunctionsPath

    $script:logPath = Join-Path $TestDrive "vbt-idempotency.log"
}

Describe "Virtual Beta Tester: idempotency / repeat-run safety (issue #88 phase 1)" {

    It "Set-Pcsx2CursorPaths produces byte-identical PCSX2.ini content on a second run with the same target paths" {
        $iniPath = Join-Path $TestDrive ("pcsx2-idempotent-" + [guid]::NewGuid().ToString('N') + '.ini')
        @(
            '[Frame]',
            'GS = 1',
            '',
            '[USB Port 1 guncon2]',
            'cursor_path = C:\Old\Legacy\Path\P1.png',
            '',
            '[USB Port 2 guncon2]',
            'cursor_path = C:\Old\Legacy\Path\P2.png'
        ) -join "`r`n" | Set-Content -LiteralPath $iniPath -Encoding utf8

        $p1 = 'C:\TeknoParrot\pcsx2x6\TeknoParrot\crosshairs\P1.png'
        $p2 = 'C:\TeknoParrot\pcsx2x6\TeknoParrot\crosshairs\P2.png'

        Set-Pcsx2CursorPaths -IniPath $iniPath -P1Path $p1 -P2Path $p2
        $afterFirstRun = Get-Content -LiteralPath $iniPath -Raw

        Set-Pcsx2CursorPaths -IniPath $iniPath -P1Path $p1 -P2Path $p2
        $afterSecondRun = Get-Content -LiteralPath $iniPath -Raw

        $afterSecondRun | Should -Be $afterFirstRun -Because "running the same crosshair-path write twice with identical targets must not duplicate or drift cursor_path entries"

        # A real idempotency check, not just "the strings match": confirm there
        # is still exactly one cursor_path line per section, not one appended
        # on top of another.
        $cursorPathLines = @(($afterSecondRun -split "`r`n") | Where-Object { $_ -match '^cursor_path\s*=' })
        $cursorPathLines.Count | Should -Be 2 -Because "two guncon2 sections, one cursor_path line each -- a repeat run must not append a duplicate"
    }

    It "each run still creates its own timestamped backup (backup-before-write is not itself skipped on a repeat run)" {
        $iniPath = Join-Path $TestDrive ("pcsx2-backup-check-" + [guid]::NewGuid().ToString('N') + '.ini')
        @('[USB Port 1 guncon2]', 'cursor_path = old.png') -join "`r`n" | Set-Content -LiteralPath $iniPath -Encoding utf8
        $iniDir = [System.IO.Path]::GetDirectoryName($iniPath)
        $iniName = [System.IO.Path]::GetFileName($iniPath)

        Set-Pcsx2CursorPaths -IniPath $iniPath -P1Path 'p1.png' -P2Path 'p2.png'
        Start-Sleep -Milliseconds 1100  # backup filenames are second-resolution timestamps
        Set-Pcsx2CursorPaths -IniPath $iniPath -P1Path 'p1.png' -P2Path 'p2.png'

        $backups = @(Get-ChildItem -LiteralPath $iniDir -Filter "$iniName.bak_*")
        $backups.Count | Should -Be 2 -Because "backup-before-write is a safety invariant that must hold on every run, including repeat runs -- it must never be silently skipped because the file 'already looks right'"
    }
}
