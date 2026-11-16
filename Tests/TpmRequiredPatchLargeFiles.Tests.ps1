#Requires -Module Pester

# Real patches can be big: a self-patching game executable of 142 MB, a 175 MB asset file, a fix that is
# only published as a 7z. These tests use generated files just over the old 64 MiB limit, created in
# TestDrive and removed with it. The engine is dot-sourced like the other TpmRequiredPatch tests.
BeforeDiscovery {
    $script:SevenZip = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ } | ForEach-Object { Join-Path $_ '7-Zip\7z.exe' } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}

BeforeAll {
    . (Join-Path $PSScriptRoot '..\scripts\TpmRequiredPatchEngine.ps1')
    $mainScriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $parseTokens = $null
    $parseErrors = $null
    $mainAst = [System.Management.Automation.Language.Parser]::ParseFile($mainScriptPath, [ref]$parseTokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw 'Unable to parse manager helper source for large-file tests.' }
    foreach ($functionName in @('Get-TpmSupportNativeType','Get-TpmSupportFinalPathFromHandle','Resolve-TpmSupportExpectedFinalPath','Remove-TpmSupportHandle','Get-TpmFileState','Test-PathInside','Test-TpmNoReparsePath','Test-TpmPathOverlap','Assert-TpmNoReparseWriteTarget','New-ManagerUpdateBackup','Test-TpmPathLengthAllowed')) {
        $functionAst = $mainAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $functionName }, $true)
        if (-not $functionAst) { throw ('Missing required helper: ' + $functionName) }
        . ([scriptblock]::Create($functionAst.Extent.Text))
    }
    [void](Get-TpmSupportNativeType)
    $script:SevenZipExe = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ } | ForEach-Object { Join-Path $_ '7-Zip\7z.exe' } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    # Fixed framework assembly names are required by Windows PowerShell 5.1.
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    # One byte value repeated: 65 MiB is just over the old 64 MiB limit.
    $script:BigSize = [int64](65MB)
    function New-LargeFile {
        param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][int64]$Bytes, [Parameter(Mandatory)][char]$Fill)
        $block = [Text.Encoding]::ASCII.GetBytes(([string]$Fill) * 1048576)
        $stream = [IO.File]::Create($Path)
        try {
            $left = $Bytes
            while ($left -gt 0) { $count = [int][Math]::Min($left, $block.Length); $stream.Write($block, 0, $count); $left -= $count }
        } finally { $stream.Dispose() }
    }
    function Get-LargeHash { param([Parameter(Mandatory)][string]$Path) return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }

    # A game whose own executable (sdaemon.exe) is the file the patch replaces.
    function New-LargeCase {
        param([Parameter(Mandatory)][string]$Name)
        $root = Join-Path $TestDrive $Name
        $game = Join-Path $root 'g'; $payload = Join-Path $root 'p'; $recovery = Join-Path $root 'r'; $protected = Join-Path $root 'x'
        foreach ($directory in @($game, $payload, $recovery, $protected)) { [void][IO.Directory]::CreateDirectory($directory) }
        $exe = Join-Path $game 'sdaemon.exe'
        New-LargeFile $exe $script:BigSize 'A'
        New-LargeFile (Join-Path $payload 'sdaemon.new') $script:BigSize 'B'
        $beforeHash = Get-LargeHash $exe
        $afterHash = Get-LargeHash (Join-Path $payload 'sdaemon.new')
        $operation = [pscustomobject]@{ Type='ReplaceFile'; Target='sdaemon.exe'; BeforeSha256=$beforeHash; AfterSha256=$afterHash; Payload='sdaemon.new'; PayloadSha256=$afterHash }
        $entry = [pscustomobject]@{
            Id='large.self.patch'; ProfileId='LargeCase'; Executable='sdaemon.exe'; ExecutableSha256=$beforeHash
            SourceUrl='https://example.invalid/large'; SourceRevision=('C' * 40); ExclusiveGroup=''; AllowExecutableSelfPatch=$true; Operations=@($operation)
        }
        $content = [pscustomobject]@{ Schema=3; Entries=@($entry) } | ConvertTo-Json -Depth 8
        $inputs = @{
            CatalogContent=$content; CatalogSha256=(Get-TpmPatchTextSha256 $content); PatchId=$entry.Id; ProfileId='LargeCase'
            GameRoot=$game; PayloadRoot=$payload; RecoveryRoot=$recovery; ProtectedRoots=@($protected)
        }
        return [pscustomobject]@{ Inputs=$inputs; Root=$root; Exe=$exe; Recovery=$recovery; BeforeHash=$beforeHash; AfterHash=$afterHash }
    }

    # A ZIP/7z member entry for staging: one member of the given size and fill.
    function New-LargeStageEntry {
        param([Parameter(Mandatory)][string]$SourceSet, [Parameter(Mandatory)][string]$SourceEntry, [Parameter(Mandatory)][int64]$Size, [Parameter(Mandatory)][string]$Sha256)
        $operation = [pscustomobject]@{ Type='ReplaceFile'; Target='Game_Data/resources.assets.resS'; BeforeSha256=('1' * 64); AfterSha256=$Sha256; Payload='payload/resources.assets.resS'; PayloadSha256=$Sha256 }
        return [pscustomobject]@{ SourceSet=$SourceSet; SourceEntry=$SourceEntry; SourceSize=$Size; SourceSha1=('2' * 40); SourceSha256=$Sha256; Operations=@($operation) }
    }
}

