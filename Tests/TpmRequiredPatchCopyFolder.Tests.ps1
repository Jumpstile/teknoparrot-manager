#Requires -Module Pester

# Who is helped: a player whose game needs a whole folder of patch files (The House of the Dead EX, Tatsunoko vs. Capcom,
# Ghost Squad Evolution) copied from a ZIP they already own. All files come in together or none do, every overwritten file is
# saved first, and undo puts the originals back. Synthetic files in TestDrive only; the engine is dot-sourced and nothing is run.
BeforeAll {
    . (Join-Path $PSScriptRoot '..\scripts\TpmRequiredPatchEngine.ps1')
    $mainScriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $parseTokens = $null
    $parseErrors = $null
    $mainAst = [System.Management.Automation.Language.Parser]::ParseFile($mainScriptPath, [ref]$parseTokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw 'Unable to parse manager helper source for folder-copy tests.' }
    foreach ($functionName in @('Get-TpmSupportNativeType','Get-TpmSupportFinalPathFromHandle','Resolve-TpmSupportExpectedFinalPath','Remove-TpmSupportHandle','Get-TpmFileState','Test-PathInside','Test-TpmNoReparsePath','Test-TpmPathLengthAllowed','Test-TpmPathOverlap','Assert-TpmNoReparseWriteTarget','New-ManagerUpdateBackup')) {
        $functionAst = $mainAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $functionName }, $true)
        if (-not $functionAst) { throw ('Missing required helper: ' + $functionName) }
        . ([scriptblock]::Create($functionAst.Extent.Text))
    }
    [void](Get-TpmSupportNativeType)
    function Write-Log { param([string]$msg) }
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    function Get-CfBytes { param([string]$Text) return ,[Text.Encoding]::ASCII.GetBytes($Text) }
    function Get-CfSha256 {
        param([Parameter(Mandatory)][byte[]]$Bytes)
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '') } finally { $sha.Dispose() }
    }
    function Get-CfCrc32 {
        param([byte[]]$Bytes)
        if (-not $script:cfCrcTable) {
            $script:cfCrcTable = foreach ($i in 0..255) { $c = [long]$i; foreach ($bit in 1..8) { if ($c -band 1) { $c = 0xEDB88320L -bxor ($c -shr 1) } else { $c = $c -shr 1 } }; $c }
        }
        $crc = 0xFFFFFFFFL
        foreach ($b in $Bytes) { $crc = $script:cfCrcTable[[int](($crc -bxor $b) -band 0xFF)] -bxor ($crc -shr 8) }
        return [uint32]($crc -bxor 0xFFFFFFFFL)
    }
    # A ZIP whose entries are STORED (method 0, no compression), like a game ZIP made by a store-only packer. Members: @{ Name; Bytes }.
    function New-CfStoredZipBytes {
        param([Parameter(Mandatory)][object[]]$Members)
        $stream = New-Object IO.MemoryStream
        $writer = New-Object IO.BinaryWriter($stream)
        $central = @()
        foreach ($member in $Members) {
            $name = Get-CfBytes $member.Name
            $crc = Get-CfCrc32 $member.Bytes
            $offset = [uint32]$stream.Position
            $writer.Write([uint32]0x04034b50); $writer.Write([uint16]20); $writer.Write([uint16]0); $writer.Write([uint16]0); $writer.Write([uint16]0); $writer.Write([uint16]0x21)
            $writer.Write([uint32]$crc); $writer.Write([uint32]$member.Bytes.Length); $writer.Write([uint32]$member.Bytes.Length); $writer.Write([uint16]$name.Length); $writer.Write([uint16]0)
            $writer.Write($name); $writer.Write([byte[]]$member.Bytes)
            $central += @([pscustomobject]@{ Name = $name; Crc = $crc; Length = [uint32]$member.Bytes.Length; Offset = $offset })
        }
        $start = [uint32]$stream.Position
        foreach ($item in $central) {
            $writer.Write([uint32]0x02014b50); $writer.Write([uint16]20); $writer.Write([uint16]20); $writer.Write([uint16]0); $writer.Write([uint16]0); $writer.Write([uint16]0); $writer.Write([uint16]0x21)
            $writer.Write([uint32]$item.Crc); $writer.Write([uint32]$item.Length); $writer.Write([uint32]$item.Length); $writer.Write([uint16]$item.Name.Length)
            $writer.Write([uint16]0); $writer.Write([uint16]0); $writer.Write([uint16]0); $writer.Write([uint16]0); $writer.Write([uint32]0); $writer.Write([uint32]$item.Offset); $writer.Write($item.Name)
        }
        $size = [uint32]($stream.Position - $start)
        $writer.Write([uint32]0x06054b50); $writer.Write([uint16]0); $writer.Write([uint16]0); $writer.Write([uint16]$central.Count); $writer.Write([uint16]$central.Count)
        $writer.Write($size); $writer.Write($start); $writer.Write([uint16]0)
        $writer.Flush()
        return ,[byte[]]$stream.ToArray()
    }

    # A game folder with a program, a patch ZIP (own bytes below), and the destination folder holding the ORIGINAL files.
    #   a.bin and sub\c.bin exist and get replaced; b.bin and pack.zip are new. pack.zip is a stored ZIP that holds a nested ZIP.
    function New-CfCase {
        param([Parameter(Mandatory)][string]$Name, [ValidateSet('Game', 'TeknoParrot')][string]$Root = 'Game', [string]$Destination = 'data',
            [string]$ExtraPath = '', [string]$WrongPatchedA = '', [switch]$NoSubFolder)
        $base = Join-Path $TestDrive $Name
        $game = Join-Path $base 'g'; $tp = Join-Path $base 'tp'; $payload = Join-Path $base 'p'; $recovery = Join-Path $base 'r'; $protected = Join-Path $base 'x'; $src = Join-Path $base 's'; $temp = Join-Path $base 't'
        foreach ($directory in @($game, $tp, $payload, $recovery, $protected, $src, $temp, (Join-Path $tp 'GameProfiles'), (Join-Path $tp 'UserProfiles'))) { [void][IO.Directory]::CreateDirectory($directory) }
        $script:TpmOwnedLayout = [pscustomobject]@{ Root = $base; Temp = $temp }
        [IO.File]::WriteAllBytes((Join-Path $game 'game.exe'), (Get-CfBytes 'synthetic program; never run'))
        [IO.File]::WriteAllBytes((Join-Path $tp 'TeknoParrotUi.exe'), (Get-CfBytes 'synthetic launcher; never run'))
        $rootFolder = if ($Root -ceq 'TeknoParrot') { $tp } else { $game }
        $target = Join-Path $rootFolder $Destination
        $makeFiles = ($Destination -notmatch '\.\.|:')
        if ($makeFiles) { [void][IO.Directory]::CreateDirectory((Join-Path $target 'sub')) }
        if ($NoSubFolder) { Remove-Item -LiteralPath (Join-Path $target 'sub') -Recurse -Force }
        $inner = New-CfStoredZipBytes @(@{ Name = 'deep.txt'; Bytes = (Get-CfBytes 'deep file') })
        $pack = New-CfStoredZipBytes @(@{ Name = 'inner.zip'; Bytes = [byte[]]$inner }, @{ Name = 'note.txt'; Bytes = (Get-CfBytes 'note') })
        $orig = @{ 'a.bin' = (Get-CfBytes 'original a'); 'sub/c.bin' = (Get-CfBytes 'original c') }
        $patched = [ordered]@{
            'a.bin' = $(if ($WrongPatchedA) { Get-CfBytes $WrongPatchedA } else { Get-CfBytes 'patched a' }); 'b.bin' = (Get-CfBytes 'new b'); 'sub/c.bin' = (Get-CfBytes 'patched c'); 'pack.zip' = [byte[]]$pack
        }
        $pins = [ordered]@{ 'a.bin' = (Get-CfBytes 'patched a'); 'b.bin' = (Get-CfBytes 'new b'); 'sub/c.bin' = (Get-CfBytes 'patched c'); 'pack.zip' = [byte[]]$pack }
        if ($makeFiles) { foreach ($relative in $orig.Keys) { if (-not ($NoSubFolder -and $relative -like 'sub/*')) { [IO.File]::WriteAllBytes((Join-Path $target $relative.Replace('/', '\')), $orig[$relative]) } } }
        $members = @(foreach ($relative in $patched.Keys) { @{ Name = 'Patch/Fix/' + $relative; Bytes = [byte[]]$patched[$relative] } }) + @(@{ Name = 'readme.txt'; Bytes = (Get-CfBytes 'readme') })
        [IO.File]::WriteAllBytes((Join-Path $src 'game.zip'), (New-CfStoredZipBytes $members))
        $files = @(foreach ($relative in $pins.Keys) { [pscustomobject]@{ Path = $relative; Size = [int64]$pins[$relative].Length; Sha256 = (Get-CfSha256 $pins[$relative]) } })
        if ($ExtraPath) { $files += @([pscustomobject]@{ Path = $ExtraPath; Size = [int64]4; Sha256 = (Get-CfSha256 (Get-CfBytes 'evil')) }) }
        $entry = [pscustomobject]@{
            Id = 'cf.test'; ProfileId = 'CfTest'; Executable = 'game.exe'; ExecutableSha256 = ''; SourceUrl = ''; SourceRevision = ''
            SourceRole = 'Main'; SourceSet = 'game.zip'; SourceEntry = 'Patch/Fix'; ExclusiveGroup = ''; Prerequisites = @()
            Operations = @([pscustomobject]@{ Type = 'CopyFolder'; DestinationRoot = $Root; Destination = $Destination; Files = $files })
        }
        $content = [pscustomobject]@{ Schema = 3; Entries = @($entry) } | ConvertTo-Json -Depth 8
        $protectedRoots = @($protected, (Join-Path $tp 'TeknoParrotUi.exe'), (Join-Path $tp 'GameProfiles'), (Join-Path $tp 'UserProfiles'))
        return [pscustomobject]@{
            Entry = $entry; Game = $game; Tp = $tp; Target = $target; Src = $src; Orig = $orig; Pins = $pins; Base = $base
            Inputs = @{ CatalogContent = $content; CatalogSha256 = (Get-TpmPatchTextSha256 $content); PatchId = 'cf.test'; ProfileId = 'CfTest'; GameRoot = $game; PayloadRoot = $payload; RecoveryRoot = $recovery; ProtectedRoots = $protectedRoots; TeknoParrotRoot = $tp }
        }
    }
    # The patch files from the ZIP, staged under their pins, then the inputs for the engine.
    function Get-CfStagedInputs {
        param($Case)
        $stage = New-TpmRequiredPatchPayloadStage -Entry $Case.Entry -SourceRoot $Case.Src
        $inputs = @{} + $Case.Inputs
        $inputs.PayloadRoot = $stage.Root
        return $inputs
    }
    function Get-CfDiskBytes { param($Case, [string]$Relative) return ,[IO.File]::ReadAllBytes((Join-Path $Case.Target $Relative.Replace('/', '\'))) }
    function Assert-CfOriginals {
        param($Case)
        (Get-CfDiskBytes $Case 'a.bin') | Should -Be $Case.Orig['a.bin']
        (Get-CfDiskBytes $Case 'sub/c.bin') | Should -Be $Case.Orig['sub/c.bin']
        Test-Path -LiteralPath (Join-Path $Case.Target 'b.bin') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $Case.Target 'pack.zip') | Should -BeFalse
    }
    function Assert-CfPatched {
        param($Case)
        foreach ($relative in $Case.Pins.Keys) { (Get-CfDiskBytes $Case $relative) | Should -Be $Case.Pins[$relative] }
    }
}

Describe 'A folder copy puts every patch file in, or none' {
    It 'copies the whole folder from the ZIP, saves each overwritten file, and does not touch anything else' {
        $case = New-CfCase 'ok'
        $inputs = Get-CfStagedInputs $case
        $applied = Invoke-TpmCatalogPatch @inputs -Confirm:$false
        $applied.Status | Should -BeExactly 'Applied'
        Assert-CfPatched $case
        [IO.File]::ReadAllText((Join-Path $case.Game 'game.exe')) | Should -BeExactly 'synthetic program; never run'
        $receipt = [IO.File]::ReadAllText((Join-Path $applied.RecoveryDirectory 'receipt.json')) | ConvertFrom-Json
        $receipt.State | Should -BeExactly 'Applied'
        @($receipt.Operations).Count | Should -Be 4
        [IO.File]::ReadAllBytes((@($receipt.Operations | Where-Object Target -CEQ 'data/a.bin')[0].Backup)) | Should -Be $case.Orig['a.bin']
        [IO.File]::ReadAllBytes((@($receipt.Operations | Where-Object Target -CEQ 'data/sub/c.bin')[0].Backup)) | Should -Be $case.Orig['sub/c.bin']
    }

    It 'copies a ZIP file that holds a nested ZIP byte for byte' {
        $case = New-CfCase 'nested'
        $inputs = Get-CfStagedInputs $case
        [void](Invoke-TpmCatalogPatch @inputs -Confirm:$false)
        $zipPath = Join-Path $case.Target 'pack.zip'
        (Get-CfDiskBytes $case 'pack.zip') | Should -Be $case.Pins['pack.zip']
        $outer = [IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            @($outer.Entries.FullName) | Should -Be @('inner.zip', 'note.txt')
            $innerStream = $outer.GetEntry('inner.zip').Open()
            $copy = New-Object IO.MemoryStream
            try { $innerStream.CopyTo($copy) } finally { $innerStream.Dispose() }
            $nested = New-Object IO.Compression.ZipArchive($copy, [IO.Compression.ZipArchiveMode]::Read)
            try { @($nested.Entries.FullName) | Should -Be @('deep.txt') } finally { $nested.Dispose() }
        } finally { $outer.Dispose() }
    }

    It 'undo puts every original back byte for byte and removes the new files' {
        $case = New-CfCase 'undo'
        $inputs = Get-CfStagedInputs $case
        $applied = Invoke-TpmCatalogPatch @inputs -Confirm:$false
        $undone = Undo-TpmCatalogPatch @inputs -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false
        $undone.Status | Should -BeExactly 'Restored'
        Assert-CfOriginals $case
    }

    It 'does nothing when run again on a game that already has the patch' {
        $case = New-CfCase 'rerun'
        $inputs = Get-CfStagedInputs $case
        [void](Invoke-TpmCatalogPatch @inputs -Confirm:$false)
        $again = Invoke-TpmCatalogPatch @inputs -Confirm:$false
        $again.Status | Should -BeExactly 'AlreadyApplied'
        @(Get-ChildItem -LiteralPath $case.Inputs.RecoveryRoot -Directory | Where-Object Name -Match '^[a-f0-9]{32}$').Count | Should -Be 1
        Assert-CfPatched $case
    }

    It 'leaves files that already match alone, installs the rest, and undo restores only what it changed' {
        $case = New-CfCase 'partial'
        [IO.File]::WriteAllBytes((Join-Path $case.Target 'a.bin'), $case.Pins['a.bin'])
        $inputs = Get-CfStagedInputs $case
        $applied = Invoke-TpmCatalogPatch @inputs -Confirm:$false
        $applied.Status | Should -BeExactly 'Applied'
        @(([IO.File]::ReadAllText((Join-Path $applied.RecoveryDirectory 'receipt.json')) | ConvertFrom-Json).Operations).Count | Should -Be 3
        Assert-CfPatched $case
        [void](Undo-TpmCatalogPatch @inputs -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false)
        (Get-CfDiskBytes $case 'a.bin') | Should -Be $case.Pins['a.bin']
        (Get-CfDiskBytes $case 'sub/c.bin') | Should -Be $case.Orig['sub/c.bin']
        Test-Path -LiteralPath (Join-Path $case.Target 'b.bin') | Should -BeFalse
    }
}

Describe 'A wrong or different patch is refused and nothing changes' {
    It 'refuses a ZIP whose file has other bytes than the recipe pins' {
        $case = New-CfCase 'wrong' -WrongPatchedA 'patched X'
        { Get-CfStagedInputs $case } | Should -Throw '*payload and target*'
        Assert-CfOriginals $case
        @(Get-ChildItem -LiteralPath $case.Inputs.RecoveryRoot -Directory | Where-Object Name -Match '^[a-f0-9]{32}$').Count | Should -Be 0
    }

    It 'refuses when a staged file is swapped after staging' {
        $case = New-CfCase 'swapped'
        $inputs = Get-CfStagedInputs $case
        [IO.File]::WriteAllBytes((Join-Path $inputs.PayloadRoot 'cf-1.tmp'), (Get-CfBytes 'tampered'))
        { Invoke-TpmCatalogPatch @inputs -Confirm:$false } | Should -Throw
        Assert-CfOriginals $case
        @(Get-ChildItem -LiteralPath $case.Inputs.RecoveryRoot -Directory | Where-Object Name -Match '^[a-f0-9]{32}$').Count | Should -Be 0
    }

    It 'tells the player what to get when the ZIP is missing' {
        $case = New-CfCase 'nozip'
        Remove-Item -LiteralPath (Join-Path $case.Src 'game.zip')
        { Get-CfStagedInputs $case } | Should -Throw '*The ZIP file with this patch was not found. TeknoParrot Manager does not download it.*game.zip*'
        Assert-CfOriginals $case
    }

    It 'refuses when a folder sits where the patch needs a file' {
        $case = New-CfCase 'dirhit'
        Remove-Item -LiteralPath (Join-Path $case.Target 'b.bin') -ErrorAction SilentlyContinue
        [void][IO.Directory]::CreateDirectory((Join-Path $case.Target 'b.bin'))
        $inputs = Get-CfStagedInputs $case
        { Invoke-TpmCatalogPatch @inputs -Confirm:$false } | Should -Throw
        (Get-CfDiskBytes $case 'a.bin') | Should -Be $case.Orig['a.bin']
    }
}

Describe 'A folder copy never leaves the folder it is allowed to write in' {
    It 'refuses a recipe that walks out with ..' {
        $case = New-CfCase 'dots' -ExtraPath '../../escape.bin'
        $inputs = @{} + $case.Inputs
        $plan = Get-TpmPatchPlan @inputs
        $plan.Status | Should -BeExactly 'Unavailable'
        Test-Path -LiteralPath (Join-Path $case.Base 'escape.bin') | Should -BeFalse
    }

    It 'refuses a destination that starts outside the game folder' {
        $case = New-CfCase 'dest' -Destination '..\g2'
        $inputs = @{} + $case.Inputs
        (Get-TpmPatchPlan @inputs).Status | Should -BeExactly 'Unavailable'
    }

    It 'refuses an absolute path in the recipe' {
        $case = New-CfCase 'abs' -Destination 'C:\Windows'
        $inputs = @{} + $case.Inputs
        (Get-TpmPatchPlan @inputs).Status | Should -BeExactly 'Unavailable'
    }

    It 'refuses a folder that is really a junction to somewhere else' {
        $case = New-CfCase 'junction'
        $outside = Join-Path $case.Base 'outside'
        [void][IO.Directory]::CreateDirectory($outside)
        [IO.File]::WriteAllBytes((Join-Path $outside 'c.bin'), (Get-CfBytes 'outside c'))
        Remove-Item -LiteralPath (Join-Path $case.Target 'sub') -Recurse -Force
        New-Item -ItemType Junction -Path (Join-Path $case.Target 'sub') -Target $outside | Out-Null
        $inputs = Get-CfStagedInputs $case
        (Get-TpmPatchPlan @inputs).Status | Should -BeExactly 'Unavailable'
        { Invoke-TpmCatalogPatch @inputs -Confirm:$false } | Should -Throw
        [IO.File]::ReadAllBytes((Join-Path $outside 'c.bin')) | Should -Be (Get-CfBytes 'outside c')
        (Get-CfDiskBytes $case 'a.bin') | Should -Be $case.Orig['a.bin']
    }

    It 'refuses when a folder the patch needs does not exist, and says so in plain words' {
        $case = New-CfCase 'nofolder' -NoSubFolder
        $inputs = Get-CfStagedInputs $case
        $plan = Get-TpmPatchPlan @inputs
        $plan.Status | Should -BeExactly 'Unavailable'
        (Get-TpmRequiredPatchPlainReason -Status 'BLOCKED' -Reason $plan.Reason) | Should -BeLike 'A folder this patch copies into does not exist yet*'
        (Get-CfDiskBytes $case 'a.bin') | Should -Be $case.Orig['a.bin']
    }

    It 'copies into the TeknoParrot folder only when the recipe says so and the folder was given' {
        $case = New-CfCase 'tp' -Root TeknoParrot -Destination 'Libs'
        $inputs = Get-CfStagedInputs $case
        $applied = Invoke-TpmCatalogPatch @inputs -Confirm:$false
        $applied.Status | Should -BeExactly 'Applied'
        Assert-CfPatched $case
        Test-Path -LiteralPath (Join-Path $case.Game 'libs') | Should -BeFalse
        [void](Undo-TpmCatalogPatch @inputs -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false)
        Assert-CfOriginals $case
    }

    It 'refuses a TeknoParrot-folder recipe when no TeknoParrot folder is given' {
        $case = New-CfCase 'tpnone' -Root TeknoParrot -Destination 'Libs'
        $inputs = Get-CfStagedInputs $case
        $inputs.Remove('TeknoParrotRoot')
        $plan = Get-TpmPatchPlan @inputs
        $plan.Status | Should -BeExactly 'Unavailable'
        (Get-TpmRequiredPatchPlainReason -Status 'BLOCKED' -Reason $plan.Reason) | Should -BeLike 'This patch copies files into your TeknoParrot folder*'
    }

    It 'never overwrites a protected TeknoParrot file such as the launcher or a profile' {
        $case = New-CfCase 'tpprotected' -Root TeknoParrot -Destination 'GameProfiles'
        $inputs = @{} + $case.Inputs
        (Get-TpmPatchPlan @inputs).Status | Should -BeExactly 'Unavailable'
        [IO.File]::ReadAllText((Join-Path $case.Tp 'TeknoParrotUi.exe')) | Should -BeExactly 'synthetic launcher; never run'
        (Get-CfDiskBytes $case 'a.bin') | Should -Be $case.Orig['a.bin']
    }
}

Describe 'A folder copy that fails part way is rolled back' {
    It 'restores every original and removes every new file when the last check fails' {
        $case = New-CfCase 'rollback'
        $inputs = Get-CfStagedInputs $case
        $check = { param($State) if ($State -ceq 'published') { throw 'simulated failure after the files were copied' } }
        { Invoke-TpmCatalogPatch @inputs -ValidationAction $check -Confirm:$false } | Should -Throw '*simulated failure*'
        Assert-CfOriginals $case
        $run = @(Get-ChildItem -LiteralPath $case.Inputs.RecoveryRoot -Directory | Where-Object Name -Match '^[a-f0-9]{32}$')
        $receipt = [IO.File]::ReadAllText((Join-Path $run[0].FullName 'receipt.json')) | ConvertFrom-Json
        $receipt.State | Should -BeExactly 'RolledBack'
    }
}

Describe 'The three games that need a folder copy are honest about what is missing' {
    It '<Id> reports "not ready yet" and changes nothing' -TestCases @(
        @{ Id = 'the-house-of-the-dead-ex-folder-copy'; Profile = 'HOTDEX' }
        @{ Id = 'tatsunoko-vs-capcom-folder-copy'; Profile = 'tatsuvscap' }
    ) {
        $catalog = Read-TpmRequiredPatchCatalog -ProgramRoot ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')))
        $base = Join-Path $TestDrive ('real-' + $Id)
        foreach ($name in @('g', 'p', 'r', 'x')) { [void][IO.Directory]::CreateDirectory((Join-Path $base $name)) }
        $plan = Get-TpmPatchPlan -CatalogContent $catalog.Content -CatalogSha256 $catalog.CatalogSha256 -PatchId $Id -ProfileId $Profile -GameRoot (Join-Path $base 'g') -PayloadRoot (Join-Path $base 'p') -RecoveryRoot (Join-Path $base 'r') -ProtectedRoots @((Join-Path $base 'x'))
        $plan.Status | Should -BeExactly 'Unavailable'
        $plan.Reason | Should -BeLike 'This patch is not ready yet.*Still needed:*Nothing was changed.'
        (Get-TpmRequiredPatchPlainReason -Status 'BLOCKED' -Reason $plan.Reason) | Should -BeLike 'This patch is not ready in this version of TeknoParrot Manager yet.*'
        @(Get-ChildItem -LiteralPath (Join-Path $base 'g') -Recurse).Count | Should -Be 0
    }
}

Describe 'A game ZIP made of stored entries with ZIP files inside it can be read' {
    It 'reads a nested ZIP member out of a stored game ZIP, exactly' {
        $case = New-CfCase 'storezip'
        $inner = New-CfStoredZipBytes @(@{ Name = 'deep.txt'; Bytes = (Get-CfBytes 'deep file') })
        $outerBytes = New-CfStoredZipBytes @(@{ Name = 'Patches/inner.zip'; Bytes = [byte[]]$inner }, @{ Name = 'readme.txt'; Bytes = (Get-CfBytes 'readme') })
        [IO.File]::WriteAllBytes((Join-Path $case.Src 'game.zip'), $outerBytes)
        $sha = Get-CfSha256 $inner
        $entry = [pscustomobject]@{
            Id = 'nested.single'; ProfileId = 'CfTest'; Executable = 'game.exe'; ExecutableSha256 = ''; SourceUrl = ''; SourceRevision = ''
            SourceRole = 'Main'; SourceSet = 'game.zip'; SourceEntry = 'Patches/inner.zip'; SourceSize = [int64]$inner.Length; SourceSha256 = $sha
            Operations = @([pscustomobject]@{ Type = 'CreateFile'; Target = 'inner.zip'; BeforeState = 'Absent'; AfterSha256 = $sha; Payload = 'payload/inner.zip'; PayloadSha256 = $sha })
        }
        $stage = New-TpmRequiredPatchPayloadStage -Entry $entry -SourceRoot $case.Src
        [IO.File]::ReadAllBytes($stage.Payload) | Should -Be $inner
        $opened = [IO.Compression.ZipFile]::OpenRead($stage.Payload)
        try { @($opened.Entries.FullName) | Should -Be @('deep.txt') } finally { $opened.Dispose() }
    }
}
