#Requires -Module Pester

# Things a person can see or lose: graphics card choice, patch ZIP member names, tooling output.
BeforeAll {
    . (Join-Path $PSScriptRoot '..\scripts\TpmRequiredPatchEngine.ps1')
    $mainScriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $parseTokens = $null
    $parseErrors = $null
    $mainAst = [System.Management.Automation.Language.Parser]::ParseFile($mainScriptPath, [ref]$parseTokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw 'Unable to parse manager helper source for these tests.' }
    foreach ($functionName in @('Get-TpmSupportNativeType','Get-TpmSupportFinalPathFromHandle','Resolve-TpmSupportExpectedFinalPath','Remove-TpmSupportHandle','Get-TpmFileState','Test-PathInside','Test-TpmNoReparsePath','Test-TpmPathLengthAllowed','Test-TpmPathOverlap','Assert-TpmNoReparseWriteTarget','New-ManagerUpdateBackup','Get-DetectedGpuVendor')) {
        $functionAst = $mainAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $functionName }, $true)
        if (-not $functionAst) { throw ('Missing required helper: ' + $functionName) }
        . ([scriptblock]::Create($functionAst.Extent.Text))
    }
    [void](Get-TpmSupportNativeType)

    function Get-DS16BytesSha256 {
        param([Parameter(Mandatory)][byte[]]$Bytes)
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','') } finally { $sha.Dispose() }
    }

    # One recipe with a ReplaceFile and a CreateFile (a grouped, schema 3 transaction); the recovery folder is exactly $RecoveryLength characters long.
    function New-DS16Case {
        param([Parameter(Mandatory)][string]$Name, [int]$RecoveryLength = 0)
        $root = Join-Path $TestDrive $Name
        $game = Join-Path $root 'g'
        $parent = Join-Path $game 'd'
        $payload = Join-Path $root 'p'
        $recovery = Join-Path $root 'r'
        if ($RecoveryLength -gt 0) { $recovery = Join-Path $recovery ('r' * ($RecoveryLength - $recovery.Length - 1)) }
        $protected = Join-Path $root 'x'
        foreach ($directory in @($parent,$payload,$recovery,$protected)) { [void][IO.Directory]::CreateDirectory($directory) }
        $exeBytes = [Text.Encoding]::ASCII.GetBytes('ds16c synthetic executable; never run')
        [IO.File]::WriteAllBytes((Join-Path $game 's.exe'), $exeBytes)
        $createBytes = [Text.Encoding]::ASCII.GetBytes('ds16c created payload')
        [IO.File]::WriteAllBytes((Join-Path $payload 'c.bin'), $createBytes)
        $createHash = Get-DS16BytesSha256 $createBytes
        $beforeBytes = [Text.Encoding]::ASCII.GetBytes('ds16c settings before')
        $afterBytes = [Text.Encoding]::ASCII.GetBytes('ds16c settings after')
        [IO.File]::WriteAllBytes((Join-Path $parent 's.ini'), $beforeBytes)
        [IO.File]::WriteAllBytes((Join-Path $payload 's.new'), $afterBytes)
        $beforeHash = Get-DS16BytesSha256 $beforeBytes
        $afterHash = Get-DS16BytesSha256 $afterBytes
        $create = [pscustomobject]@{Type='CreateFile'; Target='d/c.bin'; BeforeState='Absent'; AfterSha256=$createHash; Payload='c.bin'; PayloadSha256=$createHash}
        $replace = [pscustomobject]@{Type='ReplaceFile'; Target='d/s.ini'; BeforeSha256=$beforeHash; AfterSha256=$afterHash; Payload='s.new'; PayloadSha256=$afterHash}
        $entry = [pscustomobject]@{
            Id='ds16c.group'; ProfileId='DS16C'; Executable='s.exe'; ExecutableSha256=(Get-DS16BytesSha256 $exeBytes)
            SourceUrl='https://example.invalid/ds16c'; SourceRevision=('C' * 40); ExclusiveGroup=''; Operations=@($replace,$create)
        }
        $content = [pscustomobject]@{Schema=3; Entries=@($entry)} | ConvertTo-Json -Depth 8
        $inputs = @{
            CatalogContent=$content; CatalogSha256=(Get-TpmPatchTextSha256 $content); PatchId=$entry.Id; ProfileId='DS16C'
            GameRoot=$game; PayloadRoot=$payload; RecoveryRoot=$recovery; ProtectedRoots=@($protected)
        }
        return [pscustomobject]@{ Inputs=$inputs; SettingsTarget=(Join-Path $parent 's.ini'); CreateTarget=(Join-Path $parent 'c.bin'); BeforeHash=$beforeHash }
    }
}

