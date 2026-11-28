#Requires -Module Pester

# Issue 275: the advanced-user message must stay reachable. A player (or a cabinet builder) who reads the README, the Quick Start or the
# changelog header must be able to find docs\ADVANCED-USERS.md, and the page must exist.
# Mutation: delete docs\ADVANCED-USERS.md, remove its link from README.md or QUICKSTART.md, or drop the "hides complexity, not detail"
# sentence from the changelog header -> this fails.

BeforeAll {
    $script:f275Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    function script:Read-F275 { param([string]$Relative) [System.IO.File]::ReadAllText((Join-Path $script:f275Root $Relative)) }
}

Describe 'The advanced-user page is linked and announced (issue 275)' {
    It 'has the advanced-user page' {
        Test-Path -LiteralPath (Join-Path $script:f275Root 'docs\ADVANCED-USERS.md') -PathType Leaf | Should -BeTrue
    }

    It 'links the page from the README' {
        (Read-F275 'README.md') | Should -Match '\]\(docs/ADVANCED-USERS\.md\)'
    }

    It 'mentions the page in the Quick Start' {
        (Read-F275 'QUICKSTART.md') | Should -Match 'docs/ADVANCED-USERS\.md'
    }

    It 'says "hides complexity, not detail" and points to the page in the changelog header' {
        $changelog = Read-F275 'TeknoParrot-Manager-CHANGELOG.txt'
        # The header is everything before the first version heading.
        $header = $changelog.Substring(0, $changelog.IndexOf('v1.0 RC9.5'))
        $header | Should -Match 'hides complexity, not detail'
        $header | Should -Match 'docs\\ADVANCED-USERS\.md'
    }
}
