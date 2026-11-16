#Requires -Module Pester

Describe "Human-use simulation metadata" {
    It "has the human-use simulation plan and scenario dataset" {
        (Test-Path -LiteralPath (Join-Path $PSScriptRoot "..\docs\HUMAN-USE-SIMULATION-PLAN.md") -PathType Leaf) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $PSScriptRoot "..\testdata\human-use-scenarios.json") -PathType Leaf) | Should -Be $true
    }

    It "has parseable human-use scenarios with unique ids" {
        $scenarioPath = Join-Path $PSScriptRoot "..\testdata\human-use-scenarios.json"
        $scenarios = Get-Content -LiteralPath $scenarioPath -Raw | ConvertFrom-Json
        @($scenarios).Count | Should -BeGreaterThan 0

        $ids = @($scenarios | ForEach-Object { $_.id })
        @($ids | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count | Should -Be 0
        @($ids | Select-Object -Unique).Count | Should -Be $ids.Count
    }

    It "requires core usability fields on every human-use scenario" {
        $scenarioPath = Join-Path $PSScriptRoot "..\testdata\human-use-scenarios.json"
        $scenarios = Get-Content -LiteralPath $scenarioPath -Raw | ConvertFrom-Json

        foreach ($scenario in $scenarios) {
            [string]::IsNullOrWhiteSpace($scenario.id) | Should -Be $false
            [string]::IsNullOrWhiteSpace($scenario.journey) | Should -Be $false
            [string]::IsNullOrWhiteSpace($scenario.goal) | Should -Be $false
            $null -eq $scenario.requiredPhrases | Should -Be $false
            $null -eq $scenario.forbiddenPhrases | Should -Be $false
            $scenario.PSObject.Properties.Name | Should -Contain 'expectedStateChange'
        }
    }

    It "requires every human-use scenario to check either helpful wording or forbidden wording" {
        $scenarioPath = Join-Path $PSScriptRoot "..\testdata\human-use-scenarios.json"
        $scenarios = Get-Content -LiteralPath $scenarioPath -Raw | ConvertFrom-Json

        foreach ($scenario in $scenarios) {
            (@($scenario.requiredPhrases).Count + @($scenario.forbiddenPhrases).Count) | Should -BeGreaterThan 0
        }
    }

    # FIX131 S15: a scenario whose required phrase is not in the product can never fail and proves nothing (the postgres-guided-recovery
    # scenario asked for a password-repair prompt that FIX95 removed). Every required phrase must appear in a string the product can show:
    # the string tokens (single quoted, double quoted, here-strings) of the main script and of every module under scripts and tools.
    # Mutation: change any required phrase in testdata\human-use-scenarios.json to wording the product does not have (the original
    # "Fix it now?" is such a phrase), or reword the product line it came from; the phrase is then reported as missing.
    It "finds every required phrase of every human-use scenario in the product's own text" {
        $root = Split-Path -Parent $PSScriptRoot
        $files = @((Join-Path $root 'TeknoParrot-Manager.ps1')) + @(Get-ChildItem -LiteralPath (Join-Path $root 'scripts'), (Join-Path $root 'tools') -Filter '*.psm1' -File | ForEach-Object { $_.FullName })
        $stringKinds = @('StringLiteral', 'StringExpandable', 'HereStringLiteral', 'HereStringExpandable')
        $text = New-Object System.Text.StringBuilder
        foreach ($file in $files) {
            $tokens = $null
            $parseErrors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$parseErrors)
            @($parseErrors).Count | Should -Be 0 -Because $file
            foreach ($token in $tokens) {
                if ($stringKinds -contains [string]$token.Kind) { [void]$text.AppendLine([string]$token.Value) }
            }
        }
        $productText = $text.ToString()
        $scenarios = Get-Content -LiteralPath (Join-Path $root 'testdata\human-use-scenarios.json') -Raw | ConvertFrom-Json

        $missing = New-Object System.Collections.Generic.List[string]
        foreach ($scenario in $scenarios) {
            foreach ($phrase in @($scenario.requiredPhrases)) {
                if (-not $productText.Contains([string]$phrase)) { [void]$missing.Add(('{0}: {1}' -f $scenario.id, $phrase)) }
            }
        }
        $missing.ToArray() | Should -BeNullOrEmpty
    }
}
