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
        ($ids | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count | Should -Be 0
        ($ids | Select-Object -Unique).Count | Should -Be $ids.Count
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
}
