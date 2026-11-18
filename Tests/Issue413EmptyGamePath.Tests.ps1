#Requires -Modules Pester
# #413: a game whose profile is not linked to a game file yet must not stop AutoSync from extracting it.

Describe 'AutoSync registered-executable check (#413)' {
    BeforeAll {
        $text = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'))
        $s = $text.IndexOf('$registeredGamePath = ''''')
        $script:block = $text.Substring($s, 3800)
    }

    It 'treats an empty or missing game path as "nothing registered", not as an error' {
        $script:block | Should -Not -Match "throw 'Registered executable path is missing\.'"
        $script:block | Should -Match '\$registeredPathNode = \$null'
    }

    It 'only reads and checks a registered path when the profile has one' {
        $script:block | Should -Match 'if \(\$null -ne \$registeredPathNode\) \{ \$registeredGamePath = '
        $script:block | Should -Match 'if \(\$registeredGamePath -and -not \(Test-Path'
    }

    It 'ignores a saved game file that is missing at an old location only when a new folder is being made' {
        $script:block | Should -Match 'missing at its old location'
        $script:block | Should -Match "throw 'Registered executable path could not be verified\.'"
    }

    It 'says the real reason in the log' {
        $script:block | Should -Match "archive-root verification \(' \+ \`$_\.Exception\.Message"
    }
}