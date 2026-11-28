#Requires -Module Pester

# Issue #408: the AutoSync screen after extraction must say the files were only unpacked and what each choice does.
# Reads the shipped script text only (nothing is run). Not run by the lane author.

BeforeAll {
    $script:f408bSource = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'))
}

Describe 'The screen after extraction says what happened and what each choice does' {
    It 'says unpacked files are not a ready game and asks what to do next' {
        $script:f408bSource | Should -Match 'That only means the files were unpacked, not that the game is ready in TeknoParrot'
        $script:f408bSource | Should -Match 'What should I do next\?'
    }

    It 'keeps the choice keys and says what N and A do' {
        $script:f408bSource | Should -Match '\[N\] New game only \(default\) -- stop here, skip the rest of your games'
        $script:f408bSource | Should -Match '\[A\] Check all games -- also repair your whole library, then set up controls'
        $script:f408bSource | Should -Match '\[B\] Back'
        $script:f408bSource | Should -Match "-Choices @\('N', 'A', 'B'\)"
    }
}
