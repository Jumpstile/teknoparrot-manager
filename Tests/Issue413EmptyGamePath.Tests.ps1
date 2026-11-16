#Requires -Modules Pester
# #413: a game whose profile is not linked to a game file yet must not stop AutoSync from extracting it.

Describe 'AutoSync registered-executable check (#413)' {
    BeforeAll {
        $text = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'))
        $s = $text.IndexOf('$registeredGamePath = ''''')
        $script:block = $text.Substring($s, 2600)
    }

    It 'treats an empty or missing game path as "nothing registered", not as an error' {
        $script:block | Should -Not -Match "throw 'Registered executable path is missing\.'"
        $script:block | Should -Match '\$registeredPathNode = \$null'
    }

    It 'only reads and checks a registered path when the profile has one' {
        $script:block | Should -Match 'if \(\$null -ne \$registeredPathNode\) \{ \$registeredGamePath = '
        $script:block | Should -Match 'if \(\$registeredGamePath -and -not \(Test-Path'
    }

    It 'still refuses a registered file that is missing and not inside the new folder' {
        $script:block | Should -Match "throw 'Registered executable path could not be verified\.'"
    }

    It 'says the real reason in the log' {
        $script:block | Should -Match "archive-root verification \(' \+ \`$_\.Exception\.Message"
    }
}