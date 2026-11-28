#Requires -Module Pester

# Who is helped: a Ghost Squad Evolution player who needs the AMD or the Nvidia shader fix from the game's own ZIP.
# Many files, one backup, one undo, and only one of the two sets installed. Synthetic files in TestDrive; the engine is dot-sourced.
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
    # Fixed framework assembly names are required by Windows PowerShell 5.1.
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    function Get-GsSha256 {
        param([Parameter(Mandatory)][byte[]]$Bytes)
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','') } finally { $sha.Dispose() }
    }
    function Get-GsBytes { param([string]$Text) return [Text.Encoding]::ASCII.GetBytes($Text) }

    # Files: shader/s0 and shader/s1 are in both sets (like the 8 shared lit files), s2..s(N-1) are AMD only,
    # and the last AMD file is byte-identical to the game's own file (the recipe skips it).
    function New-GsCase {
        param([Parameter(Mandatory)][string]$Name, [int]$AmdOnly = 3, [string]$ExeText = 'gs synthetic vsg; never run')
        $root = Join-Path $TestDrive $Name
        $game = Join-Path $root 'g'; $payload = Join-Path $root 'p'; $recovery = Join-Path $root 'r'; $protected = Join-Path $root 'x'; $src = Join-Path $root 's'; $temp = Join-Path $root 't'
        foreach ($directory in @($game,$payload,$recovery,$protected,$src,$temp,(Join-Path $game 'shader\unit'))) { [void][IO.Directory]::CreateDirectory($directory) }
        $script:TpmOwnedLayout = [pscustomobject]@{ Root = $root; Temp = $temp }
        $exeBytes = Get-GsBytes 'gs synthetic vsg; never run'
        [IO.File]::WriteAllBytes((Join-Path $game 'vsg'), (Get-GsBytes $ExeText))
        $zipName = 'Ghost Squad Evolution (1.0 Rev A)(2007-02-14)[Sega Lindbergh Red][TP].zip'
        $zip = [IO.Compression.ZipFile]::Open((Join-Path $src $zipName), [IO.Compression.ZipArchiveMode]::Create)
        $names = @('unit/s0.h', 'unit/s1.h') + @(1..$AmdOnly | ForEach-Object { 'only' + $_ + '.h' })
        $files = @{}
        try {
            foreach ($relative in $names) {
                $files[$relative] = @{ Orig = (Get-GsBytes ('original ' + $relative)); Amd = (Get-GsBytes ('amd fix ' + $relative)); Nv = (Get-GsBytes ('nvidia fix ' + $relative)) }
                [IO.File]::WriteAllBytes((Join-Path $game ('shader\' + $relative.Replace('/', '\'))), $files[$relative].Orig)
            }
            # The identical file: its AMD copy equals what the game already has.
            $files['same.h'] = @{ Orig = (Get-GsBytes 'same bytes'); Amd = (Get-GsBytes 'same bytes') }
            [IO.File]::WriteAllBytes((Join-Path $game 'shader\same.h'), $files['same.h'].Orig)
            foreach ($relative in $files.Keys) {
                foreach ($set in @(@('GSEvo_AMD_shaderfix', 'Amd'), @('GSEvo_Nvidia_shaderfix', 'Nv'))) {
                    if (-not $files[$relative].ContainsKey($set[1])) { continue }
                    if ($set[1] -eq 'Nv' -and $relative -notin @('unit/s0.h', 'unit/s1.h')) { continue }
                    $item = $zip.CreateEntry('Patches/' + $set[0] + '/shader/' + $relative)
                    $stream = $item.Open(); try { $stream.Write($files[$relative][$set[1]], 0, $files[$relative][$set[1]].Length) } finally { $stream.Dispose() }
                }
            }
        } finally { $zip.Dispose() }
        $entries = foreach ($set in @(@('amd', 'Amd', 'GSEvo_AMD_shaderfix'), @('nvidia', 'Nv', 'GSEvo_Nvidia_shaderfix'))) {
            $rows = @($files.Keys | Sort-Object | Where-Object { $files[$_].ContainsKey($set[1]) -and (Get-GsSha256 $files[$_].Orig) -ne (Get-GsSha256 $files[$_][$set[1]]) -and ($set[1] -eq 'Amd' -or $_ -in @('unit/s0.h', 'unit/s1.h')) })
            $operations = @($rows | ForEach-Object {
                $after = Get-GsSha256 $files[$_][$set[1]]
                [pscustomobject]@{ Type='ReplaceFile'; Target=('shader/' + $_); BeforeSha256=(Get-GsSha256 $files[$_].Orig); AfterSha256=$after; Payload=('payload/shader/' + $_); PayloadSha256=$after }
            })
            $more = @(1..($rows.Count - 1) | ForEach-Object { [pscustomobject]@{ SourceEntry=('Patches/' + $set[2] + '/shader/' + $rows[$_]); SourceSize=[int64]$files[$rows[$_]][$set[1]].Length } })
            [pscustomobject]@{
                Id=('ghost-squad-evolution-shaderfix-' + $set[0]); ProfileId='GSEVOELF2'; BuildName=$zipName.Substring(0, $zipName.Length - 4); Executable='vsg'; ExecutableSha256=(Get-GsSha256 $exeBytes)
                SourceUrl=''; SourceRevision=''; SourceRole='Main'; SourceSet=$zipName; SourceEntry=('Patches/' + $set[2] + '/shader/' + $rows[0]); SourceSize=[int64]$files[$rows[0]][$set[1]].Length
                SourceSha256=$operations[0].AfterSha256; MoreSourceEntries=$more; ExclusiveGroup='ghost-squad-evolution-shaderfix'; Prerequisites=@(); Operations=$operations
            }
        }
        $content = [pscustomobject]@{ Schema=3; Entries=@($entries) } | ConvertTo-Json -Depth 8
        return [pscustomobject]@{
            Game=$game; Src=$src; Files=$files; Entries=@($entries)
            Inputs=@{ CatalogContent=$content; CatalogSha256=(Get-TpmPatchTextSha256 $content); ProfileId='GSEVOELF2'; GameRoot=$game; PayloadRoot=$payload; RecoveryRoot=$recovery; ProtectedRoots=@($protected) }
        }
    }
    function Get-GsDiskSha256 { param($Case, [string]$Relative) return (Get-FileHash -LiteralPath (Join-Path $Case.Game ('shader\' + $Relative.Replace('/', '\'))) -Algorithm SHA256).Hash }
    function Install-GsChoice {
        param($Case, [string]$Gpu)
        $entry = @($Case.Entries | Where-Object Id -CEQ ('ghost-squad-evolution-shaderfix-' + $Gpu))[0]
        $stage = New-TpmRequiredPatchPayloadStage -Entry $entry -SourceRoot $Case.Src
        $inputs = @{} + $Case.Inputs
        $inputs.PayloadRoot = $stage.Root
        return (Invoke-TpmCatalogPatch @inputs -PatchId $entry.Id -ChosenVariantId $entry.Id -Confirm:$false)
    }
}

Describe 'The Ghost Squad Evolution shader fix, chosen by the player' {
    It 'installs the AMD set, skips the file that is already identical, and keeps the other files' {
        $case = New-GsCase 'amd'
        $applied = Install-GsChoice $case 'amd'
        $applied.Status | Should -BeExactly 'Applied'
        foreach ($relative in @('unit/s0.h', 'unit/s1.h', 'only1.h', 'only2.h', 'only3.h')) { Get-GsDiskSha256 $case $relative | Should -BeExactly (Get-GsSha256 $case.Files[$relative].Amd) }
        Get-GsDiskSha256 $case 'same.h' | Should -BeExactly (Get-GsSha256 $case.Files['same.h'].Orig)
        @($case.Entries | Where-Object Id -CEQ 'ghost-squad-evolution-shaderfix-amd')[0].Operations.Target | Should -Not -Contain 'shader/same.h'
    }

    It 'installs only the Nvidia set when the player picks it' {
        $case = New-GsCase 'nvidia'
        (Install-GsChoice $case 'nvidia').Status | Should -BeExactly 'Applied'
        foreach ($relative in @('unit/s0.h', 'unit/s1.h')) { Get-GsDiskSha256 $case $relative | Should -BeExactly (Get-GsSha256 $case.Files[$relative].Nv) }
        foreach ($relative in @('only1.h', 'only2.h', 'only3.h')) { Get-GsDiskSha256 $case $relative | Should -BeExactly (Get-GsSha256 $case.Files[$relative].Orig) }
    }

    It 'puts every original file back on undo, and refuses the other set while one is installed' {
        $case = New-GsCase 'undo'
        $applied = Install-GsChoice $case 'amd'
        $other = @($case.Entries | Where-Object Id -CEQ 'ghost-squad-evolution-shaderfix-nvidia')[0]
        $inputs = $case.Inputs
        (Get-TpmPatchPlan @inputs -PatchId $other.Id -ChosenVariantId $other.Id).Status | Should -BeExactly 'Unavailable'
        (Undo-TpmCatalogPatch @inputs -PatchId 'ghost-squad-evolution-shaderfix-amd' -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false).Status | Should -BeExactly 'Restored'
        foreach ($relative in @('unit/s0.h', 'unit/s1.h', 'only1.h', 'only2.h', 'only3.h', 'same.h')) { Get-GsDiskSha256 $case $relative | Should -BeExactly (Get-GsSha256 $case.Files[$relative].Orig) }
    }

    It 'refuses a game program that is not the exact one, and changes nothing' {
        $case = New-GsCase 'wrongexe' -ExeText 'some other vsg program'
        $entry = $case.Entries[0]
        $inputs = @{} + $case.Inputs
        $inputs.PayloadRoot = (New-TpmRequiredPatchPayloadStage -Entry $entry -SourceRoot $case.Src).Root
        $plan = Get-TpmPatchPlan @inputs -PatchId $entry.Id -ChosenVariantId $entry.Id
        $plan.Status | Should -BeExactly 'Unavailable'
        $plan.Reason | Should -BeLike '*Executable revision mismatch*'
        { Invoke-TpmCatalogPatch @inputs -PatchId $entry.Id -ChosenVariantId $entry.Id -Confirm:$false } | Should -Throw
        Get-GsDiskSha256 $case 'only1.h' | Should -BeExactly (Get-GsSha256 $case.Files['only1.h'].Orig)
    }

    It 'keeps the receipt of the real 126-file AMD set under the receipt size limit' {
        $case = New-GsCase 'bigamd' -AmdOnly 124
        $applied = Install-GsChoice $case 'amd'
        $applied.Status | Should -BeExactly 'Applied'
        @($case.Entries | Where-Object Id -CEQ 'ghost-squad-evolution-shaderfix-amd')[0].Operations.Count | Should -Be 126
        (Get-Item -LiteralPath (Join-Path $applied.RecoveryDirectory 'receipt.json')).Length | Should -BeLessThan $script:TpmReceiptMaxBytes
    }
}

Describe 'The bundled Ghost Squad Evolution recipes' {
    BeforeAll {
        $script:gsCatalog = Read-TpmRequiredPatchCatalog -ProgramRoot (Join-Path $PSScriptRoot '..')
        $script:gsEntries = @($script:gsCatalog.Entries | Where-Object ProfileId -CEQ 'GSEVOELF2')
    }
    It 'offer an AMD and an Nvidia set of the measured size, as one choice the player makes' {
        $script:gsEntries.Count | Should -Be 2
        $amd = @($script:gsEntries | Where-Object Id -CEQ 'ghost-squad-evolution-shaderfix-amd')[0]
        $nvidia = @($script:gsEntries | Where-Object Id -CEQ 'ghost-squad-evolution-shaderfix-nvidia')[0]
        $amd.Operations.Count | Should -Be 126
        $nvidia.Operations.Count | Should -Be 8
        foreach ($entry in $script:gsEntries) {
            $entry.Executable | Should -BeExactly 'vsg'
            $entry.ExecutableSha256 | Should -BeExactly '2966EED7254B485BD086215DF226240AE97464132714A1A1504C52BA2A9E4815'
            @($entry.MoreSourceEntries).Count | Should -Be ($entry.Operations.Count - 1)
            @($entry.Operations | Where-Object { $_.BeforeSha256 -ieq $_.AfterSha256 }).Count | Should -Be 0
        }
        $decision = Resolve-TpmPatchVariantDecision -Entries @($script:gsCatalog.Entries) -PatchId $amd.Id -ProfileId 'GSEVOELF2' -HardwareEvidence $null
        $decision.Status | Should -BeExactly 'AMBIGUOUS'
        @($decision.VariantIds).Count | Should -Be 2
        (Resolve-TpmPatchVariantDecision -Entries @($script:gsCatalog.Entries) -PatchId $amd.Id -ProfileId 'GSEVOELF2' -HardwareEvidence $null -ChosenId $nvidia.Id).SelectedId | Should -BeExactly $nvidia.Id
    }
    It 'tell AMD players, and only them, to turn on EnableAmdFix' {
        Get-TpmRequiredPatchAfterInstallNote -Entry $script:gsEntries[0] | Should -BeLike '*EnableAmdFix*'
        Get-TpmRequiredPatchAfterInstallNote -Entry $script:gsEntries[1] | Should -BeExactly ''
    }
}
