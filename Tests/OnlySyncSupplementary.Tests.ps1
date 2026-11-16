#Requires -Module Pester

# The onlySync list in TeknoParrot-Manager.overrides.json is a whitelist of ZIP names. When it has entries, only those ZIPs may be extracted,
# in the main ZIP folder AND in the supplementary folder. An empty list means no filter.
# The decision sits in the main flow, not in a function, so the real if-statement is cut out of the production script and run here.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Could not parse the production script.' }
    $found = @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.IfStatementAst] -and
        $node.Clauses[0].Item1.Extent.Text -match '\$suppValid' -and $node.Clauses[0].Item1.Extent.Text -match '\$combinedPickerRan' -and
        $node.Clauses[0].Item2.Extent.Text -match '\$onlySyncListSupp'
    }, $true))
    if ($found.Count -ne 1) { throw "Expected exactly one supplementary onlySync decision, found $($found.Count)." }
    $script:suppDecision = [scriptblock]::Create($found[0].Extent.Text)

    function Get-SuppList {
        param([bool]$SuppValid, [bool]$PickerRan, $Selection, $Main, $Supp)
        $suppValid = $SuppValid; $combinedPickerRan = $PickerRan; $autoSyncSelection = $Selection
        $onlySyncList = $Main; $onlySyncListSupp = $Supp
        . $script:suppDecision
        return ,$onlySyncListSupp
    }
}

Describe 'onlySync and the supplementary ZIP folder' {
    It 'limits the supplementary folder to the listed ZIPs' {
        # Mutation: set the supplementary list to @() (no filter) -> every supplementary ZIP is extracted although onlySync names one.
        $result = Get-SuppList -SuppValid $true -PickerRan $false -Selection $null -Main @('GoldenTee') -Supp $null
        $result | Should -Be @('GoldenTee')
    }

    It 'keeps no filter when onlySync is empty' {
        $result = Get-SuppList -SuppValid $true -PickerRan $false -Selection $null -Main @() -Supp $null
        @($result).Count | Should -Be 0
        $null -ne $result | Should -BeTrue
    }

    It 'leaves the supplementary list alone when the picker or the preview already chose it' {
        (Get-SuppList -SuppValid $true -PickerRan $true -Selection $null -Main @('A') -Supp @('B')) | Should -Be @('B')
        $null -eq (Get-SuppList -SuppValid $true -PickerRan $true -Selection $null -Main @('A') -Supp $null) | Should -BeTrue
    }
}
