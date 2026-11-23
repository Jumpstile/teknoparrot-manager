#Requires -Module Pester

# Changelog format guards (first written for FIX112, rewritten when the changelog became one short plain-words history).
#   The changelog must not name a private computer, must be plain ASCII with Windows line endings, and must list the
#   versions newest first with exactly one heading each.
# What this CANNOT prove: that the wording of an entry is correct for the product behavior; that is a review job.

BeforeAll {
    $root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:F112ChangelogPath = Join-Path $root 'TeknoParrot-Manager-CHANGELOG.txt'
    $script:F112Bytes = [IO.File]::ReadAllBytes($script:F112ChangelogPath)
    $script:F112Text = [Text.Encoding]::GetEncoding('iso-8859-1').GetString($script:F112Bytes)
    $script:F112Lines = $script:F112Text -split "`r`n"
}

Describe 'changelog format' {
    It 'names no private computer' {
        # Mutation: write either computer name into the changelog.
        # The names are built from pieces so that this test file does not name the computers itself.
        $machineName = 'ARC' + 'ADE'
        $otherMachineName = 'MEGA' + 'TRON-' + 'NEW'
        $script:F112Text | Should -Not -MatchExactly ('\b' + $machineName + '\b')
        $script:F112Text | Should -Not -Match ('(?i)' + $otherMachineName)
    }

    It 'is plain ASCII' {
        # Mutation: paste a curly quote or dash into the changelog.
        $bad = @($script:F112Bytes | Where-Object { $_ -gt 127 })
        $bad.Count | Should -Be 0
    }

    It 'uses Windows line endings only' {
        # Mutation: save the changelog with bare line feeds.
        [regex]::Matches($script:F112Text, "(?<!`r)`n").Count | Should -Be 0
        [regex]::Matches($script:F112Text, "`r(?!`n)").Count | Should -Be 0
    }

    It 'lists each version once, newest first: RC9.1, RC9, RC8.4, RC8.3, RC8.2, RC8.1, RC7, RC6, RC5, RC4, RC3, RC2.1, RC2' {
        # Mutation: move the RC8.1 block below RC7, or add a second RC7 heading.
        $previous = -1
        foreach ($tag in @('RC9.1', 'RC9', 'RC8.4', 'RC8.3', 'RC8.2', 'RC8.1', 'RC7', 'RC6', 'RC5', 'RC4', 'RC3', 'RC2.1', 'RC2')) {
            $pattern = '^  v1\.0 ' + [regex]::Escape($tag) + '(\s|$)'
            $hits = @(for ($i = 0; $i -lt $script:F112Lines.Count; $i++) { if ($script:F112Lines[$i] -match $pattern) { $i } })
            $hits.Count | Should -Be 1 -Because "$tag must have exactly one heading"
            $hits[0] | Should -BeGreaterThan $previous -Because "$tag must come after the newer versions"
            $previous = $hits[0]
        }
    }

    It 'lists RC8.1 as the changes since RC7, RC8.2 since RC8.1, RC8.3 since RC8.2, RC8.4 since RC8.3, RC9 since RC8.4, RC9.1 since RC9, and gives RC8 no heading of its own' {
        # RC8 was a tester-only build that was never published; its changes belong to RC8.1. Final Version 1.0 comes later.
        # Mutation: add a "v1.0 RC8" heading, drop the RC9 heading, or say RC8.1 changed "since RC8".
        @($script:F112Lines | Where-Object { $_ -match '^  v1\.0 RC8(\s|$)' }).Count | Should -Be 0
        @($script:F112Lines | Where-Object { $_ -match '^  v1\.0 RC9 \(changes since RC8\.4\)\s*$' }).Count | Should -Be 1
        @($script:F112Lines | Where-Object { $_ -match '^  v1\.0 RC9\.1 \(changes since RC9\)\s*$' }).Count | Should -Be 1
        @($script:F112Lines | Where-Object { $_ -match '^  v1\.0 RC8\.1 \(changes since RC7\)\s*$' }).Count | Should -Be 1
        @($script:F112Lines | Where-Object { $_ -match '^  v1\.0 RC8\.2 \(changes since RC8\.1\)\s*$' }).Count | Should -Be 1
        @($script:F112Lines | Where-Object { $_ -match '^  v1\.0 RC8\.3 \(changes since RC8\.2\)\s*$' }).Count | Should -Be 1
        @($script:F112Lines | Where-Object { $_ -match '^  v1\.0 RC8\.4 \(changes since RC8\.3\)\s*$' }).Count | Should -Be 1
    }

    It 'is short (a few pages, not the long technical history)' {
        # Mutation: paste the long technical history back into the shipped changelog.
        # The cap was 500 until RC9. RC9 lists about 200 plain-words lines on top of the published RC8.4 and older sections, which stay as published, so the file is about 665 lines.
        # 720 is the next round number that fits and still catches the long technical history.
        $script:F112Lines.Count | Should -BeLessThan 720
    }
}
