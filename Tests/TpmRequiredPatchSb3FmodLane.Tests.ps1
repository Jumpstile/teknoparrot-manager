BeforeAll {
    $programRoot = [string]$env:TPM_RECIPE_TEST_PROGRAM_ROOT
    if ([string]::IsNullOrWhiteSpace($programRoot)) {
        $programRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    } else {
        $programRoot = [IO.Path]::GetFullPath($programRoot)
    }
    $enginePath = Join-Path $programRoot 'scripts\TpmRequiredPatchEngine.ps1'
    if (-not (Test-Path -LiteralPath $enginePath -PathType Leaf)) {
        throw 'Required-patch engine is unavailable under TPM_RECIPE_TEST_PROGRAM_ROOT.'
    }
    . $enginePath

    function Test-PathInside {
        param([string]$child,[string]$parent)
        try {
            $c=[IO.Path]::GetFullPath($child).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
            $p=[IO.Path]::GetFullPath($parent).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
            return $c.Equals($p,[StringComparison]::OrdinalIgnoreCase) -or
                $c.StartsWith(($p+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase) -or
                $c.StartsWith(($p+[IO.Path]::AltDirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)
        } catch { return $false }
    }

    function Test-TpmNoReparsePath {
        param([string]$Path)
        try {
            if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
            $cursorPath=[IO.Path]::GetFullPath($Path)
            while (-not (Test-Path -LiteralPath $cursorPath)) {
                $parentPath=[IO.Path]::GetDirectoryName($cursorPath)
                if ([string]::IsNullOrWhiteSpace($parentPath) -or $parentPath -eq $cursorPath) { return $false }
                $cursorPath=$parentPath
            }
            $cursor=Get-Item -LiteralPath $cursorPath -Force -ErrorAction Stop
            while ($cursor) {
                if (($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
                $cursor=$cursor.Parent
            }
            return $true
        } catch { return $false }
    }

    $script:fmodFragmentPath=Join-Path $PSScriptRoot '..\tools\required-patches\fragments\plugins-sb3-fmod-components-20261015.json'
    $script:fmodFragment=[IO.File]::ReadAllText($script:fmodFragmentPath,[Text.Encoding]::UTF8)|ConvertFrom-Json -ErrorAction Stop

    $mainPath=Join-Path $programRoot 'TeknoParrot-Manager.ps1'
    $tokens=$null;$errors=$null
    $mainAst=[System.Management.Automation.Language.Parser]::ParseFile($mainPath,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw 'Unable to parse manager helper source for isolated FMOD transaction proof.'}
    foreach($name in @('Get-TpmSupportNativeType','Get-TpmSupportFinalPathFromHandle','Remove-TpmSupportHandle','Test-TpmPathOverlap','Get-TpmFileState','Read-HostSafe','Read-PathWithBrowse')){
        $functionAst=$mainAst.Find({param($node)$node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$true)
        if(-not $functionAst){throw ('Missing required FMOD proof helper: '+$name)}
        . ([scriptblock]::Create($functionAst.Extent.Text))
    }
    [void](Get-TpmSupportNativeType)

    $suitePath=Join-Path $programRoot 'Tests\TeknoParrot-Manager.Tests.ps1'
    $suiteTokens=$null;$suiteErrors=$null
    $suiteAst=[System.Management.Automation.Language.Parser]::ParseFile($suitePath,[ref]$suiteTokens,[ref]$suiteErrors)
    if($suiteErrors.Count){throw 'Unable to parse the existing required-patch fixture source.'}
    $describe=$suiteAst.Find({param($node)$node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Describe' -and $node.CommandElements.Count -ge 3 -and $node.CommandElements[1].Value -ceq 'Required patch engine and local recipes'},$true)
    if(-not $describe){throw 'The existing required-patch fixture container was not found.'}
    $beforeEach=$describe.CommandElements[2].ScriptBlock.Find({param($node)$node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'BeforeEach'},$true)
    if(-not $beforeEach){throw 'The existing required-patch fixture setup was not found.'}
    $script:fmodFixtureSetup=$beforeEach.CommandElements[-1].ScriptBlock.GetScriptBlock()
}

Describe 'SB3 FMOD Main-component fragment' {
    It 'binds both exact x64 component members to the 1.91 Main build and absent-only targets' {
        $script:fmodFragment.BaseCatalog.EntryCount | Should -Be 24
        $script:fmodFragment.BaseCatalog.Sha256 | Should -BeExactly '283DB40B0A17F3FEF2BC758D8123209B87C07731E433CECFE96DE1E2C69C5CE8'
        $script:fmodFragment.Entries.Count | Should -Be 2
        $expected=@{
            'sb3-fmod64-main-restore'=@{Target='fnfmega_Data/Plugins/x86_64/fmod64.dll';Size=1755648;Sha1='F062F4158722FC833D470DAF2BD7333AC003A958';Sha256='E3508221439C073EC01391680D14125C7B72BB32280BDC0A90D980A2AE143FD2'}
            'sb3-fmodstudio64-main-restore'=@{Target='fnfmega_Data/Plugins/x86_64/fmodstudio64.dll';Size=1419264;Sha1='A3A614C1EA5891FEEEA06EC86FD7BA1DA441C853';Sha256='CFE1D74BB4EA8BFD842EE8CBCCB3FDE61F366AD0BB01AF59965CCF304425DBAB'}
        }
        foreach($entry in $script:fmodFragment.Entries){
            $pin=$expected[[string]$entry.Id]
            $pin | Should -Not -BeNullOrEmpty
            $entry.ProfileId | Should -BeExactly 'SB3'
            $entry.BuildName | Should -BeExactly 'Super Bikes 3 (1.91 x64)(2021-10-01)[Raw Thrills][TP]'
            $entry.Executable | Should -BeExactly 'fnfmega.exe'
            $entry.ExecutableSha256 | Should -BeExactly '7F84AE68A35587EA87312ED59247EB0379F00826B8F2473A09155792A90AEEAD'
            $entry.SourceRole | Should -BeExactly 'Main'
            $entry.SourceSet | Should -BeExactly 'Super Bikes 3 (1.91 x64)(2021-10-01)[Raw Thrills PC][TP].zip'
            $entry.SourceEntry | Should -BeExactly $pin.Target
            $entry.SourceSize | Should -Be $pin.Size
            $entry.SourceSha1 | Should -BeExactly $pin.Sha1
            $entry.SourceSha1.Length | Should -Be 40
            $entry.SourceSha1 | Should -Match '^[A-F0-9]{40}$'
            $entry.SourceSha256 | Should -BeExactly $pin.Sha256
            $entry.ExclusiveGroup | Should -BeExactly ''
            $entry.Prerequisites.Count | Should -Be 0
            $entry.Operations.Count | Should -Be 1
            $entry.Operations[0].Type | Should -BeExactly 'CreateFile'
            $entry.Operations[0].Target | Should -BeExactly $pin.Target
            $entry.Operations[0].BeforeState | Should -BeExactly 'Absent'
            $entry.Operations[0].AfterSha256 | Should -BeExactly $pin.Sha256
            $entry.Operations[0].PayloadSha256 | Should -BeExactly $pin.Sha256
        }
    }

    It 'applies each absent component, skips exact repeats, receipt-undoes, and preserves foreign bytes' {
        foreach($recipe in $script:fmodFragment.Entries){
            & $script:fmodFixtureSetup
            $fixture=$script:requiredPatchFixture
            $entry=$recipe|ConvertTo-Json -Depth 20|ConvertFrom-Json
            $priorPin=$script:TpmRequiredPatchCatalogSha256
            $priorLayout=$script:TpmOwnedLayout
            try {
                $entry.Executable='synthetic.exe'
                $entry.ExecutableSha256=$fixture.ExecutableSha256
                $entry.SourceRole='Main'
                $entry.SourceSet='Synthetic Main.zip'
                $payload=Join-Path $fixture.PayloadRoot ('payload/'+[IO.Path]::GetFileName($entry.Operations[0].Target))
                [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($payload))
                [IO.File]::Copy($fixture.CreatedPayload,$payload,$true)
                $payloadHash=(Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash
                $entry.SourceSize=[int](Get-Item -LiteralPath $payload).Length
                $entry.SourceSha1=(Get-FileHash -LiteralPath $payload -Algorithm SHA1).Hash
                $entry.SourceSha256=$payloadHash
                $entry.Operations[0].Payload='payload/'+[IO.Path]::GetFileName($entry.Operations[0].Target)
                $entry.Operations[0].AfterSha256=$payloadHash
                $entry.Operations[0].PayloadSha256=$payloadHash
                $content=[pscustomobject]@{Schema=3;Entries=@($entry)}|ConvertTo-Json -Depth 20
                $catalogHash=Get-TpmPatchTextSha256 $content
                $target=Join-Path $fixture.GameRoot ($entry.Operations[0].Target.Replace('/','\'))
                $inputs=@{
                    CatalogContent=$content;CatalogSha256=$catalogHash;PatchId=$entry.Id;ProfileId=$entry.ProfileId
                    GameRoot=$fixture.GameRoot;PayloadRoot=$fixture.PayloadRoot;RecoveryRoot=$fixture.RecoveryRoot
                    ProtectedRoots=@($fixture.ProtectedRoot)
                }
                (Get-TpmPatchPlan @inputs).Status | Should -Be 'Unavailable'
                $parent=[IO.Path]::GetDirectoryName($target)
                [void][IO.Directory]::CreateDirectory($parent)
                $siblingName=if([IO.Path]::GetFileName($target) -ceq 'fmod64.dll'){'fmodstudio64.dll'}else{'fmod64.dll'}
                $sibling=Join-Path $parent $siblingName
                [IO.File]::WriteAllText($sibling,'foreign sibling bytes; never execute')
                (Get-TpmPatchPlan @inputs).Status | Should -Be 'Ready'
                $applied=Invoke-TpmCatalogPatch @inputs -Confirm:$false
                $applied.Status | Should -Be 'Applied'
                (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash | Should -Be $payloadHash
                [IO.File]::ReadAllText($sibling) | Should -Be 'foreign sibling bytes; never execute'
                (Get-TpmPatchPlan @inputs).Status | Should -Be 'AlreadyApplied'
                (Invoke-TpmCatalogPatch @inputs -Confirm:$false).Status | Should -Be 'AlreadyApplied'
                (Undo-TpmCatalogPatch @inputs -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false).Status | Should -Be 'Restored'
                Test-Path -LiteralPath $target | Should -BeFalse
                [IO.File]::ReadAllText($sibling) | Should -Be 'foreign sibling bytes; never execute'
                [IO.File]::WriteAllText($target,'foreign synthetic bytes; never execute')
                (Get-TpmPatchPlan @inputs).Status | Should -Be 'Unavailable'
                [IO.File]::ReadAllText($target) | Should -Be 'foreign synthetic bytes; never execute'
            } finally {
                $script:TpmOwnedLayout=$priorLayout
                $script:TpmRequiredPatchCatalogSha256=$priorPin
            }
        }
    }
}
