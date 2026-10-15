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

    $script:infinityFragmentPath=Join-Path $PSScriptRoot '..\tools\required-patches\fragments\support-infinitybladefx-main-components-20261015.json'
    $script:infinityFragment=[IO.File]::ReadAllText($script:infinityFragmentPath,[Text.Encoding]::UTF8)|ConvertFrom-Json -ErrorAction Stop

    $mainPath=Join-Path $programRoot 'TeknoParrot-Manager.ps1'
    $tokens=$null;$errors=$null
    $mainAst=[System.Management.Automation.Language.Parser]::ParseFile($mainPath,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw 'Unable to parse manager helper source for isolated Infinity Blade FX transaction proof.'}
    foreach($name in @('Get-TpmSupportNativeType','Get-TpmSupportFinalPathFromHandle','Remove-TpmSupportHandle','Test-TpmPathOverlap','Get-TpmFileState','Read-HostSafe','Read-PathWithBrowse')){
        $functionAst=$mainAst.Find({param($node)$node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$true)
        if(-not $functionAst){throw ('Missing required Infinity Blade FX proof helper: '+$name)}
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
    $script:infinityFixtureSetup=$beforeEach.CommandElements[-1].ScriptBlock.GetScriptBlock()
}

Describe 'Infinity Blade FX Main component candidates' {
    It 'binds exact 1.02 Main DLL members and excludes the separate rename/config/first-run procedure' {
        $script:infinityFragment.BaseCatalog.EntryCount | Should -Be 24
        $script:infinityFragment.BaseCatalog.Sha256 | Should -BeExactly '283DB40B0A17F3FEF2BC758D8123209B87C07731E433CECFE96DE1E2C69C5CE8'
        $script:infinityFragment.Entries.Count | Should -Be 2
        $expected=@{
            'infinity-blade-fx-matrix32-main-restore'=@{Target='Binaries/Win32/matrix32.dll';Size=109056;Sha1='355E6F9557BAFC726694DC2E40820FF8429D61FB';Sha256='CB25982F65A32E3D29B3F449BD8CCF2E4A4B47CA3096B454B6910341B213D547'}
            'infinity-blade-fx-dinput8-main-restore'=@{Target='Binaries/Win32/dinput8.dll';Size=2058752;Sha1='72E6862972409A4685545B21C0C687766F83DADC';Sha256='E7E149EE9E8B64E23B739E236E5A61CAB7F2F56E632082993A95F05DE7D6CCB1'}
        }
        foreach($entry in $script:infinityFragment.Entries){
            $pin=$expected[[string]$entry.Id]
            $pin | Should -Not -BeNullOrEmpty
            $entry.ProfileId | Should -BeExactly 'InfinityBladeFX'
            $entry.BuildName | Should -BeExactly 'Infinity Blade FX (1.02)(2020)[Adrenaline PC][TP]'
            $entry.Executable | Should -BeExactly 'Binaries/Win32/SwordGame.exe'
            $entry.ExecutableSha256 | Should -BeExactly '8E605C3748C6D3D45832F40316C1FEC35D2507E31E51A5F85DCB3B664DA72D24'
            $entry.SourceRole | Should -BeExactly 'Main'
            $entry.SourceSet | Should -BeExactly 'Infinity Blade FX (1.02)(2020)[Adrenaline PC][TP].zip'
            $entry.SourceEntry | Should -BeExactly $pin.Target
            $entry.SourceSize | Should -Be $pin.Size
            $entry.SourceSha1 | Should -BeExactly $pin.Sha1
            $entry.SourceSha1.Length | Should -Be 40
            $entry.SourceSha1 | Should -Match '^[A-F0-9]{40}$'
            $entry.SourceSha256 | Should -BeExactly $pin.Sha256
            $entry.Prerequisites.Count | Should -Be 2
            @($entry.Prerequisites | Where-Object { $_.Type -cne 'File' }).Count | Should -Be 0
            $prerequisitePaths=@($entry.Prerequisites | ForEach-Object { $_.Path })
            $prerequisitePaths | Should -Contain 'Binaries/Win32/matrix32.TEKNOPARROT.dll'
            $prerequisitePaths | Should -Contain 'Binaries/Win32/TPFIX.ini'
            @($entry.Prerequisites | ForEach-Object { $_.PSObject.Properties.Name | Where-Object { $_ -match 'Sha|Version|Section|Key|Value' } }).Count | Should -Be 0
            @($entry.Prerequisites | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.Description) }).Count | Should -Be 0
            $entry.Operations.Count | Should -Be 1
            $entry.Operations[0].Type | Should -BeExactly 'CreateFile'
            $entry.Operations[0].Target | Should -BeExactly $pin.Target
            $entry.Operations[0].BeforeState | Should -BeExactly 'Absent'
            $entry.Operations[0].AfterSha256 | Should -BeExactly $pin.Sha256
            $entry.Operations[0].PayloadSha256 | Should -BeExactly $pin.Sha256
        }
        @($script:infinityFragment.Entries.Operations.Target | Where-Object { $_ -in @('Binaries/Win32/matrix32.TEKNOPARROT.dll','Binaries/Win32/TPFIX.ini') }).Count | Should -Be 0
    }

    It 'restores each absent DLL only, skips exact repeats, receipt-undoes, and preserves sibling/config bytes' {
        foreach($recipe in $script:infinityFragment.Entries){
            & $script:infinityFixtureSetup
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
                $siblingName=if([IO.Path]::GetFileName($target) -ceq 'matrix32.dll'){'dinput8.dll'}else{'matrix32.dll'}
                $sibling=Join-Path $parent $siblingName
                $backup=Join-Path $parent 'matrix32.TEKNOPARROT.dll'
                $config=Join-Path $parent 'TPFIX.ini'
                $missing=Test-TpmRequiredPatchPrerequisites -Entry $entry -GameRoot $fixture.GameRoot
                $missing.Satisfied | Should -BeFalse
                $missing.Missing.Count | Should -Be 2
                [IO.File]::WriteAllText($backup,'foreign backup bytes; never execute')
                $missing=Test-TpmRequiredPatchPrerequisites -Entry $entry -GameRoot $fixture.GameRoot
                $missing.Satisfied | Should -BeFalse
                @($missing.Missing | Where-Object Id -CEQ 'infinity-tpfix-config').Count | Should -Be 1
                Remove-Item -LiteralPath $backup -Force
                [IO.File]::WriteAllText($config,'[DLL]'+[Environment]::NewLine+'path=foreign; never open')
                $missing=Test-TpmRequiredPatchPrerequisites -Entry $entry -GameRoot $fixture.GameRoot
                $missing.Satisfied | Should -BeFalse
                @($missing.Missing | Where-Object Id -CEQ 'infinity-original-matrix32').Count | Should -Be 1
                [IO.File]::WriteAllText($backup,'foreign backup bytes; never execute')
                $ready=Test-TpmRequiredPatchPrerequisites -Entry $entry -GameRoot $fixture.GameRoot
                $ready.Satisfied | Should -BeTrue
                $ready.Missing.Count | Should -Be 0
                [IO.File]::WriteAllText($sibling,'foreign sibling bytes; never execute')
                (Get-TpmPatchPlan @inputs).Status | Should -Be 'Ready'
                $applied=Invoke-TpmCatalogPatch @inputs -Confirm:$false
                $applied.Status | Should -Be 'Applied'
                (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash | Should -Be $payloadHash
                [IO.File]::ReadAllText($sibling) | Should -Be 'foreign sibling bytes; never execute'
                [IO.File]::ReadAllText($backup) | Should -Be 'foreign backup bytes; never execute'
                [IO.File]::ReadAllText($config) | Should -Be ('[DLL]'+[Environment]::NewLine+'path=foreign; never open')
                (Get-TpmPatchPlan @inputs).Status | Should -Be 'AlreadyApplied'
                (Invoke-TpmCatalogPatch @inputs -Confirm:$false).Status | Should -Be 'AlreadyApplied'
                (Undo-TpmCatalogPatch @inputs -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false).Status | Should -Be 'Restored'
                Test-Path -LiteralPath $target | Should -BeFalse
                [IO.File]::ReadAllText($sibling) | Should -Be 'foreign sibling bytes; never execute'
                [IO.File]::ReadAllText($backup) | Should -Be 'foreign backup bytes; never execute'
                [IO.File]::ReadAllText($config) | Should -Be ('[DLL]'+[Environment]::NewLine+'path=foreign; never open')
                [IO.File]::WriteAllText($target,'unknown foreign target bytes; never execute')
                (Get-TpmPatchPlan @inputs).Status | Should -Be 'Unavailable'
                [IO.File]::ReadAllText($target) | Should -Be 'unknown foreign target bytes; never execute'
            } finally {
                $script:TpmOwnedLayout=$priorLayout
                $script:TpmRequiredPatchCatalogSha256=$priorPin
            }
        }
    }
}
