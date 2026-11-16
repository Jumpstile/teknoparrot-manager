#Requires -Module Pester
# FIX89 group E: regression tests for two screen defects found by the FIX88 test run.
#  1. A details row whose label is wider than the label column ("Verified physical bindings") printed its value
#     glued to the colon ("bindings:0").
#  2. The PostgreSQL setup result screen counted every wrapped paragraph as one line, so on a narrow console
#     the paragraphs ran together (15 lines in a row), and a paragraph that is longer than five lines on its own
#     was never split.
# The production script is parsed and only the named functions are dot-sourced. Only console output is intercepted;
# every value is synthetic.
BeforeAll {
    $sourcePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'TeknoParrot-Manager.ps1'
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { throw "Production parse failed: $($errors -join '; ')" }
    $wanted = @(
        'Show-TpmDetailBlocks', 'Write-TpmLabelValue', 'Write-TpmText', 'Split-TextForMenuWidth', 'Get-TpmResetRestoreLineWidth',
        'Get-TpmTransactionField', 'Get-TpmShortParagraphs', 'Write-TpmPostgresSetupResult', 'Write-TpmPostgresSetupResultLog',
        'Get-TpmPostgresSetupGames', 'Get-TpmPostgresSetupGameName', 'Get-TpmPostgresSetupOutcomeLine', 'Join-TpmPostgresSetupNames'
    )
    $functions = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Where-Object { $wanted -contains $_.Name })
    foreach ($name in $wanted) {
        if (@($functions | Where-Object Name -eq $name).Count -ne 1) { throw "Expected one production function: $name" }
    }
    $functionPath = Join-Path $TestDrive 'fix89-e-functions.ps1'
    [System.IO.File]::WriteAllText($functionPath, (($functions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"))
    . $functionPath
    function Write-Log { param([string]$msg) }
    function Get-ConsoleContentWidth { return [int]$script:E89Width }

    # The longest stretch of lines with text and no blank line between them.
    function Get-E89LongestRun {
        param([string[]]$Lines)
        $longest = 0
        $run = 0
        foreach ($line in @($Lines)) {
            if ([string]::IsNullOrWhiteSpace($line)) { $run = 0 } else { $run++; if ($run -gt $longest) { $longest = $run } }
        }
        return $longest
    }

    # The six-game library of the FIX71 tests: four games created from a backup, two that already had a database.
    function New-E89PostgresResult {
        $games = @(
            [pscustomobject]@{ Key = 'A'; Name = 'Golden Tee Live 2019'; DbName = 'DbA'; Outcome = 'CreatedFromBackup' },
            [pscustomobject]@{ Key = 'B'; Name = 'Power Putt Live 2012'; DbName = 'DbB'; Outcome = 'AlreadyExisted' },
            [pscustomobject]@{ Key = 'C'; Name = 'Target Toss Pro Bags'; DbName = 'DbC'; Outcome = 'AlreadyExisted' },
            [pscustomobject]@{ Key = 'D'; Name = 'Power Putt Live 2013'; DbName = 'DbD'; Outcome = 'CreatedFromBackup' },
            [pscustomobject]@{ Key = 'E'; Name = 'Silver Strike Bowling Live'; DbName = 'DbE'; Outcome = 'CreatedFromBackup' },
            [pscustomobject]@{ Key = 'F'; Name = 'Target Toss Pro Lawndarts'; DbName = 'DbF'; Outcome = 'CreatedFromBackup' }
        )
        return [pscustomobject]@{
            Configured = 6; DbCreated = 3; AlreadyConfigured = 2; PassKeptProfiles = @(); GameOutcomes = $games
            Warnings = @(); FinalVerification = [pscustomobject]@{ Checks = @() }; RecoveryActions = @()
        }
    }
}

Describe 'FIX89 details rows with a long label' {
    BeforeEach {
        $script:E89Width = 80
        $script:E89Screen = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { [void]$script:E89Screen.Add([string]($Object -join ' ')) }
    }

    It 'keeps a space after a label that is wider than the label column, and keeps short labels aligned' {
        # Mutation: pad "Label:" to the column width without a space after the colon -> "Verified physical bindings:0".
        $blocks = @(
            @{ Heading = 'Counts'; Lines = @('Verified physical bindings: 0 (nothing was tested).', 'Games with controls copied: 2', 'Games failed: 1') },
            @{ Heading = 'Saved copy'; Lines = @('Folder: C:\x', 'To go back: Use Restore backup.') }
        )
        Show-TpmDetailBlocks -Blocks $blocks
        $lines = @($script:E89Screen)
        $text = $lines -join "`n"
        $text | Should -Match 'Verified physical bindings: 0 \(nothing was tested\)\.'
        $text | Should -Match 'Games with controls copied: 2'
        $lines | Should -Contain '    Folder:     C:\x'
        $lines | Should -Contain '    To go back: Use Restore backup.'
    }
}

Describe 'FIX89 short paragraphs' {
    It 'keeps whole sentences together up to the line limit and starts a new paragraph after that' {
        # Mutation: split after every sentence, or never split -> two or one paragraphs where three sentences need exactly two.
        $parts = @(Get-TpmShortParagraphs -Text 'First sentence here. Second one here. Third one is here.' -Width 20 -MaxLines 2)
        $parts.Count | Should -Be 2
        $parts[0] | Should -BeExactly 'First sentence here. Second one here.'
        $parts[1] | Should -BeExactly 'Third one is here.'
    }

    It 'returns a text that fits as one paragraph, a too long sentence whole, and nothing for an empty text' {
        # Mutation: cut a sentence in the middle, or return an empty paragraph for an empty text.
        $fits = @(Get-TpmShortParagraphs -Text 'One short sentence. Another short one.' -Width 60 -MaxLines 5)
        $fits.Count | Should -Be 1
        $fits[0] | Should -BeExactly 'One short sentence. Another short one.'
        $long = 'This one sentence is far too long to fit on two lines of twenty columns.'
        $whole = @(Get-TpmShortParagraphs -Text $long -Width 20 -MaxLines 2)
        $whole.Count | Should -Be 1
        $whole[0] | Should -BeExactly $long
        @(Get-TpmShortParagraphs -Text '' -Width 20).Count | Should -Be 0
    }
}

Describe 'FIX89 PostgreSQL result screen on a narrow console' {
    BeforeEach {
        $script:E89Screen = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { [void]$script:E89Screen.Add([string]($Object -join ' ')) }
    }

    It 'never shows more than five text lines in a row and never a line as wide as the console at <Width> columns' -TestCases @(@{ Width = 40 }, @{ Width = 60 }) {
        param($Width)
        # Mutation: count a wrapped paragraph as one line -> the paragraphs run together (15 lines at 40, 9 at 60).
        $script:E89Width = $Width
        Write-TpmPostgresSetupResult -Result (New-E89PostgresResult) -OfferDetails
        $lines = @($script:E89Screen)
        (Get-E89LongestRun -Lines $lines) | Should -BeLessOrEqual 5
        $longest = ($lines | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
        $longest | Should -BeLessThan $Width
        $flat = ($lines -join ' ') -replace '\s+', ' '
        $flat | Should -Match ([regex]::Escape('Ready: Golden Tee Live 2019, Power Putt Live 2013, Silver Strike Bowling Live and Target Toss Pro Lawndarts. The databases were created from the games'' own backups and checked.'))
        $flat | Should -Not -Match '(?i)click yes|TeknoParrot will ask'
    }
}