Describe 'Undo works at the longest recovery folder the engine accepts' {
    # Who gets hurt: a player whose TeknoParrot folder is long. The install was accepted, then the undo restored the files
    # and failed on its own checkpoint path, so the patch could not be undone.
    It 'installs, then undoes and re-installs with the recovery folder at <Length> characters' -TestCases @(
        @{ Length = 152 }
    ) {
        $case = New-DS16Case ('undo' + $Length) -RecoveryLength $Length
        $inputs = $case.Inputs
        $inputs.RecoveryRoot.Length | Should -Be $Length
        $applied = Invoke-TpmCatalogPatch @inputs -Confirm:$false
        $applied.Status | Should -BeExactly 'Applied'
        $undone = Undo-TpmCatalogPatch @inputs -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false
        $undone.Status | Should -BeExactly 'Restored'
        (Get-FileHash -LiteralPath $case.SettingsTarget -Algorithm SHA256).Hash | Should -BeExactly $case.BeforeHash
        Test-Path -LiteralPath $case.CreateTarget | Should -BeFalse
    }
}

Describe 'Two video adapters no longer make the graphics-card patches impossible to install' {
    BeforeAll {
        function New-DS16Evidence {
            param([string[]]$Names)
            $one = ($Names.Count -eq 1)
            [pscustomobject]@{
                Adapters = @($Names | ForEach-Object { [pscustomobject]@{ Name = $_ } })
                ActiveAdapterIndex = $(if ($one) { 0 } else { $null }); ActiveAdapterName = $(if ($one) { $Names[0] } else { $null })
                ActiveGpuConfidence = $(if ($one) { 'INFERRED' } else { 'UNKNOWN' }); MultiGpuAmbiguous = (-not $one)
            }
        }
        function Write-TpmText { param([string]$Text, [string]$Color, [switch]$BlankBefore, [switch]$BlankAfter, [int]$HangingIndent) [void]$script:ds16Screen.Add($Text) }
        function Read-HostSafe { param([string]$Prompt, [string]$Default) $script:ds16Prompts++; return $script:ds16Answer }
        $script:ds16Amd = [pscustomobject]@{ Id = 'ds16.amd'; ProfileId = 'DS16'; ExecutableSha256 = ('A' * 64); ExclusiveGroup = 'ds16.gpu'; HardwarePredicate = [pscustomobject]@{ Vendor = 'AMD' } }
        $script:ds16Nvidia = [pscustomobject]@{ Id = 'ds16.nvidia'; ProfileId = 'DS16'; ExecutableSha256 = ('A' * 64); ExclusiveGroup = 'ds16.gpu'; HardwarePredicate = [pscustomobject]@{ Vendor = 'NVIDIA' } }
        function Get-DS16Decision {
            param($Evidence)
            Resolve-TpmPatchVariantDecision -Entries @($script:ds16Amd, $script:ds16Nvidia) -PatchId 'ds16.nvidia' -ProfileId 'DS16' -HardwareEvidence $Evidence
        }
    }
    BeforeEach { $script:ds16Screen = New-Object System.Collections.Generic.List[string]; $script:ds16Prompts = 0; $script:ds16Answer = '' }

    # Who gets hurt: anyone whose PC lists a Microsoft Basic Display or remote adapter next to the real card. Every NVIDIA/AMD shader patch was refused.
    It 'ignores the basic display adapter and uses the one real card without asking' {
        $evidence = Resolve-TpmPatchHardwareEvidence -Evidence (New-DS16Evidence @('Microsoft Basic Display Adapter', 'NVIDIA GeForce RTX 4060'))
        $decision = Get-DS16Decision $evidence
        $decision.Status | Should -BeExactly 'SELECTED'
        $decision.SelectedId | Should -BeExactly 'ds16.nvidia'
        $script:ds16Prompts | Should -Be 0
    }

    It 'does not ask when the real cards are all the same make' {
        $evidence = Resolve-TpmPatchHardwareEvidence -Evidence (New-DS16Evidence @('NVIDIA GeForce GTX 1080', 'NVIDIA GeForce RTX 4060', 'Remote Desktop Virtual Display'))
        (Get-DS16Decision $evidence).SelectedId | Should -BeExactly 'ds16.nvidia'
        $script:ds16Prompts | Should -Be 0
    }

    It 'asks once, in plain words, when the real cards are different makes, and uses the card the person picks' {
        $script:ds16Answer = '1'
        $evidence = Resolve-TpmPatchHardwareEvidence -Evidence (New-DS16Evidence @('Intel(R) UHD Graphics', 'NVIDIA GeForce RTX 4060'))
        $script:ds16Prompts | Should -Be 1
        (@($script:ds16Screen) -join "`n") | Should -Match 'NVIDIA GeForce RTX 4060'
        # Card 1 is the Intel one, and no variant here is made for Intel.
        (Get-DS16Decision $evidence).Status | Should -BeExactly 'NOT_APPLICABLE'
        $script:ds16Answer = '2'
        $evidence = Resolve-TpmPatchHardwareEvidence -Evidence (New-DS16Evidence @('Intel(R) UHD Graphics', 'NVIDIA GeForce RTX 4060'))
        (Get-DS16Decision $evidence).SelectedId | Should -BeExactly 'ds16.nvidia'
    }

    It 'keeps the safe refusal, with a plain next step, when the person does not pick a card' -ForEach @(
        @{ Answer = '' }
        @{ Answer = '9' }
    ) {
        $script:ds16Answer = $Answer
        $evidence = Resolve-TpmPatchHardwareEvidence -Evidence (New-DS16Evidence @('Intel(R) UHD Graphics', 'NVIDIA GeForce RTX 4060'))
        $decision = Get-DS16Decision $evidence
        $decision.Status | Should -BeExactly 'AMBIGUOUS'
        $decision.SelectedId | Should -BeExactly ''
        (Get-TpmRequiredPatchPlainReason -Status 'BLOCKED' -Reason $decision.Reason) | Should -Match 'more than one graphics card.*Run this again'
    }

    It 'still refuses a card of a make nobody knows, and a PC with only virtual adapters' -ForEach @(
        @{ Names = @('Matrox G200eW', 'Microsoft Basic Display Adapter') }
        @{ Names = @('Microsoft Basic Display Adapter') }
    ) {
        $evidence = Resolve-TpmPatchHardwareEvidence -Evidence (New-DS16Evidence $Names)
        (Get-DS16Decision $evidence).Status | Should -Be 'UNKNOWN'
        $script:ds16Prompts | Should -Be 0
    }
}

