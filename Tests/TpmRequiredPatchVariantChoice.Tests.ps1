#Requires -Module Pester

# Who is helped: a player whose game has several patch versions and nothing on the PC says which one (screen size, game region).
BeforeAll {
    . (Join-Path $PSScriptRoot '..\scripts\TpmRequiredPatchEngine.ps1')
    $mainScriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $parseTokens = $null
    $parseErrors = $null
    $mainAst = [System.Management.Automation.Language.Parser]::ParseFile($mainScriptPath, [ref]$parseTokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw 'Unable to parse manager helper source for these tests.' }
    foreach ($functionName in @('Get-TpmSupportNativeType','Get-TpmSupportFinalPathFromHandle','Resolve-TpmSupportExpectedFinalPath','Remove-TpmSupportHandle','Get-TpmFileState','Test-PathInside','Test-TpmNoReparsePath','Test-TpmPathLengthAllowed','Test-TpmPathOverlap','Assert-TpmNoReparseWriteTarget','New-ManagerUpdateBackup','Read-TpmAnswerWithDetails')) {
        $functionAst = $mainAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $functionName }, $true)
        if (-not $functionAst) { throw ('Missing required helper: ' + $functionName) }
        . ([scriptblock]::Create($functionAst.Extent.Text))
    }
    [void](Get-TpmSupportNativeType)
    function Write-Log { param([string]$msg) }
    function Write-TpmText { param([string]$Text, [string]$Color, [string]$Prefix, [int]$Indent, [switch]$BlankBefore, [switch]$BlankAfter, [int]$HangingIndent) [void]$script:vcScreen.Add($Text) }
    function Read-HostSafe { param([string]$Prompt, [string]$Default) return $script:vcAnswer }

    function Get-VcSha256 {
        param([Parameter(Mandatory)][byte[]]$Bytes)
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','') } finally { $sha.Dispose() }
    }

    # One game with two region files in one exclusive group and no hardware predicate (like Chase H.Q. 2).
    function New-VcCase {
        param([Parameter(Mandatory)][string]$Name, [string]$TargetBytes = 'region=UK')
        $root = Join-Path $TestDrive $Name
        $game = Join-Path $root 'g'; $payload = Join-Path $root 'p'; $recovery = Join-Path $root 'r'; $protected = Join-Path $root 'x'
        foreach ($directory in @($game,$payload,$recovery,$protected)) { [void][IO.Directory]::CreateDirectory($directory) }
        $exeBytes = [Text.Encoding]::ASCII.GetBytes('vc synthetic executable; never run')
        [IO.File]::WriteAllBytes((Join-Path $game 's.exe'), $exeBytes)
        $uk = [Text.Encoding]::ASCII.GetBytes('region=UK')
        [IO.File]::WriteAllBytes((Join-Path $game 's.ini'), [Text.Encoding]::ASCII.GetBytes($TargetBytes))
        $beforeHash = Get-VcSha256 $uk
        $entries = foreach ($region in @('usa','japan')) {
            $bytes = [Text.Encoding]::ASCII.GetBytes('region=' + $region)
            [IO.File]::WriteAllBytes((Join-Path $payload ('s.' + $region)), $bytes)
            $hash = Get-VcSha256 $bytes
            $operation = [pscustomobject]@{Type='ReplaceFile'; Target='s.ini'; BeforeSha256=$beforeHash; AfterSha256=$hash; Payload=('s.' + $region); PayloadSha256=$hash}
            [pscustomobject]@{
                Id=('vc-region-' + $region); ProfileId='VcGame'; Executable='s.exe'; ExecutableSha256=(Get-VcSha256 $exeBytes)
                SourceUrl='https://example.invalid/vc'; SourceRevision=('C' * 40); ExclusiveGroup='vc-region'; Operations=@($operation)
            }
        }
        $content = [pscustomobject]@{Schema=3; Entries=@($entries)} | ConvertTo-Json -Depth 8
        return [pscustomobject]@{
            Entries=@($entries); Target=(Join-Path $game 's.ini'); UsaHash=(Get-VcSha256 ([Text.Encoding]::ASCII.GetBytes('region=usa')))
            Inputs=@{ CatalogContent=$content; CatalogSha256=(Get-TpmPatchTextSha256 $content); ProfileId='VcGame'; GameRoot=$game; PayloadRoot=$payload; RecoveryRoot=$recovery; ProtectedRoots=@($protected) }
        }
    }
}

