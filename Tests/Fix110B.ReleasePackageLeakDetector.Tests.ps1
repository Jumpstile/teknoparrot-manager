#Requires -Module Pester

# FIX110B (S-13, tooling side): the release package leak detector is generic.
#   - It carries no personal, machine or share name. It looks for the SHAPE of a private path: a user profile folder
#     (C:\Users\<name>, /Users/<name>, /home/<name>), a UNC share (\\host\share, also JSON-escaped), a private IP address.
#   - A narrow allowlist of placeholder names (Public, Default, Default User, All Users, Shared, Example, User, Username,
#     postgres and the <user> / %USERNAME% / ... forms) may appear in examples.
#   - SVG files are scanned like the other packaged text files (an editor can store the author's path inside an SVG).
# All identities below are made up. None of them is the account that runs the tests.
# What this CANNOT prove: that every private identifier has a recognizable shape. A name that is not part of a path needs
# TPM_PACKAGE_PRIVATE_TOKENS (private names supplied by the release owner outside source control).

BeforeAll {
    $script:f110RepoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:f110RepoRoot 'scripts/TPMReleasePackage.Core.psm1') -Force
    $script:f110SavedTokens = $env:TPM_PACKAGE_PRIVATE_TOKENS
    $env:TPM_PACKAGE_PRIVATE_TOKENS = $null
    $script:f110Patterns = @(InModuleScope 'TPMReleasePackage.Core' { Get-TPMReleasePackagePathLeakPatternsV1 })

    function Get-F110LeakLabels {
        param([Parameter(Mandatory)][string]$Text)
        @($script:f110Patterns | Where-Object { $Text -match $_.Regex } | ForEach-Object { $_.Label } | Select-Object -Unique)
    }
}

AfterAll {
    $env:TPM_PACKAGE_PRIVATE_TOKENS = $script:f110SavedTokens
}

Describe 'FIX110B S-13 package leak detector stays generic' {
    It 'flags a user profile path of any made-up account, on any drive and with any slash style' {
        # Mutation: go back to fixed markers plus the build account's own profile; every made-up account below would pass.
        $leaks = @(
            'C:\Users\Zorblax-Quentin\AppData\Local\Temp\x.txt'
            'D:/Users/Zorblax-Quentin/Documents/x.txt'
            'C:\\Users\\Zorblax-Quentin\\AppData\\Roaming'
            'file:///C:/Users/zorblax/Desktop/x.svg'
            '"C:\Users\Quillon_9\Games"'
        )
        $missed = @($leaks | Where-Object { (Get-F110LeakLabels -Text $_) -cnotcontains 'user-profile-path' })
        $missed | Should -BeNullOrEmpty
    }

    It 'flags /Users/<name> and /home/<name> paths' {
        # Mutation: drop the POSIX pattern; macOS and Linux home folders ship unseen.
        $leaks = @(
            '/Users/zorblax/Library/Preferences/x.plist'
            'path="/home/zorblax-quentin/.config/tool"'
            '(/home/quillon9/games)'
            'cd /Users/zorblax; ls'
        )
        $missed = @($leaks | Where-Object { (Get-F110LeakLabels -Text $_) -cnotcontains 'user-profile-path' })
        $missed | Should -BeNullOrEmpty
    }

    It 'flags a UNC share of any host, also when a JSON file stores every backslash twice' {
        # Mutation: allow only listed host names, or miss the doubled-backslash JSON form.
        $leaks = @(
            '\\zorblax-pc\media\roms'
            '\\\\zorblax-pc\\media\\roms'
            '\\fixture-9\share'
        )
        $missed = @($leaks | Where-Object { (Get-F110LeakLabels -Text $_) -cnotcontains 'unc-share' })
        $missed | Should -BeNullOrEmpty
    }

    It 'would have been missed by the old approach: fixed markers plus the build account profile' {
        # Mutation: none (documents why the fixed-marker approach was replaced). The old checks were two fixed names plus the
        # profile folder of the build account; made-up identities that are not that account never match them.
        $buildProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
        $oldStyle = @('(?i)fixed-marker-one', '(?i)fixed-marker-two')
        if (-not [string]::IsNullOrWhiteSpace($buildProfile)) { $oldStyle += '(?i)' + [regex]::Escape($buildProfile) }
        foreach ($text in @('C:\Users\Zorblax-Quentin\AppData', '/home/zorblax-quentin/.config', '\\zorblax-pc\media\roms')) {
            @($oldStyle | Where-Object { $text -match $_ }).Count | Should -Be 0
            @(Get-F110LeakLabels -Text $text).Count | Should -BeGreaterThan 0
        }
    }

    It 'allows only the documented placeholder names and forms' {
        # Mutation: remove the allowlist (valid examples are refused) or widen it to every name (see the next test).
        $examples = @(
            'C:\Users\<user>\AppData\Local'
            'C:\Users\%USERNAME%\Documents'
            'C:\Users\$env:USERNAME\Documents'
            'C:\Users\...\LaunchBox\Emulators'
            'C:\Users\Public\Games'
            'C:\Users\Default\NTUSER.DAT'
            'C:\Users\<user>\Games'
            'The folder is C:\Users\Example.'
            'C:\Users\Username'
            'C:\Users\postgres'
            '/Users/Shared/Games'
            '/home/user/games'
            '/home/<you>/games'
            'the /Users/ folder and the /home/ folder'
            'https://example.com/home/news and https://example.com/Users/help'
            '\\server\share'
            '\\\\server\\share'
            '\\nas\roms'
            '\\.\pipe\fixture'
            '"Description": "copied to <GameDir>\\Fixture\\crosshairs\\ first"'
            'Windows build 10.0.26100.9711, address 8.8.8.8'
        )
        $flagged = @($examples | Where-Object { @(Get-F110LeakLabels -Text $_).Count -gt 0 })
        $flagged | Should -BeNullOrEmpty
    }

    It 'treats a longer name that merely starts with a placeholder name as a real name' {
        # Mutation: match placeholder names as a prefix; C:\Users\Example-Smith would be accepted.
        $leaks = @('C:\Users\Example-Smith\Games', 'C:\Users\Examples\x', 'C:\Users\Public2\x', '/home/example9/x', 'C:\Users\Example.Smith\x')
        $missed = @($leaks | Where-Object { @(Get-F110LeakLabels -Text $_).Count -eq 0 })
        $missed | Should -BeNullOrEmpty
    }

    It 'treats an ordinary first name as a real name, not a placeholder' {
        # Mutation: put a personal-looking name back into the placeholder allowlist; these would be accepted.
        $leaks = @('C:\Users\Alice\Games', '/home/Alice/games', '/Users/alice/Library')
        $missed = @($leaks | Where-Object { @(Get-F110LeakLabels -Text $_).Count -eq 0 })
        $missed | Should -BeNullOrEmpty
    }
}
