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
            return $c.StartsWith($p+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or $c.Equals($p,[StringComparison]::OrdinalIgnoreCase)
        } catch { return $false }
    }

    function Test-TpmNoReparsePath {
        param([string]$Path)
        try {
            $full=[IO.Path]::GetFullPath($Path)
            $root=[IO.Path]::GetPathRoot($full)
            $current=$root
            $relative=$full.Substring($root.Length)
            foreach($part in ($relative -split '[\\/]')){
                if([string]::IsNullOrWhiteSpace($part)){continue}
                $current=Join-Path $current $part
                if(Test-Path -LiteralPath $current){
                    $item=Get-Item -LiteralPath $current -Force
                    if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return $false}
                }
            }
            return $true
        } catch { return $false }
    }

    $script:mainExtrasFragmentPath=Join-Path $PSScriptRoot '..\tools\required-patches\fragments\main-component-restores-followup-20261015.json'
    $script:mainExtrasFragment=[IO.File]::ReadAllText($script:mainExtrasFragmentPath,[Text.Encoding]::UTF8)|ConvertFrom-Json -ErrorAction Stop
    $script:mainExtrasCatalogPath=Join-Path $programRoot 'scripts\TpmRequiredPatchRecipes.json'
    $script:mainExtrasCatalog=[IO.File]::ReadAllText($script:mainExtrasCatalogPath,[Text.Encoding]::UTF8)|ConvertFrom-Json -ErrorAction Stop

    $mainPath=Join-Path $programRoot 'TeknoParrot-Manager.ps1'
    $tokens=$null;$errors=$null
    $mainAst=[System.Management.Automation.Language.Parser]::ParseFile($mainPath,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw 'Unable to parse manager helper source for isolated Main-component transaction proof.'}
    foreach($name in @('Get-TpmSupportNativeType','Get-TpmSupportFinalPathFromHandle','Remove-TpmSupportHandle','Test-TpmPathOverlap','Get-TpmFileState','Read-HostSafe','Read-PathWithBrowse')){
        $function=$mainAst.Find({param($node)$node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$true)
        if(-not $function){throw "Required manager helper '$name' was not found."}
        . ([scriptblock]::Create($function.Extent.Text))
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
    $script:mainExtrasFixtureSetup=$beforeEach.CommandElements[-1].ScriptBlock.GetScriptBlock()
}

Describe 'MaiMai GreeN and Rabbids Hollywood Main-component restores' {
    It 'binds three exact source members and the integrated 62-entry catalog' {
        $script:mainExtrasFragment.BaseCatalog.EntryCount | Should -Be 58
        $script:mainExtrasFragment.BaseCatalog.Sha256 | Should -BeExactly 'F86F09A8BD2749DC9C4531CD1D00A69BF07D85B14A8D281D33767732ED5B720A'
        $script:mainExtrasFragment.Entries.Count | Should -Be 3
        $script:mainExtrasCatalog.Schema | Should -Be 3
        $script:mainExtrasCatalog.Entries.Count | Should -Be 62
        @($script:mainExtrasCatalog.Entries.Id | Sort-Object -Unique).Count | Should -Be 62
        @($script:mainExtrasCatalog.Entries.ProfileId | Sort-Object -Unique).Count | Should -Be 23
        @($script:mainExtrasCatalog.Entries | Where-Object { $_.Operations[0].Type -ceq 'CreateFile' }).Count | Should -Be 54
        @($script:mainExtrasCatalog.Entries | Where-Object { $_.Operations[0].Type -ceq 'ReplaceFile' }).Count | Should -Be 8
        (Get-FileHash -LiteralPath $script:mainExtrasCatalogPath -Algorithm SHA256).Hash | Should -BeExactly $script:TpmRequiredPatchCatalogSha256
        $expected=@{
            'maimai-green-freeglut-main-restore'=@{Profile='MaiMaiGreen';Build='maimai GreeN (2013)[Sega RingEdge 2][TP]';Executable='maimai/maimai_dump_.exe';ExeSha256='B2027449C536FEE6853F3B72E28188AB47D36AAF8800FFDA30617B36D0031029';SourceSet='maimai GreeN (2013)[Sega RingEdge 2][TP].zip';Member='maimai/freeglut.dll';Size=218624;Sha1='C06C86B2D660C60DD9C57DEF62E7D9DB9960DE27';Sha256='C0968C2D0D9DB9263304A7E0B86F41125A9642E20EA96741B9F75F15E424298E'}
            'maimai-green-libcurl-main-restore'=@{Profile='MaiMaiGreen';Build='maimai GreeN (2013)[Sega RingEdge 2][TP]';Executable='maimai/maimai_dump_.exe';ExeSha256='B2027449C536FEE6853F3B72E28188AB47D36AAF8800FFDA30617B36D0031029';SourceSet='maimai GreeN (2013)[Sega RingEdge 2][TP].zip';Member='maimai/libcurl.dll';Size=325632;Sha1='DEAD9B68373A54EF43E63BC10CD651CF8D320264';Sha256='D86C6E191F0411DE94EA0724DE1C26E7EA58ED1564A6438006B111C07D05BEEE'}
            'rabbids-hollywood-operator-main-restore'=@{Profile='RabbidsHollywood';Build='Rabbids Hollywood (2018)[Adrenaline PC][TP]';Executable='Game.exe';ExeSha256='979F9736A99745454429908227CDD2F48875F193D439CFA33A9E14B4578DA95D';SourceSet='Rabbids Hollywood (2018)[Adrenaline PC][TP].zip';Member='RabbidsHollywood_Operator.exe';Size=503296;Sha1='5B2046A677A426B56AF20F873305B52826FFD00F';Sha256='B3622686EF6CE75F17805137857417B6F1B50A2AE962E979B20AAE67E69777B7'}
        }
        foreach($entry in $script:mainExtrasFragment.Entries){
            $pin=$expected[[string]$entry.Id]
            $pin | Should -Not -BeNullOrEmpty
            $entry.ProfileId | Should -BeExactly $pin.Profile
            $entry.BuildName | Should -BeExactly $pin.Build
            $entry.Executable | Should -BeExactly $pin.Executable
            $entry.ExecutableSha256 | Should -BeExactly $pin.ExeSha256
            $entry.SourceRole | Should -BeExactly 'Main'
            $entry.SourceSet | Should -BeExactly $pin.SourceSet
            $entry.SourceEntry | Should -BeExactly $pin.Member
            $entry.SourceSize | Should -Be $pin.Size
            $entry.SourceSha1 | Should -BeExactly $pin.Sha1
            $entry.SourceSha1.Length | Should -Be 40
            $entry.SourceSha1 | Should -Match '^[A-F0-9]{40}$'
            $entry.SourceSha256 | Should -BeExactly $pin.Sha256
            @($entry.Prerequisites).Count | Should -Be 0
            $entry.Operations.Count | Should -Be 1
            $entry.Operations[0].Type | Should -BeExactly 'CreateFile'
            $entry.Operations[0].Target | Should -BeExactly $pin.Member
            $entry.Operations[0].BeforeState | Should -BeExactly 'Absent'
            $entry.Operations[0].AfterSha256 | Should -BeExactly $pin.Sha256
            $entry.Operations[0].PayloadSha256 | Should -BeExactly $pin.Sha256
            $catalogMatches=@($script:mainExtrasCatalog.Entries | Where-Object { $_.Id -ceq $entry.Id })
            $catalogMatches.Count | Should -Be 1
            ($catalogMatches[0] | ConvertTo-Json -Depth 20 -Compress) | Should -BeExactly ($entry | ConvertTo-Json -Depth 20 -Compress)
        }
    }

    It 'applies each absent component, skips exact repeats, receipt-undos, and preserves foreign target bytes' {
        foreach($recipe in $script:mainExtrasFragment.Entries){
            & $script:mainExtrasFixtureSetup
            $fixture=$script:requiredPatchFixture
            $entry=$recipe|ConvertTo-Json -Depth 20|ConvertFrom-Json
            $priorPin=$script:TpmRequiredPatchCatalogSha256
            $priorLayout=$script:TpmOwnedLayout
            try {
                $entry.Executable='synthetic.exe'
                $entry.ExecutableSha256=$fixture.ExecutableSha256
                $entry.SourceRole='Main'
                $entry.SourceSet='Synthetic Main.zip'
                $payloadRelative='payload/'+$entry.Id+'.bin'
                $payload=Join-Path $fixture.PayloadRoot $payloadRelative
                [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($payload))
                [IO.File]::Copy($fixture.CreatedPayload,$payload,$true)
                $payloadHash=(Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash
                $entry.SourceSize=[int](Get-Item -LiteralPath $payload).Length
                $entry.SourceSha1=(Get-FileHash -LiteralPath $payload -Algorithm SHA1).Hash
                $entry.SourceSha256=$payloadHash
                $entry.Operations[0].Payload=$payloadRelative
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
                $parent=[IO.Path]::GetDirectoryName($target)
                if([IO.Directory]::Exists($parent)){
                    (Get-TpmPatchPlan @inputs).Status | Should -Be 'Ready'
                } else {
                    (Get-TpmPatchPlan @inputs).Status | Should -Be 'Unavailable'
                    [void][IO.Directory]::CreateDirectory($parent)
                }
                (Get-TpmPatchPlan @inputs).Status | Should -Be 'Ready'
                $applied=Invoke-TpmCatalogPatch @inputs -Confirm:$false
                $applied.Status | Should -Be 'Applied'
                (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash | Should -Be $payloadHash
                (Get-TpmPatchPlan @inputs).Status | Should -Be 'AlreadyApplied'
                (Invoke-TpmCatalogPatch @inputs -Confirm:$false).Status | Should -Be 'AlreadyApplied'
                (Undo-TpmCatalogPatch @inputs -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false).Status | Should -Be 'Restored'
                Test-Path -LiteralPath $target | Should -BeFalse
                [IO.File]::WriteAllText($target,'foreign target bytes; never execute')
                (Get-TpmPatchPlan @inputs).Status | Should -Be 'Unavailable'
                [IO.File]::ReadAllText($target) | Should -Be 'foreign target bytes; never execute'
            } finally {
                $script:TpmOwnedLayout=$priorLayout
                $script:TpmRequiredPatchCatalogSha256=$priorPin
            }
        }
    }
}