Describe 'A patch ZIP is found even when a folder name differs only in letter case' {
    BeforeAll {
        function New-DS16MemberZip {
            param([string]$Path, [string[]]$Names, [byte[]]$Bytes)
            Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
            $stream = [IO.File]::Create($Path)
            try {
                $zip = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create)
                try {
                    foreach ($name in $Names) {
                        $member = $zip.CreateEntry($name).Open()
                        try { $member.Write($Bytes, 0, $Bytes.Length) } finally { $member.Dispose() }
                    }
                } finally { $zip.Dispose() }
            } finally { $stream.Dispose() }
        }
        function New-DS16StageEntry {
            param([string]$SourceSet, [string]$SourceEntry, [byte[]]$Bytes)
            $sha1 = [Security.Cryptography.SHA1]::Create()
            try { $sha1Hex = [BitConverter]::ToString($sha1.ComputeHash($Bytes)).Replace('-', '') } finally { $sha1.Dispose() }
            $hash = Get-DS16BytesSha256 $Bytes
            [pscustomobject]@{
                SourceSet = $SourceSet; SourceEntry = $SourceEntry; SourceSize = $Bytes.Length; SourceSha1 = $sha1Hex; SourceSha256 = $hash
                Operations = @([pscustomobject]@{ Payload = 'payload/a.dll'; PayloadSha256 = $hash; AfterSha256 = $hash })
            }
        }
    }
    BeforeEach {
        $script:ds16Source = Join-Path $TestDrive ('src-' + [guid]::NewGuid().ToString('N'))
        $script:ds16Temp = Join-Path $TestDrive ('tmp-' + [guid]::NewGuid().ToString('N'))
        foreach ($directory in @($script:ds16Source, $script:ds16Temp)) { [void][IO.Directory]::CreateDirectory($directory) }
        $script:TpmOwnedLayout = [pscustomobject]@{ Root = $TestDrive; Temp = $script:ds16Temp }
    }
    AfterEach { $script:TpmOwnedLayout = $null }

    # Who gets hurt: the recipe for Blazing Angels names "Bin/MSVCP71.dll" and the one for Arctic Thunder "Midway Games/...", but the ZIP may
    # spell a folder in lower case. The match was case-sensitive, so that patch could never be installed.
    It 'finds the member whatever its letter case, and still checks size and SHA-256' {
        $bytes = [Text.Encoding]::ASCII.GetBytes('ds16c patch member')
        New-DS16MemberZip -Path (Join-Path $script:ds16Source 'pack.zip') -Names @('bin/a.dll') -Bytes $bytes
        $entry = New-DS16StageEntry -SourceSet 'pack.zip' -SourceEntry 'Bin/a.dll' -Bytes $bytes
        $stage = New-TpmRequiredPatchPayloadStage -Entry $entry -SourceRoot $script:ds16Source
        $stage.Size | Should -Be $bytes.Length
        $wrongHash = New-DS16StageEntry -SourceSet 'pack.zip' -SourceEntry 'Bin/a.dll' -Bytes ([Text.Encoding]::ASCII.GetBytes('ds16c other member'))
        { New-TpmRequiredPatchPayloadStage -Entry $wrongHash -SourceRoot $script:ds16Source } | Should -Throw
    }

    It 'refuses a ZIP that has two members differing only by case' {
        $bytes = [Text.Encoding]::ASCII.GetBytes('ds16c patch member')
        New-DS16MemberZip -Path (Join-Path $script:ds16Source 'two.zip') -Names @('bin/a.dll', 'BIN/a.dll') -Bytes $bytes
        $entry = New-DS16StageEntry -SourceSet 'two.zip' -SourceEntry 'Bin/a.dll' -Bytes $bytes
        { New-TpmRequiredPatchPayloadStage -Entry $entry -SourceRoot $script:ds16Source } | Should -Throw '*absent, duplicated, or has a different size*'
    }

    It 'every one of the 120 recipes pulls a file with the same name as the file it installs' {
        $catalog = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmRequiredPatchRecipes.json') -Raw | ConvertFrom-Json
        @($catalog.Entries).Count | Should -Be 120
        $mismatch = @(foreach ($recipe in @($catalog.Entries)) {
            # The two shader recipes of one game keep the card name on the ZIP member (shader.farc.AMD), so that suffix is ignored.
            $member = [string]$recipe.SourceEntry -replace '\.(AMD|NVIDIA|Intel)$', ''
            $target = [string]$recipe.Operations[0].Target
            if (($member.Split('/')[-1]) -cne ($target.Split('/')[-1]) -and ($member.Split('/')[-1]) -ine ($target.Split('/')[-1])) { $recipe.Id }
        })
        $mismatch | Should -BeNullOrEmpty
    }
}

