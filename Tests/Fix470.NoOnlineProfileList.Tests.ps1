#Requires -Module Pester

# The online TeknoParrot profile list is permanently offline. TeknoParrot Manager reads profiles only from the player's own
# GameProfiles folder. Who gets hurt: a player told to expect an online list, or a program that reaches out to a dead address.
# Reads source text only. The TeknoParrotUIThumbnails repository (picture downloads) is a different repository and is allowed.

BeforeAll {
    $script:F470Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:F470Patterns = @(
        '(?i)(api\.github\.com/repos|raw\.githubusercontent\.com|github\.com)/[\w.-]+/TeknoParrotUI(?![A-Za-z0-9_])',
        '(?i)\b(?:api\.github\.com|raw\.githubusercontent\.com)\S*GameProfiles',
        '(?i)\bonline (?:list|profile)',
        '(?i)\b(?:github|remote|downloaded|internet) (?:profile|game) ?list',
        '(?i)\bprofile list (?:online|on github)'
    )
    $files = New-Object System.Collections.Generic.List[string]
    [void]$files.Add((Join-Path $script:F470Root 'TeknoParrot-Manager.ps1'))
    [void]$files.Add((Join-Path $script:F470Root 'README.md'))
    foreach ($dir in @('scripts', '.github\workflows', 'docs')) {
        $path = Join-Path $script:F470Root $dir
        if (Test-Path -LiteralPath $path) {
            foreach ($f in @(Get-ChildItem -LiteralPath $path -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.ps1', '.psm1', '.psd1', '.md', '.txt', '.yml', '.yaml', '.json' })) { [void]$files.Add($f.FullName) }
        }
    }
    $script:F470Files = $files.ToArray()
}

Describe 'No reference to the online TeknoParrot profile list' {
    It 'finds nothing in the script, scripts, workflows, README or docs' {
        # Mutation: add an api.github.com or raw.githubusercontent.com address for the TeknoParrotUI profiles, or write "online list of profiles" in a guide.
        $hits = New-Object System.Collections.Generic.List[string]
        foreach ($file in $script:F470Files) {
            $text = [System.IO.File]::ReadAllText($file)
            foreach ($pattern in $script:F470Patterns) {
                foreach ($m in [regex]::Matches($text, $pattern)) { [void]$hits.Add(($file.Substring($script:F470Root.Length) + ': ' + $m.Value)) }
            }
        }
        $hits.ToArray() | Should -BeNullOrEmpty
    }

    It 'catches the old address and wording when they are planted (the check can fail)' {
        # Mutation: make the patterns match nothing -> the planted text is not reported.
        $planted = @(
            'https://api.github.com/repos/teknogods/TeknoParrotUI/contents/TeknoParrotUi/GameProfiles',
            'https://raw.githubusercontent.com/teknogods/TeknoParrotUI/master/GameProfiles/X.xml',
            'The online list of profiles is used when it can be reached.'
        )
        foreach ($text in $planted) {
            @($script:F470Patterns | Where-Object { $text -match $_ }).Count | Should -BeGreaterThan 0 -Because $text
        }
    }

    It 'allows the picture repository, which is a different repository' {
        # Mutation: widen the first pattern so it also matches TeknoParrotUIThumbnails.
        $allowed = 'https://github.com/teknogods/TeknoParrotUIThumbnails'
        @($script:F470Patterns | Where-Object { $allowed -match $_ }).Count | Should -Be 0
    }
}
