param(
    [string]$RepositoryRoot = ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))),
    [string]$FragmentPath = (Join-Path $RepositoryRoot 'tools/required-patches/fragments/mkdxusa106-main-d3d11ref-20261015.json')
)

BeforeAll {
    $script:mkdxProgramRoot = [IO.Path]::GetFullPath($RepositoryRoot)
    $enginePath = Join-Path $script:mkdxProgramRoot 'scripts/TpmRequiredPatchEngine.ps1'
    if (-not (Test-Path -LiteralPath $enginePath -PathType Leaf)) { throw 'Required-patch engine is unavailable under RepositoryRoot.' }
    . $enginePath
    function Test-PathInside {
        param([string]$child,[string]$parent)
        try {
            $c=[IO.Path]::GetFullPath($child).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
            $p=[IO.Path]::GetFullPath($parent).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
            return $c.StartsWith($p+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or $c.Equals($p,[StringComparison]::OrdinalIgnoreCase)
        } catch { return $false }
    }
    function Test-TpmNoReparsePath {
        param([string]$Path)
        try {
            $full=[IO.Path]::GetFullPath($Path);$root=[IO.Path]::GetPathRoot($full);$current=$root;$relative=$full.Substring($root.Length)
            foreach($part in ($relative -split '[\\/]')){
                if([string]::IsNullOrWhiteSpace($part)){continue}
                $current=Join-Path $current $part
                if(Test-Path -LiteralPath $current){$item=Get-Item -LiteralPath $current -Force;if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return $false}}
            }
            return $true
        } catch { return $false }
    }

    $script:mkdxFragmentPath = [IO.Path]::GetFullPath($FragmentPath)
    $script:mkdxFragmentText = [IO.File]::ReadAllText($script:mkdxFragmentPath, [Text.Encoding]::UTF8)
    $script:mkdxFragmentFileSha256 = (Get-FileHash -LiteralPath $script:mkdxFragmentPath -Algorithm SHA256).Hash.ToUpperInvariant()
    $script:mkdxFragment = $script:mkdxFragmentText | ConvertFrom-Json -ErrorAction Stop

    $mainPath = Join-Path $script:mkdxProgramRoot 'TeknoParrot-Manager.ps1'
    $tokens = $null; $errors = $null
    $mainAst = [System.Management.Automation.Language.Parser]::ParseFile($mainPath, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw 'Unable to parse manager helper source for isolated required-patch transactions.' }
    foreach ($name in @('Get-TpmSupportNativeType', 'Get-TpmSupportFinalPathFromHandle', 'Remove-TpmSupportHandle', 'Test-TpmPathOverlap', 'Get-TpmFileState', 'Read-HostSafe', 'Read-PathWithBrowse')) {
        $function = $mainAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name }, $true)
        if (-not $function) { throw "Required manager helper '$name' was not found." }
        . ([scriptblock]::Create($function.Extent.Text))
    }
    [void](Get-TpmSupportNativeType)

    $suitePath = Join-Path $script:mkdxProgramRoot 'Tests/TeknoParrot-Manager.Tests.ps1'
    $suiteTokens = $null; $suiteErrors = $null
    $suiteAst = [System.Management.Automation.Language.Parser]::ParseFile($suitePath, [ref]$suiteTokens, [ref]$suiteErrors)
    if ($suiteErrors.Count) { throw 'Unable to parse the existing required-patch fixture source.' }
    $describe = $suiteAst.Find({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Describe' -and $node.CommandElements.Count -ge 3 -and $node.CommandElements[1].Value -ceq 'Required patch engine and local recipes' }, $true)
    if (-not $describe) { throw 'The existing required-patch fixture container was not found.' }
    $beforeEach = $describe.CommandElements[2].ScriptBlock.Find({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'BeforeEach' }, $true)
    if (-not $beforeEach) { throw 'The existing required-patch fixture setup was not found.' }
    $script:mkdxFixtureSetup = $beforeEach.CommandElements[-1].ScriptBlock.GetScriptBlock()

    function New-MkdxSyntheticContext {
        param([Parameter(Mandatory)]$Recipe, [Parameter(Mandatory)]$Fixture, [switch]$WrongExecutable)
        $entry = $Recipe | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $entry.Executable = 'synthetic.exe'
        $entry.ExecutableSha256 = if ($WrongExecutable) { 'F' * 64 } else { $Fixture.ExecutableSha256 }
        $entry.SourceRole = 'Main'
        $bytes = [Text.Encoding]::UTF8.GetBytes(('synthetic D3D11Ref.dll bytes for ' + [string]$entry.Id + '; never execute'))
        $payloadRelative = 'payload/' + [string]$entry.Id + '.bin'
        $payload = Join-Path $Fixture.PayloadRoot ($payloadRelative.Replace('/', '\'))
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($payload))
        [IO.File]::WriteAllBytes($payload, $bytes)
        $entry.SourceSize = [int]$bytes.Length
        $entry.SourceSha1 = (Get-FileHash -LiteralPath $payload -Algorithm SHA1).Hash
        $entry.SourceSha256 = (Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash
        $entry.Operations[0].AfterSha256 = $entry.SourceSha256
        $entry.Operations[0].Payload = $payloadRelative
        $entry.Operations[0].PayloadSha256 = $entry.SourceSha256
        $content = [pscustomobject]@{ Schema = 3; Entries = @($entry) } | ConvertTo-Json -Depth 20 -Compress
        $inputs = @{
            CatalogContent = $content; CatalogSha256 = Get-TpmPatchTextSha256 $content
            PatchId = $entry.Id; ProfileId = $entry.ProfileId
            GameRoot = $Fixture.GameRoot; PayloadRoot = $Fixture.PayloadRoot
            RecoveryRoot = $Fixture.RecoveryRoot; ProtectedRoots = @($Fixture.ProtectedRoot)
        }
        $target = Join-Path $Fixture.GameRoot ($entry.Operations[0].Target.Replace('/', '\'))
        return [pscustomobject]@{ Entry = $entry; Inputs = $inputs; Target = $target; Payload = $payload; PayloadBytes = $bytes; PayloadSha256 = $entry.SourceSha256 }
    }
}

Describe 'MKDX USA 1.06 exact Main D3D11Ref restoration' {
    It 'binds the exact Main build and absent-only source and payload pins' {
        $script:mkdxFragment.Schema | Should -BeExactly 'TPM.RequiredPatch.ManagedPluginFragment.v1'
        $script:mkdxFragmentFileSha256 | Should -Match '^[A-F0-9]{64}$'
        $script:mkdxFragment.BaseCatalog.Schema | Should -Be 3
        $script:mkdxFragment.BaseCatalog.EntryCount | Should -Be 68
        $script:mkdxFragment.BaseCatalog.Sha256 | Should -BeExactly 'FE4E01861BEFE6C8B13A9185C26FEE4BED62B8D78C59C8353DCAB53448F4DC20'
        @($script:mkdxFragment.Entries).Count | Should -Be 1
        $entry = $script:mkdxFragment.Entries[0]
        $entry.Id | Should -BeExactly 'mkdxusa106-main-d3d11ref-restore'
        $entry.ProfileId | Should -BeExactly 'MKDXUSA106'
        $entry.BuildName | Should -BeExactly 'Mario Kart Arcade GP DX (1.06.35-OF)(2022-08-01)(USA)[Namco ES3A][TP]'
        $entry.Executable | Should -BeExactly 'MK_AGP3_FINAL.exe'
        $entry.ExecutableSha256 | Should -BeExactly '2E6CF156B30C079F82EF279B8C0D55CC46386A76E52D73F3582062CF820F0076'
        $entry.SourceUrl | Should -BeExactly ''
        $entry.SourceRevision | Should -BeExactly ''
        $entry.SourceRole | Should -BeExactly 'Main'
        $entry.SourceSet | Should -BeExactly 'Mario Kart Arcade GP DX (1.06.35-OF)(2022-08-01)(USA)[Namco ES3A][TP].zip'
        $entry.SourceEntry | Should -BeExactly 'D3D11Ref.dll'
        $entry.SourceSize | Should -Be 525144
        $entry.SourceSha1 | Should -BeExactly '01338F329BFADC339F4A402AABB29DE50521F32F'
        $entry.SourceSha256 | Should -BeExactly '6335BD1F8A137C6A6696878C67652D1C75551C858E589559DFAFA15A5E54C8C3'
        @($entry.Operations).Count | Should -Be 1
        $entry.Operations[0].Type | Should -BeExactly 'CreateFile'
        $entry.Operations[0].Target | Should -BeExactly 'D3D11Ref.dll'
        $entry.Operations[0].BeforeState | Should -BeExactly 'Absent'
        $entry.Operations[0].AfterSha256 | Should -BeExactly $entry.SourceSha256
        $entry.Operations[0].PayloadSha256 | Should -BeExactly $entry.SourceSha256
        [string]$entry.ExclusiveGroup | Should -BeExactly ''
        @($entry.Prerequisites).Count | Should -Be 0
        $entry.PSObject.Properties['HardwarePredicate'] | Should -BeNullOrEmpty
        $entry.PSObject.Properties['AllowExecutableSelfPatch'] | Should -BeNullOrEmpty
    }

    It 'stages exact synthetic member bytes, applies once, no-ops on repeat, and receipt-undoes to absence' {
        & $script:mkdxFixtureSetup
        $fixture = $script:requiredPatchFixture
        Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
        $sourceRoot = Join-Path $fixture.Root 'mkdx-source'
        [void][IO.Directory]::CreateDirectory($sourceRoot)
        $archivePath = Join-Path $sourceRoot $script:mkdxFragment.Entries[0].SourceSet
        $archive = [IO.Compression.ZipFile]::Open($archivePath, [IO.Compression.ZipArchiveMode]::Create)
        try {
            $bytes = [Text.Encoding]::UTF8.GetBytes('synthetic source DLL bytes; never execute')
            $member = $archive.CreateEntry('D3D11Ref.dll', [IO.Compression.CompressionLevel]::Optimal)
            $stream = $member.Open()
            try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
        } finally { $archive.Dispose() }
        $entry = $script:mkdxFragment.Entries[0] | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $entry.SourceSize = $bytes.Length
        $referenceDirectory = Join-Path $fixture.PayloadRoot 'payload'
        [void][IO.Directory]::CreateDirectory($referenceDirectory)
        $reference = Join-Path $referenceDirectory 'mkdx-source.reference'
        [IO.File]::WriteAllBytes($reference, $bytes)
        $entry.SourceSha1 = (Get-FileHash -LiteralPath $reference -Algorithm SHA1).Hash
        $entry.SourceSha256 = (Get-FileHash -LiteralPath $reference -Algorithm SHA256).Hash
        $entry.Operations[0].AfterSha256 = $entry.SourceSha256
        $entry.Operations[0].PayloadSha256 = $entry.SourceSha256
        $entry.Operations[0].Payload = 'payload/mkdx-source.reference'
        $owned = Join-Path $fixture.Root 'manager/owned'
        $temp = Join-Path $owned 'Temp'
        [void][IO.Directory]::CreateDirectory($temp)
        $script:TpmOwnedLayout = [pscustomobject]@{ Root = $owned; Temp = $temp; Backups = (Join-Path $owned 'Backups') }
        $stage = New-TpmRequiredPatchPayloadStage -Entry $entry -SourceRoot $sourceRoot
        $stage.SourceEntry | Should -BeExactly 'D3D11Ref.dll'
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($stage.Payload)) | Should -BeExactly ([Convert]::ToBase64String($bytes))
        & $script:mkdxFixtureSetup
        $fixture = $script:requiredPatchFixture
        $case = New-MkdxSyntheticContext -Recipe $script:mkdxFragment.Entries[0] -Fixture $fixture

        $inputs = $case.Inputs
        $applied = Invoke-TpmCatalogPatch @inputs -Confirm:$false
        $applied.Status | Should -BeExactly 'Applied'
        (Get-FileHash -LiteralPath $case.Target -Algorithm SHA256).Hash | Should -BeExactly $case.PayloadSha256
        (Invoke-TpmCatalogPatch @inputs -Confirm:$false).Status | Should -BeExactly 'AlreadyApplied'
        (Undo-TpmCatalogPatch @inputs -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false).Status | Should -BeExactly 'Restored'
        Test-Path -LiteralPath $case.Target | Should -BeFalse
    }

    It 'refuses a wrong executable and unknown existing target bytes without mutation' {
        & $script:mkdxFixtureSetup
        $fixture = $script:requiredPatchFixture
        $wrong = New-MkdxSyntheticContext -Recipe $script:mkdxFragment.Entries[0] -Fixture $fixture -WrongExecutable
        $wrongInputs = $wrong.Inputs
        (Get-TpmPatchPlan @wrongInputs).Status | Should -BeExactly 'Unavailable'
        { Invoke-TpmCatalogPatch @wrongInputs -Confirm:$false } | Should -Throw
        Test-Path -LiteralPath $wrong.Target | Should -BeFalse
        @(Get-ChildItem -LiteralPath $fixture.RecoveryRoot -Force).Count | Should -Be 0

        & $script:mkdxFixtureSetup
        $fixture = $script:requiredPatchFixture
        $unknown = New-MkdxSyntheticContext -Recipe $script:mkdxFragment.Entries[0] -Fixture $fixture
        $unknownInputs = $unknown.Inputs
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($unknown.Target))
        [IO.File]::WriteAllText($unknown.Target, 'unknown existing DLL bytes; never execute')
        (Get-TpmPatchPlan @unknownInputs).Status | Should -BeExactly 'Unavailable'
        { Invoke-TpmCatalogPatch @unknownInputs -Confirm:$false } | Should -Throw
        [IO.File]::ReadAllText($unknown.Target) | Should -BeExactly 'unknown existing DLL bytes; never execute'
    }

    It 'refuses receipt undo after same-byte replacement changes target identity' {
        & $script:mkdxFixtureSetup
        $fixture = $script:requiredPatchFixture
        $case = New-MkdxSyntheticContext -Recipe $script:mkdxFragment.Entries[0] -Fixture $fixture
        $inputs = $case.Inputs
        $applied = Invoke-TpmCatalogPatch @inputs -Confirm:$false
        $applied.Status | Should -BeExactly 'Applied'
        $receiptPath = Join-Path $applied.RecoveryDirectory 'receipt.json'
        $receipt = [IO.File]::ReadAllText($receiptPath) | ConvertFrom-Json
        $boundIdentity = [string]$receipt.Operations[0].AfterFileIdentity
        $held = Join-Path ([IO.Path]::GetDirectoryName($case.Target)) 'D3D11Ref.dll.held'
        [IO.File]::Move($case.Target, $held)
        [IO.File]::WriteAllBytes($case.Target, [byte[]]$case.PayloadBytes)
        $opened = Open-TpmPatchCreationFile $case.Target
        try { $newIdentity = [TpmSupportNativeMethods]::PatchFileIdentity($opened.SafeFileHandle) } finally { $opened.Dispose() }
        $newIdentity | Should -Not -BeExactly $boundIdentity
        { Undo-TpmCatalogPatch @inputs -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false } | Should -Throw
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($case.Target)) | Should -BeExactly ([Convert]::ToBase64String($case.PayloadBytes))
        ([IO.File]::ReadAllText($receiptPath) | ConvertFrom-Json).State | Should -BeExactly 'Applied'
    }

    It 'preserves an unrelated sibling component through apply and undo' {
        & $script:mkdxFixtureSetup
        $fixture = $script:requiredPatchFixture
        $case = New-MkdxSyntheticContext -Recipe $script:mkdxFragment.Entries[0] -Fixture $fixture
        $parent = [IO.Path]::GetDirectoryName($case.Target)
        [void][IO.Directory]::CreateDirectory($parent)
        $sibling = Join-Path $parent 'D3D11Ref.config'
        [IO.File]::WriteAllText($sibling, 'unrelated sibling bytes; preserve')
        $inputs = $case.Inputs
        $applied = Invoke-TpmCatalogPatch @inputs -Confirm:$false
        $applied.Status | Should -BeExactly 'Applied'
        [IO.File]::ReadAllText($sibling) | Should -BeExactly 'unrelated sibling bytes; preserve'
        (Undo-TpmCatalogPatch @inputs -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false).Status | Should -BeExactly 'Restored'
        [IO.File]::ReadAllText($sibling) | Should -BeExactly 'unrelated sibling bytes; preserve'
    }
}
