#Requires -Module Pester

# FIX401: the PostgreSQL repair message must be true. Reads the script text only; nothing is run.
Describe 'Fix401 PostgreSQL repair message' {
    BeforeAll {
        $script:Text = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1') -Raw
    }
    It 'says Nothing was changed only when the helper reported NothingElseChanged' {
        $script:Text | Should -Match "NothingElseChanged -eq \`$true\) \{ 'Nothing was changed\.' \} else \{ 'Some things may already have been changed \(see View Log\)\.' \}"
        $script:Text | Should -Not -Match 'The reason is shown above\. Nothing was changed\.'
    }
}
