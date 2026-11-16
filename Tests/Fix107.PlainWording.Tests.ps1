#Requires -Module Pester

# FIX107 (NEW-N4): a normal screen says what happened and what to do; the technical key stays in the log.
#   Start-up reads TeknoParrot-Manager.overrides.json. An override that names a game family TeknoParrot Manager does not know is ignored.
#   The screen used to print the setting name ("canonicalArchetype", "familyOverride") and the key; now it says the consequence and the
#   next step, and the exact setting and key are only in the log.
# The start-up block is script body, not a function, so the test runs that exact block (taken from the parsed script) against a synthetic
# overrides file in $TestDrive. Nothing else of the product runs.
# What this CANNOT prove: how a real console paints the line.

BeforeAll {
    $scriptPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX107 tests could not parse the production script.' }
    $blocks = @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.IfStatementAst] -and
        $node.Clauses[0].Item1.Extent.Text -ceq 'Test-Path -LiteralPath $overridesPath' -and
        $node.Clauses[0].Item2.Extent.Text -match 'ConvertFrom-Json'
    }, $true))
    if ($blocks.Count -ne 1) { throw ('FIX107 tests expected one overrides loading block, found {0}.' -f $blocks.Count) }
    $script:F107OverridesBlock = $blocks[0].Extent.Text
    $script:F107UnknownFamilyLine = '  A controls override names an unknown game family and was ignored. Check the log before changing it.'

    function Invoke-F107OverridesBlock {
        param([Parameter(Mandatory)][string]$Json)
        $overridesPath = Join-Path $TestDrive ('overrides-' + [guid]::NewGuid().ToString('N') + '.json')
        [System.IO.File]::WriteAllText($overridesPath, $Json)
        $noSyncList = @(); $onlySyncList = @(); $noPropagateList = @(); $forceArchetypeMap = @{}; $familyOverrideMap = @{}
        $canonicalArchetypeMap = @{}; $subFolderMap = @{}; $datFilePath = ''
        $validFamilies = @('button', 'driving', 'lightgun', 'trackball', 'analog', 'spinner')
        . ([scriptblock]::Create($script:F107OverridesBlock))
        return [pscustomobject]@{ Family = $familyOverrideMap; Canonical = $canonicalArchetypeMap }
    }
}

Describe 'FIX107 N4 an unknown override family is explained in plain words' {
    BeforeEach {
        $script:f107Rows = New-Object System.Collections.Generic.List[string]
        $script:f107Log = New-Object System.Collections.Generic.List[string]
        function Write-Log { param([string]$Message) [void]$script:f107Log.Add($Message) }
        function Show-TpmOverridesNotice { param($Counts, $FilePath) }
        Mock Write-Host { [void]$script:f107Rows.Add([string]($Object -join ' ')) }
    }

    It 'says the same plain sentence for an unknown <Setting> family and keeps the setting and the key in the log' -ForEach @(
        @{ Setting = 'canonicalArchetype'; Json = '{"canonicalArchetype":{"bogusfamily":"SomeGame"}}' }
        @{ Setting = 'familyOverride'; Json = '{"familyOverride":{"SomeGame":"bogusfamily"}}' }
    ) {
        # Mutation: print the setting name or the unknown key on the screen again (the old WARNING line) -> the screen shows an implementation term.
        # Mutation: drop the log line of the ignored override -> the exact setting and key are lost.
        $result = Invoke-F107OverridesBlock -Json $Json
        @($script:f107Rows) | Should -Be @($script:f107UnknownFamilyLine)
        (@($script:f107Rows) -join ' ') | Should -Not -Match 'canonicalArchetype|familyOverride|bogusfamily'
        (@($script:f107Log) -join "`n") | Should -Match ([regex]::Escape($Setting))
        (@($script:f107Log) -join "`n") | Should -Match 'bogusfamily'
        $result.Family.Count | Should -Be 0
        $result.Canonical.Count | Should -Be 0
    }

    It 'keeps a known family and prints nothing about it' {
        # Mutation: print the warning for every family -> a correct override looks wrong.
        $result = Invoke-F107OverridesBlock -Json '{"familyOverride":{"SomeGame":"lightgun"},"canonicalArchetype":{"driving":"SomeCar"}}'
        $script:f107Rows.Count | Should -Be 0
        $result.Family['SomeGame'] | Should -BeExactly 'lightgun'
        $result.Canonical['driving'] | Should -BeExactly 'SomeCar'
    }
}
