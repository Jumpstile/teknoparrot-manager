param(
    [string]$RepositoryRoot = ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))),
    [string]$FragmentPath = (Join-Path $RepositoryRoot 'tools/required-patches/fragments/gashaaaan2-jurassic-root-dlls-20261015.json')
)

BeforeAll {
    $script:gashProgramRoot = [IO.Path]::GetFullPath($RepositoryRoot)
    $enginePath = Join-Path $script:gashProgramRoot 'scripts/TpmRequiredPatchEngine.ps1'
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

    $script:gashFragmentPath = [IO.Path]::GetFullPath($FragmentPath)
    $script:gashFragmentText = [IO.File]::ReadAllText($script:gashFragmentPath, [Text.Encoding]::UTF8)
    $script:gashFragmentFileSha256 = (Get-FileHash -LiteralPath $script:gashFragmentPath -Algorithm SHA256).Hash.ToUpperInvariant()
    $script:gashFragment = $script:gashFragmentText | ConvertFrom-Json -ErrorAction Stop

    $mainPath = Join-Path $script:gashProgramRoot 'TeknoParrot-Manager.ps1'
    $tokens = $null; $errors = $null
    $mainAst = [System.Management.Automation.Language.Parser]::ParseFile($mainPath, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw 'Unable to parse manager helper source for isolated required-patch transactions.' }
    foreach ($name in @('Get-TpmSupportNativeType', 'Get-TpmSupportFinalPathFromHandle', 'Remove-TpmSupportHandle', 'Test-TpmPathOverlap', 'Get-TpmFileState', 'Read-HostSafe', 'Read-PathWithBrowse')) {
        $function = $mainAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name }, $true)
        if (-not $function) { throw "Required manager helper '$name' was not found." }
        . ([scriptblock]::Create($function.Extent.Text))
    }
    [void](Get-TpmSupportNativeType)

    $suitePath = Join-Path $script:gashProgramRoot 'Tests/TeknoParrot-Manager.Tests.ps1'
    $suiteTokens = $null; $suiteErrors = $null
    $suiteAst = [System.Management.Automation.Language.Parser]::ParseFile($suitePath, [ref]$suiteTokens, [ref]$suiteErrors)
    if ($suiteErrors.Count) { throw 'Unable to parse the existing required-patch fixture source.' }
    $describe = $suiteAst.Find({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Describe' -and $node.CommandElements.Count -ge 3 -and $node.CommandElements[1].Value -ceq 'Required patch engine and local recipes' }, $true)
    if (-not $describe) { throw 'The existing required-patch fixture container was not found.' }
    $beforeEach = $describe.CommandElements[2].ScriptBlock.Find({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'BeforeEach' }, $true)
    if (-not $beforeEach) { throw 'The existing required-patch fixture setup was not found.' }
    $script:gashFixtureSetup = $beforeEach.CommandElements[-1].ScriptBlock.GetScriptBlock()

    function New-GashSyntheticContext {
        param([Parameter(Mandatory)]$Recipe, [Parameter(Mandatory)]$Fixture, [switch]$WrongExecutable)
        $entry = $Recipe | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $entry.ExecutableSha256 = if ($WrongExecutable) { 'F' * 64 } else { $Fixture.ExecutableSha256 }
        $syntheticExe = Join-Path $Fixture.GameRoot ($entry.Executable.Replace('/', '\'))
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($syntheticExe))
        [IO.File]::WriteAllBytes($syntheticExe,[IO.File]::ReadAllBytes($Fixture.Executable))
        $bytes = [Text.Encoding]::UTF8.GetBytes(('synthetic donor DLL bytes for ' + [string]$entry.Id + '; never execute'))
        $payloadRelative = 'payload/' + [string]$entry.SourceEntry
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

Describe 'Gashaaaan 2 Jurassic Park root DLL absent-only restorations' {
    AfterEach { $script:TpmOwnedLayout = $null }
    It 'binds the exact profile, executable, Main source members, catalog base and absent-only operations' {
        $script:gashFragment.Schema | Should -BeExactly 'TPM.RequiredPatch.ManagedPluginFragment.v1'
        $script:gashFragmentFileSha256 | Should -Match '^[A-F0-9]{64}$'
        $script:gashFragment.BaseCatalog.Schema | Should -Be 3
        $script:gashFragment.BaseCatalog.EntryCount | Should -Be 69
        $script:gashFragment.BaseCatalog.Sha256 | Should -BeExactly 'A097875B605418D76540A1547235C3F03898D3608300BC017694015FDD76CA12'
        $entries = @($script:gashFragment.Entries)
        $entries.Count | Should -Be 3
        $expected = @(
            @{Id='gashaaaan2-jurassic-libogg-create';Name='libogg.dll';Size=21504;Sha1='DE9DB7F730A0B8273FE2D3ADB3AC6C56510C8972';Sha256='E6B423A237ED5C1E2503F1B3E48855061A74343BDD8BBDB5DAD004C234513328'},
            @{Id='gashaaaan2-jurassic-libvorbis-create';Name='libvorbis.dll';Size=667648;Sha1='1537A1D208F2C5DC756B394393C9A3C77E962D95';Sha256='971A471C5A7710BBFDAAA62D7A31EBC094B359FD374D015B602679E7CFEEAD69'},
            @{Id='gashaaaan2-jurassic-libvorbisfile-create';Name='libvorbisfile.dll';Size=33792;Sha1='AE4F5F737532CE4774332733889BD62FF71BE596';Sha256='76E8A51A1E2F9FFC42D00A53F1214D4653B13182BDD30A154BBB9AE2853A8B97'}
        )
        for($i=0;$i -lt 3;$i++){
            $entry=$entries[$i];$item=$expected[$i]
            $entry.Id | Should -BeExactly $item.Id
            $entry.ProfileId | Should -BeExactly 'Gashaaaan2'
            $entry.BuildName | Should -BeExactly 'Gashaaaan Refill! (2009-02-24)(JPN)[Konami PC][TP]'
            $entry.Executable | Should -BeExactly 'IG2/exec_root/gasya.exe'
            $entry.ExecutableSha256 | Should -BeExactly '67BDEBF22D64E997A59423EC68A36CF234F0060B4FB32BAFBCE6E5A6C2D5FEB6'
            $entry.SourceUrl | Should -BeExactly ''
            $entry.SourceRevision | Should -BeExactly ''
            $entry.SourceRole | Should -BeExactly 'Main'
            $entry.SourceSet | Should -BeExactly 'Jurassic Park (1.08)(2015)[Raw Thrills Linux PC][TP].zip'
            $entry.SourceEntry | Should -BeExactly $item.Name
            $entry.SourceSize | Should -Be $item.Size
            $entry.SourceSha1 | Should -BeExactly $item.Sha1
            $entry.SourceSha256 | Should -BeExactly $item.Sha256
            @($entry.Operations).Count | Should -Be 1
            $entry.Operations[0].Type | Should -BeExactly 'CreateFile'
            $entry.Operations[0].Target | Should -BeExactly ('IG2/exec_root/' + $item.Name)
            $entry.Operations[0].BeforeState | Should -BeExactly 'Absent'
            $entry.Operations[0].AfterSha256 | Should -BeExactly $item.Sha256
            $entry.Operations[0].PayloadSha256 | Should -BeExactly $item.Sha256
        }
    }

    It 'stages, applies, repeat-no-ops and receipt-undoes each of the three files independently' {
        Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
        foreach($recipe in @($script:gashFragment.Entries)){
            & $script:gashFixtureSetup
            $fixture=$script:requiredPatchFixture
            $case=New-GashSyntheticContext -Recipe $recipe -Fixture $fixture
            $sourceRoot=Join-Path $fixture.Root 'gash-source'
            [void][IO.Directory]::CreateDirectory($sourceRoot)
            $archivePath=Join-Path $sourceRoot $recipe.SourceSet
            $archive=[IO.Compression.ZipFile]::Open($archivePath,[IO.Compression.ZipArchiveMode]::Create)
            try{$member=$archive.CreateEntry($recipe.SourceEntry,[IO.Compression.CompressionLevel]::Optimal);$stream=$member.Open();try{$stream.Write($case.PayloadBytes,0,$case.PayloadBytes.Length)}finally{$stream.Dispose()}}finally{$archive.Dispose()}
            $owned=Join-Path $fixture.Root 'owned'
            $temp=Join-Path $owned 'Temp'
            [void][IO.Directory]::CreateDirectory($temp)
            $script:TpmOwnedLayout=[pscustomobject]@{Root=$owned;Temp=$temp;Backups=(Join-Path $owned 'Backups')}
            $stage=New-TpmRequiredPatchPayloadStage -Entry $case.Entry -SourceRoot $sourceRoot
            $stage.SourceEntry | Should -BeExactly $recipe.SourceEntry
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($stage.Payload)) | Should -BeExactly ([Convert]::ToBase64String($case.PayloadBytes))
            $inputs=$case.Inputs
            $inputs.PayloadRoot=$stage.Root
            try {
                $applied=Invoke-TpmCatalogPatch @inputs -Confirm:$false
                $applied.Status | Should -BeExactly 'Applied'
                (Get-FileHash -LiteralPath $case.Target -Algorithm SHA256).Hash | Should -BeExactly $case.PayloadSha256
                (Invoke-TpmCatalogPatch @inputs -Confirm:$false).Status | Should -BeExactly 'AlreadyApplied'
                (Undo-TpmCatalogPatch @inputs -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false).Status | Should -BeExactly 'Restored'
                Test-Path -LiteralPath $case.Target | Should -BeFalse
            } finally {
                if ((Test-PathInside $stage.Root $script:TpmOwnedLayout.Temp) -and (Test-Path -LiteralPath $stage.Root) -and (Test-TpmNoReparsePath $stage.Root)) {
                    Remove-Item -LiteralPath $stage.Root -Recurse -Force -ErrorAction Stop
                    if (Test-Path -LiteralPath $stage.Root) { throw 'The staged directory remains after cleanup.' }
                }
            }
        }
    }

    It 'refuses wrong executable identity and unknown pre-existing bytes without mutation' {
        & $script:gashFixtureSetup
        $fixture=$script:requiredPatchFixture
        $wrong=New-GashSyntheticContext -Recipe $script:gashFragment.Entries[0] -Fixture $fixture -WrongExecutable
        $wrongInputs=$wrong.Inputs
        (Get-TpmPatchPlan @wrongInputs).Status | Should -BeExactly 'Unavailable'
        {Invoke-TpmCatalogPatch @wrongInputs -Confirm:$false} | Should -Throw
        Test-Path -LiteralPath $wrong.Target | Should -BeFalse

        & $script:gashFixtureSetup
        $fixture=$script:requiredPatchFixture
        $unknown=New-GashSyntheticContext -Recipe $script:gashFragment.Entries[0] -Fixture $fixture
        $unknownInputs=$unknown.Inputs
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($unknown.Target))
        [IO.File]::WriteAllText($unknown.Target,'unknown existing DLL bytes; never execute')
        (Get-TpmPatchPlan @unknownInputs).Status | Should -BeExactly 'Unavailable'
        {Invoke-TpmCatalogPatch @unknownInputs -Confirm:$false} | Should -Throw
        [IO.File]::ReadAllText($unknown.Target) | Should -BeExactly 'unknown existing DLL bytes; never execute'
    }

    It 'rejects target traversal and verifies real path containment helpers' {
        & $script:gashFixtureSetup
        $fixture=$script:requiredPatchFixture
        $case=New-GashSyntheticContext -Recipe $script:gashFragment.Entries[0] -Fixture $fixture
        $inside=Join-Path $fixture.GameRoot 'IG2/exec_root/libogg.dll'
        $outside=Join-Path ([IO.Path]::GetDirectoryName($fixture.GameRoot)) 'outside.dll'
        (Test-PathInside $inside $fixture.GameRoot) | Should -BeTrue
        (Test-PathInside $outside $fixture.GameRoot) | Should -BeFalse
        (Test-TpmNoReparsePath $fixture.GameRoot) | Should -BeTrue
        $bad=$case.Entry | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $bad.Operations[0].Target='../outside.dll'
        $content=[pscustomobject]@{Schema=3;Entries=@($bad)} | ConvertTo-Json -Depth 20 -Compress
        $inputs=$case.Inputs
        $inputs.CatalogContent=$content
        $inputs.CatalogSha256=Get-TpmPatchTextSha256 $content
        (Get-TpmPatchPlan @inputs).Status | Should -BeExactly 'Unavailable'
        {Invoke-TpmCatalogPatch @inputs -Confirm:$false} | Should -Throw
        Test-Path -LiteralPath $outside | Should -BeFalse
    }

    It 'preserves unrelated siblings and refuses receipt undo after same-byte target replacement' {
        & $script:gashFixtureSetup
        $fixture=$script:requiredPatchFixture
        $case=New-GashSyntheticContext -Recipe $script:gashFragment.Entries[1] -Fixture $fixture
        $parent=[IO.Path]::GetDirectoryName($case.Target)
        [void][IO.Directory]::CreateDirectory($parent)
        $sibling=Join-Path $parent 'unrelated.config'
        [IO.File]::WriteAllText($sibling,'preserve sibling bytes')
        $inputs=$case.Inputs
        $applied=Invoke-TpmCatalogPatch @inputs -Confirm:$false
        $applied.Status | Should -BeExactly 'Applied'
        [IO.File]::ReadAllText($sibling) | Should -BeExactly 'preserve sibling bytes'
        $receiptPath=Join-Path $applied.RecoveryDirectory 'receipt.json'
        $receipt=[IO.File]::ReadAllText($receiptPath)|ConvertFrom-Json
        $boundIdentity=[string]$receipt.Operations[0].AfterFileIdentity
        $held=Join-Path $parent 'libvorbis.dll.held'
        [IO.File]::Move($case.Target,$held)
        [IO.File]::WriteAllBytes($case.Target,[byte[]]$case.PayloadBytes)
        $opened=Open-TpmPatchCreationFile $case.Target
        try{$newIdentity=[TpmSupportNativeMethods]::PatchFileIdentity($opened.SafeFileHandle)}finally{$opened.Dispose()}
        $newIdentity | Should -Not -BeExactly $boundIdentity
        {Undo-TpmCatalogPatch @inputs -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false} | Should -Throw
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($case.Target)) | Should -BeExactly ([Convert]::ToBase64String($case.PayloadBytes))
        ([IO.File]::ReadAllText($receiptPath)|ConvertFrom-Json).State | Should -BeExactly 'Applied'
        [IO.File]::ReadAllText($sibling) | Should -BeExactly 'preserve sibling bytes'
    }
}
