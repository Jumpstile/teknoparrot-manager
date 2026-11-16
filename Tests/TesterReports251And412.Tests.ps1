#Requires -Modules Pester
# #251: closing the browse window at the game ZIP folder question must ask again, not drop to the menu.
# #412: a support-package item that cannot be collected must say why (log and Details view).

Describe 'Game ZIP folder question asks again (#251)' {
    BeforeAll {
        $text = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'))
        $s = $text.IndexOf('Game ZIP folder (your own game .zip files)')
        $script:ask = $text.Substring($s, 2600)
    }

    It 'loops until a real folder is given, and Q goes back' {
        $script:ask | Should -Match 'while \(\$true\)'
        $script:ask | Should -Match "-eq 'Q'"
        $script:ask | Should -Match 'type B to browse again'
    }

    It 'does not treat a closed browse window as the end of the question' {
        $script:ask | Should -Match 'browse canceled'
        $script:ask | Should -Match 'That folder was not found'
    }

    It 'still stops in unattended runs instead of waiting for a person' {
        ([regex]::Matches($script:ask, 'if \(\$Unattended\) \{ break \}')).Count | Should -Be 2
    }
}

Describe 'Support package says why an item could not be collected (#412)' {
    BeforeAll {
        $script:text = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'))
    }

    It 'logs the real error when a plugin inventory fails' {
        $script:text | Should -Match 'Support plugin inventory for \{0\} failed: \{1\}'
    }

    It 'shows a Why line under each item that could not be collected' {
        $script:text | Should -Match "'  Why: \{0\}'"
    }
}