Describe 'A self-patching executable bigger than 64 MiB' {
    It 'installs, keeps a verified backup of the original, and undo puts the original back' {
        $case = New-LargeCase 'self1'
        $inputs = $case.Inputs
        (Get-TpmPatchPlan @inputs).Status | Should -BeExactly 'Ready'
        $applied = Invoke-TpmCatalogPatch @inputs -Confirm:$false
        $applied.Status | Should -BeExactly 'Applied'
        Get-LargeHash $case.Exe | Should -BeExactly $case.AfterHash
        $receipt = [IO.File]::ReadAllText((Join-Path $applied.RecoveryDirectory 'receipt.json')) | ConvertFrom-Json
        $receipt.Operations[0].BeforeSha256 | Should -BeExactly $case.BeforeHash
        (Get-Item -LiteralPath $receipt.Operations[0].Backup).Length | Should -Be $script:BigSize
        Get-LargeHash $receipt.Operations[0].Backup | Should -BeExactly $case.BeforeHash
        (Get-TpmPatchPlan @inputs).Status | Should -BeExactly 'AlreadyApplied'

        (Undo-TpmCatalogPatch @inputs -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false).Status | Should -BeExactly 'Restored'
        Get-LargeHash $case.Exe | Should -BeExactly $case.BeforeHash
        @(Get-ChildItem -LiteralPath (Split-Path $case.Exe) -Force | Where-Object Name -like '.tpm-*').Count | Should -Be 0
    }

    It 'rolls back to the original executable when the install fails after the new file is in place' {
        $case = New-LargeCase 'self2'
        $inputs = $case.Inputs
        $fail = { param($state) if ($state -ceq 'published') { throw 'simulated failure after publication' } }
        { Invoke-TpmCatalogPatch @inputs -ValidationAction $fail -Confirm:$false } | Should -Throw '*simulated failure after publication*'
        Get-LargeHash $case.Exe | Should -BeExactly $case.BeforeHash
        @(Get-ChildItem -LiteralPath (Split-Path $case.Exe) -Force | Where-Object Name -like '.tpm-*').Count | Should -Be 0
        (Get-TpmPatchPlan @inputs).Status | Should -BeExactly 'Ready'
    }

    It 'refuses and changes nothing when the executable is not the exact expected bytes' {
        $case = New-LargeCase 'self3'
        $stream = [IO.File]::Open($case.Exe, [IO.FileMode]::Open, [IO.FileAccess]::Write)
        try { [void]$stream.Seek(-1, [IO.SeekOrigin]::End); $stream.WriteByte(90) } finally { $stream.Dispose() }
        $changedHash = Get-LargeHash $case.Exe
        $inputs = $case.Inputs
        (Get-TpmPatchPlan @inputs).Status | Should -BeExactly 'Unavailable'
        { Invoke-TpmCatalogPatch @inputs -Confirm:$false } | Should -Throw
        Get-LargeHash $case.Exe | Should -BeExactly $changedHash
        @(Get-ChildItem -LiteralPath $case.Recovery -Force).Count | Should -Be 0
    }

    It 'refuses before writing anything when the drive does not have room for the patch and the backup' {
        $case = New-LargeCase 'self4'
        $inputs = $case.Inputs
        Mock Get-TpmPatchFreeBytes { return [int64](1MB) }
        { Invoke-TpmCatalogPatch @inputs -Confirm:$false } | Should -Throw '*Not enough free space*'
        Get-LargeHash $case.Exe | Should -BeExactly $case.BeforeHash
        @(Get-ChildItem -LiteralPath $case.Recovery -Force).Count | Should -Be 0
        @(Get-ChildItem -LiteralPath (Split-Path $case.Exe) -Force | Where-Object Name -like '.tpm-*').Count | Should -Be 0
    }
}

Describe 'The hard upper limit on one patch file' {
    It 'refuses a payload over 512 MiB without hashing or touching the game' {
        $case = New-LargeCase 'limit1'
        $oversized = Join-Path $case.Root 'p\sdaemon.new'
        $stream = [IO.File]::Open($oversized, [IO.FileMode]::Open, [IO.FileAccess]::Write)
        try { $stream.SetLength(513MB) } finally { $stream.Dispose() }
        $inputs = $case.Inputs
        $plan = Get-TpmPatchPlan @inputs
        $plan.Status | Should -BeExactly 'Unavailable'
        $plan.Reason | Should -BeLike '*size bound*'
        Get-LargeHash $case.Exe | Should -BeExactly $case.BeforeHash
    }

    It 'refuses to stage a member whose pinned size is over 512 MiB, before creating any staging folder' {
        $source = Join-Path $TestDrive 'limit2-src'
        $temp = Join-Path $TestDrive 'limit2-temp'
        foreach ($directory in @($source, $temp)) { [void][IO.Directory]::CreateDirectory($directory) }
        [IO.File]::WriteAllBytes((Join-Path $source 'big.zip'), [byte[]]@(1))
        $script:TpmOwnedLayout = [pscustomobject]@{ Root = $TestDrive; Temp = $temp }
        try {
            $entry = New-LargeStageEntry 'big.zip' 'a.bin' (513MB) ('3' * 64)
            { New-TpmRequiredPatchPayloadStage -Entry $entry -SourceRoot $source } | Should -Throw '*exceeds the supported bound*'
            @(Get-ChildItem -LiteralPath $temp -Force).Count | Should -Be 0
        } finally { $script:TpmOwnedLayout = $null }
    }
}