Describe 'A player picks one version of a patch group that nothing else can decide' {
    BeforeEach { $script:vcScreen = New-Object System.Collections.Generic.List[string]; $script:vcAnswer = '' }

    It 'still refuses to guess when no version was chosen, and accepts only an id from that group' {
        $case = New-VcCase 'refuse'
        $plain = Resolve-TpmPatchVariantDecision -Entries $case.Entries -PatchId 'vc-region-usa' -ProfileId 'VcGame' -HardwareEvidence $null
        $plain.Status | Should -BeExactly 'AMBIGUOUS'
        @($plain.VariantIds).Count | Should -Be 2
        (Resolve-TpmPatchVariantDecision -Entries $case.Entries -PatchId 'vc-region-usa' -ProfileId 'VcGame' -HardwareEvidence $null -ChosenId 'not-in-group').Status | Should -BeExactly 'AMBIGUOUS'
        $inputs = $case.Inputs
        (Get-TpmPatchPlan @inputs -PatchId 'vc-region-usa').Status | Should -BeExactly 'Unavailable'
    }

    It 'installs only the chosen version, writes a receipt, and undoes it' {
        $case = New-VcCase 'pick'
        $inputs = $case.Inputs
        $chosen = Resolve-TpmPatchVariantDecision -Entries $case.Entries -PatchId 'vc-region-japan' -ProfileId 'VcGame' -HardwareEvidence $null -ChosenId 'vc-region-usa'
        $chosen.Status | Should -BeExactly 'SELECTED'
        $chosen.SelectedId | Should -BeExactly 'vc-region-usa'
        # The other version is not the chosen one, so it is refused even when asked for by name.
        (Get-TpmPatchPlan @inputs -PatchId 'vc-region-japan' -ChosenVariantId 'vc-region-usa').Status | Should -BeExactly 'Unavailable'
        $applied = Invoke-TpmCatalogPatch @inputs -PatchId 'vc-region-usa' -ChosenVariantId 'vc-region-usa' -Confirm:$false
        $applied.Status | Should -BeExactly 'Applied'
        (Get-FileHash -LiteralPath $case.Target -Algorithm SHA256).Hash | Should -BeExactly $case.UsaHash
        Test-Path -LiteralPath (Join-Path $applied.RecoveryDirectory 'receipt.json') | Should -BeTrue
        (Undo-TpmCatalogPatch @inputs -PatchId 'vc-region-usa' -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false).Status | Should -BeExactly 'Restored'
        [IO.File]::ReadAllText($case.Target) | Should -BeExactly 'region=UK'
    }

    It 'refuses the chosen version when the game file is not the exact original, and leaves it alone' {
        $case = New-VcCase 'wrongbefore' -TargetBytes 'region=edited by the player'
        $inputs = $case.Inputs
        (Get-TpmPatchPlan @inputs -PatchId 'vc-region-usa' -ChosenVariantId 'vc-region-usa').Status | Should -BeExactly 'Unavailable'
        { Invoke-TpmCatalogPatch @inputs -PatchId 'vc-region-usa' -ChosenVariantId 'vc-region-usa' -Confirm:$false } | Should -Throw
        [IO.File]::ReadAllText($case.Target) | Should -BeExactly 'region=edited by the player'
    }

    It 'asks in plain words and returns the picked patch id' {
        $case = New-VcCase 'menu'
        $script:vcAnswer = '2'
        Read-TpmRequiredPatchVariantChoice -Entries $case.Entries -GameName 'Synthetic Game' | Should -BeExactly 'vc-region-japan'
        $screen = @($script:vcScreen) -join "`n"
        $screen | Should -Match 'Only one can be installed'
        $screen | Should -Match 'USA'
        $screen | Should -Match 'Japan'
        $screen | Should -Match 'B\) Back'
    }

    It 'returns nothing when the player goes back or types something that is not in the list' -ForEach @(
        @{ Answer = 'B' }, @{ Answer = '' }, @{ Answer = '9' }, @{ Answer = 'x' }
    ) {
        $case = New-VcCase 'cancel'
        $script:vcAnswer = $Answer
        Read-TpmRequiredPatchVariantChoice -Entries $case.Entries -GameName 'Synthetic Game' | Should -BeExactly ''
    }
}

Describe 'The bundled Drift and Chase H.Q. 2 groups can be chosen from, and the Drift sizes are measured' {
    It 'offers every Drift resolution and both Chase H.Q. 2 regions, with all three Drift files at the measured size' {
        $catalog = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmRequiredPatchRecipes.json') -Raw | ConvertFrom-Json
        $drift = @($catalog.Entries | Where-Object ProfileId -CEQ 'FNFDrift')
        $drift.Count | Should -Be 3
        foreach ($entry in $drift) { $entry.SourceSize | Should -Be 69480448 }
        foreach ($entry in $catalog.Entries | Where-Object ProfileId -CEQ 'ChaseHQ2') { $entry.SourceSize | Should -Be 70 }
        foreach ($pair in @(@('fnf-drift-sdaemon-640x480', 3), @('chase-hq-2-region-usa', 2))) {
            $decision = Resolve-TpmPatchVariantDecision -Entries @($catalog.Entries) -PatchId $pair[0] -ProfileId (@($catalog.Entries | Where-Object Id -CEQ $pair[0])[0].ProfileId) -HardwareEvidence $null
            $decision.Status | Should -BeExactly 'AMBIGUOUS'
            @($decision.VariantIds).Count | Should -Be $pair[1]
        }
    }
}