Describe 'The console preview draws what the window can show, and the release version' {
    BeforeAll {
        $previewPath = Join-Path $PSScriptRoot '..\scripts\Preview-TPM-ConsoleUx.ps1'
        $previewAst = [System.Management.Automation.Language.Parser]::ParseFile($previewPath, [ref]$null, [ref]$null)
        foreach ($functionAst in $previewAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
            . ([scriptblock]::Create($functionAst.Extent.Text))
        }
        $script:DisplayVersion = [regex]::Match([IO.File]::ReadAllText($previewPath), "\`$script:DisplayVersion = '(v[^']+)'").Groups[1].Value
        function Get-DS16PreviewLines {
            param([string]$Layout, [int]$Width)
            @(& $Layout -Width $Width 6>&1 | ForEach-Object { $_.ToString() })
        }
    }

    It 'prints the current version in every layout, never an old one' -ForEach @(
        @{ Layout = 'Write-ReferenceNeon' }, @{ Layout = 'Write-BlockMarquee' }, @{ Layout = 'Write-ArcadeFrame' }, @{ Layout = 'Write-CenteredTerminal' }, @{ Layout = 'Write-CompactReadable' }
    ) {
        $script:DisplayVersion | Should -Match '^v\d'
        $text = (Get-DS16PreviewLines -Layout $Layout -Width 140) -join "`n"
        $text | Should -Match ([regex]::Escape(($script:DisplayVersion -replace '^v', '')))
        $text | Should -Not -Match 'RC[0-7]\b'
    }

    It 'never draws a line wider than an 80-column window: <Layout>' -ForEach @(
        @{ Layout = 'Write-ReferenceNeon' }, @{ Layout = 'Write-BlockMarquee' }, @{ Layout = 'Write-ArcadeFrame' }, @{ Layout = 'Write-CenteredTerminal' }, @{ Layout = 'Write-CompactReadable' }
    ) {
        $lines = Get-DS16PreviewLines -Layout $Layout -Width 80
        $lines.Count | Should -BeGreaterThan 0
        @($lines | Where-Object { $_.Length -gt 80 }) | Should -BeNullOrEmpty
    }

    It 'fits a window exactly as wide as the layout needs, and one column less gets a short note: <Layout>' -ForEach @(
        @{ Layout = 'Write-ReferenceNeon'; Minimum = 117 }, @{ Layout = 'Write-BlockMarquee'; Minimum = 104 }, @{ Layout = 'Write-ArcadeFrame'; Minimum = 111 }, @{ Layout = 'Write-CenteredTerminal'; Minimum = 107 }
    ) {
        $fits = Get-DS16PreviewLines -Layout $Layout -Width $Minimum
        $fits.Count | Should -BeGreaterThan 10
        @($fits | Where-Object { $_.Length -gt $Minimum }) | Should -BeNullOrEmpty
        $note = Get-DS16PreviewLines -Layout $Layout -Width ($Minimum - 1)
        $note.Count | Should -Be 3
    }
}