Describe 'Staging a patch file bigger than 64 MiB' {
    BeforeEach {
        $script:StageSource = Join-Path $TestDrive ('stage-src-' + [guid]::NewGuid().ToString('N'))
        $script:StageTemp = Join-Path $TestDrive ('stage-temp-' + [guid]::NewGuid().ToString('N'))
        foreach ($directory in @($script:StageSource, $script:StageTemp)) { [void][IO.Directory]::CreateDirectory($directory) }
        $script:TpmOwnedLayout = [pscustomobject]@{ Root = $TestDrive; Temp = $script:StageTemp }
        $script:BigMember = Join-Path $script:StageSource 'member.bin'
        New-LargeFile $script:BigMember $script:BigSize 'C'
        $script:BigHash = Get-LargeHash $script:BigMember
    }
    AfterEach { $script:TpmOwnedLayout = $null }

    It 'streams a ZIP member of that size to the staging folder and verifies its size and SHA-256' {
        $zipPath = Join-Path $script:StageSource 'Spiderman Fix.zip'
        $zip = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
        try { [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $script:BigMember, 'Game_Data/resources.assets.resS', [IO.Compression.CompressionLevel]::Fastest) } finally { $zip.Dispose() }
        $entry = New-LargeStageEntry 'Spiderman Fix.zip' 'Game_Data/resources.assets.resS' $script:BigSize $script:BigHash
        $stage = New-TpmRequiredPatchPayloadStage -Entry $entry -SourceRoot $script:StageSource
        $stage.Size | Should -Be $script:BigSize
        Get-LargeHash $stage.Payload | Should -BeExactly $script:BigHash
    }

    It 'refuses, and leaves no staging folder, when the drive does not have room' {
        $zipPath = Join-Path $script:StageSource 'room.zip'
        $zip = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
        try { [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $script:BigMember, 'a.bin', [IO.Compression.CompressionLevel]::Fastest) } finally { $zip.Dispose() }
        $entry = New-LargeStageEntry 'room.zip' 'a.bin' $script:BigSize $script:BigHash
        Mock Get-TpmPatchFreeBytes { return [int64](1MB) }
        { New-TpmRequiredPatchPayloadStage -Entry $entry -SourceRoot $script:StageSource } | Should -Throw '*Not enough free space*'
        @(Get-ChildItem -LiteralPath $script:StageTemp -Force).Count | Should -Be 0
    }

    It 'streams a member of a 7z file with the installed 7-Zip and verifies its size and SHA-256' -Skip:(-not $script:SevenZip) {
        $inner = Join-Path $script:StageSource 'pack\Binaries'
        [void][IO.Directory]::CreateDirectory($inner)
        [IO.File]::Move($script:BigMember, (Join-Path $inner 'sdaemon fix.exe'))
        $archive = Join-Path $script:StageSource 'Fix FNFSB2 exe.7z'
        Push-Location (Join-Path $script:StageSource 'pack')
        try { & $script:SevenZipExe a -bd -mx=1 $archive * | Out-Null } finally { Pop-Location }
        $LASTEXITCODE | Should -Be 0
        $entry = New-LargeStageEntry 'Fix FNFSB2 exe.7z' 'Binaries/sdaemon fix.exe' $script:BigSize $script:BigHash
        $stage = New-TpmRequiredPatchPayloadStage -Entry $entry -SourceRoot $script:StageSource
        $stage.Size | Should -Be $script:BigSize
        Get-LargeHash $stage.Payload | Should -BeExactly $script:BigHash

        # A wrong pinned size or member name is refused and leaves no staging folder behind.
        $wrongSize = New-LargeStageEntry 'Fix FNFSB2 exe.7z' 'Binaries/sdaemon fix.exe' ($script:BigSize - 1) $script:BigHash
        { New-TpmRequiredPatchPayloadStage -Entry $wrongSize -SourceRoot $script:StageSource } | Should -Throw '*absent, duplicated, or has a different size*'
        $wrongName = New-LargeStageEntry 'Fix FNFSB2 exe.7z' 'Binaries/other.exe' $script:BigSize $script:BigHash
        { New-TpmRequiredPatchPayloadStage -Entry $wrongName -SourceRoot $script:StageSource } | Should -Throw '*absent, duplicated, or has a different size*'
        @(Get-ChildItem -LiteralPath $script:StageTemp -Directory -Force).Count | Should -Be 1
    }
}
