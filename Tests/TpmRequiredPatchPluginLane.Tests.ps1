BeforeAll {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    . (Join-Path $PSScriptRoot '..\scripts\TpmRequiredPatchEngine.ps1')

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

    $script:pluginFragmentPath=Join-Path $PSScriptRoot '..\tools\required-patches\fragments\plugins-20261015.json'
    $script:pluginFragment=Get-Content -LiteralPath $script:pluginFragmentPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop

    function New-PluginLaneSyntheticZip {
        param([string]$Path,[string]$Member,[byte[]]$Bytes)
        $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        $zip=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
        try {
            $entry=$zip.CreateEntry($Member,[IO.Compression.CompressionLevel]::Optimal)
            $output=$entry.Open()
            try { $output.Write($Bytes,0,$Bytes.Length) } finally { $output.Dispose() }
        } finally { $zip.Dispose();$stream.Dispose() }
    }
    $mainScriptPath=Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $parseTokens=$null;$parseErrors=$null
    $mainAst=[System.Management.Automation.Language.Parser]::ParseFile($mainScriptPath,[ref]$parseTokens,[ref]$parseErrors)
    if($parseErrors.Count){throw 'Unable to parse manager helper source for isolated transaction tests.'}
    foreach($functionName in @('Get-TpmSupportNativeType','Get-TpmSupportFinalPathFromHandle','Remove-TpmSupportHandle','Test-TpmPathOverlap','Get-TpmFileState','Read-HostSafe','Read-PathWithBrowse')){
        $functionAst=$mainAst.Find({param($node)$node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $functionName},$true)
        if(-not $functionAst){throw ('Missing required synthetic-test helper: '+$functionName)}
        . ([scriptblock]::Create($functionAst.Extent.Text))
    }
    [void](Get-TpmSupportNativeType)

    $suitePath=Join-Path $PSScriptRoot 'TeknoParrot-Manager.Tests.ps1'
    $suiteTokens=$null;$suiteErrors=$null
    $suiteAst=[System.Management.Automation.Language.Parser]::ParseFile($suitePath,[ref]$suiteTokens,[ref]$suiteErrors)
    if($suiteErrors.Count){throw 'Unable to parse the existing required-patch fixture source.'}
    $requiredDescribe=$suiteAst.Find({param($node)$node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Describe' -and $node.CommandElements.Count -ge 3 -and $node.CommandElements[1].Value -ceq 'Required patch engine and local recipes'},$true)
    if(-not $requiredDescribe){throw 'The existing required-patch fixture container was not found.'}
    $requiredBlock=$requiredDescribe.CommandElements[2].ScriptBlock
    $fixtureSetup=$requiredBlock.Find({param($node)$node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'BeforeEach'},$true)
    if(-not $fixtureSetup){throw 'The existing required-patch fixture setup was not found.'}
    $setupBlock=$fixtureSetup.CommandElements[-1].ScriptBlock
    if(-not $setupBlock){throw 'The existing required-patch fixture block could not be extracted.'}
    $script:pluginLaneRequiredPatchFixtureSetup=$setupBlock.GetScriptBlock()
}

Describe 'Managed plugin recipe fragment' {
    It 'contains exact-build absent-only Mars and Rabbids plugin recipes with aligned source and target pins' {
        $mars=@($script:pluginFragment.Entries | Where-Object Id -CEQ 'mars-sortie-bepinex-plugin-restore')
        $rabbids=@($script:pluginFragment.Entries | Where-Object Id -CEQ 'rabbids-hollywood-bepinex-operator-plugin-restore')
        $mars.Count | Should -Be 1
        $rabbids.Count | Should -Be 1
        $script:pluginFragment.Entries.Count | Should -Be 2
        $mars[0].ProfileId | Should -BeExactly 'MarsSortie'
        $mars[0].BuildName | Should -BeExactly 'Mars Sortie (1.46.9)(2018)[UDC PC][TP]'
        $mars[0].ExecutableSha256 | Should -BeExactly '08541DCD067D7BB3BBE42BEAF2F1B5224C762FC347B71FC7A7308D7430384372'
        $mars[0].SourceRole | Should -BeExactly 'UserSelected'
        $mars[0].SourceSha256 | Should -BeExactly $mars[0].Operations[0].AfterSha256
        $mars[0].SourceSha256 | Should -BeExactly $mars[0].Operations[0].PayloadSha256
        $mars[0].Operations[0].Type | Should -BeExactly 'CreateFile'
        $mars[0].Operations[0].BeforeState | Should -BeExactly 'Absent'
        $mars[0].Prerequisites[0].Path | Should -BeExactly 'BepInEx/core/BepInEx.dll'
        $rabbids[0].ProfileId | Should -BeExactly 'RabbidsHollywood'
        $rabbids[0].ExecutableSha256 | Should -BeExactly '979F9736A99745454429908227CDD2F48875F193D439CFA33A9E14B4578DA95D'
        $rabbids[0].SourceEntry | Should -BeExactly 'BepInEx/plugins/UnityPlugin_BepInEx_RHA.dll'
        $rabbids[0].SourceSize | Should -Be 15360
        $rabbids[0].SourceSha1 | Should -BeExactly '25F9142BC4CDC364A5D2348606D0C513C86C9610'
        $rabbids[0].SourceSet | Should -BeExactly 'Rabbids Hollywood (2018) - BepInEx Operator Configuration Pack.zip'
        $rabbids[0].Operations[0].Target | Should -BeExactly 'BepInEx/plugins/UnityPlugin_BepInEx_RHA.dll'
        $rabbids[0].SourceSha256 | Should -BeExactly 'C3DEDA497E160652A1F0D3D99892A4F534A88D61358DBA5192003FF519D5E8EB'
        $rabbids[0].SourceSha256 | Should -BeExactly $rabbids[0].Operations[0].AfterSha256
        $rabbids[0].Operations[0].Type | Should -BeExactly 'CreateFile'
        $rabbids[0].Operations[0].BeforeState | Should -BeExactly 'Absent'
        $rabbids[0].Prerequisites[0].Path | Should -BeExactly 'BepInEx/core/BepInEx.dll'
    }

    It 'records exact Main matches and holds SB3 without an official profile binding' {
        $json=[IO.File]::ReadAllText($script:pluginFragmentPath)
        $json | Should -Not -Match '(?i)(?:[a-z]:[\\/]|\\\\(?:OMVNAS|[A-Z]{2,}NAS)\\)'
        (@($script:pluginFragment.Census | Where-Object ProfileId -CEQ 'SB3')[0]).Disposition | Should -BeExactly 'HeldProfileBindingUnresolved'
        (@($script:pluginFragment.Census | Where-Object ProfileId -CEQ 'RabbidsHollywood')[0]).Disposition | Should -BeExactly 'RecipeInFragment'
        (@($script:pluginFragment.Census | Where-Object ProfileId -CEQ 'RabbidsHollywood')[0]).TriggerCrosshairsAssembly.ExistingRecipeId | Should -BeExactly 'rabbids-hollywood-trigger-crosshairs-restore'
        (@($script:pluginFragment.Census | Where-Object ProfileId -CEQ 'RabbidsHollywood')[0]).Plugin.Sha256 | Should -BeExactly 'C3DEDA497E160652A1F0D3D99892A4F534A88D61358DBA5192003FF519D5E8EB'
    }


    It 'blocks both recipe-shaped restores when the BepInEx core prerequisite is missing' {
        Mock Read-HostSafe {
            if($script:pluginLaneHostQueue.Count -eq 0){throw 'Unexpected menu prompt.'}
            return $script:pluginLaneHostQueue.Dequeue()
        }
        Mock Read-PathWithBrowse {
            if($script:pluginLanePathQueue.Count -eq 0){throw 'Unexpected path prompt.'}
            return $script:pluginLanePathQueue.Dequeue()
        }
        Mock Invoke-TpmCatalogPatch { throw 'A missing-core recipe must not reach patch publication.' }
        foreach($seed in $script:pluginFragment.Entries){
            & $script:pluginLaneRequiredPatchFixtureSetup
            $fixture=$script:requiredPatchFixture
            $entry=$seed|ConvertTo-Json -Depth 20|ConvertFrom-Json
            $entry.Executable='synthetic.exe'
            $entry.ExecutableSha256=$fixture.ExecutableSha256
            $entry.SourceRole='UserSelected'
            $entry.SourceSet='synthetic-'+$entry.Id+'.zip'
            $entry.SourceSize=[int](Get-Item -LiteralPath $fixture.CreatedPayload).Length
            $entry.SourceSha1=(Get-FileHash -LiteralPath $fixture.CreatedPayload -Algorithm SHA1).Hash
            $entry.SourceSha256=$fixture.CreatedSha256
            $entry.Operations[0].Payload='plugin.dll'
            $entry.Operations[0].AfterSha256=$fixture.CreatedSha256
            $entry.Operations[0].PayloadSha256=$fixture.CreatedSha256
            $content=[pscustomobject]@{Schema=3;Entries=@($entry)}|ConvertTo-Json -Depth 20
            $manager=Join-Path $fixture.Root 'manager';$owned=Join-Path $manager 'owned'
            $temp=Join-Path $owned 'Temp';$backups=Join-Path $owned 'Backups'
            $source=Join-Path $fixture.Root 'source';$tp=Join-Path $fixture.Root 'tp'
            foreach($directory in @($manager,(Join-Path $manager 'scripts'),$owned,$temp,$backups,$source,$tp,(Join-Path $tp 'GameProfiles'),(Join-Path $tp 'UserProfiles'))){
                [void][IO.Directory]::CreateDirectory($directory)
            }
            New-PluginLaneSyntheticZip -Path (Join-Path $source $entry.SourceSet) -Member $entry.SourceEntry -Bytes ([IO.File]::ReadAllBytes($fixture.CreatedPayload))
            [IO.File]::WriteAllText((Join-Path $tp 'TeknoParrotUi.exe'),'synthetic UI; never launch')
            [IO.File]::WriteAllText((Join-Path (Join-Path $tp 'GameProfiles') ($entry.ProfileId+'.xml')),'<GameProfile />')
            $catalogPath=Join-Path (Join-Path $manager 'scripts') 'TpmRequiredPatchRecipes.json'
            [IO.File]::WriteAllText($catalogPath,$content,(New-Object Text.UTF8Encoding($false)))
            $script:TpmRequiredPatchCatalogSha256=(Get-FileHash -LiteralPath $catalogPath -Algorithm SHA256).Hash
            $script:TpmOwnedLayout=[pscustomobject]@{Root=$owned;Temp=$temp;Backups=$backups}
            $script:gamesInstallFolder=$fixture.GameRoot
            $script:pluginLaneHostQueue=New-Object 'System.Collections.Generic.Queue[string]'
            foreach($value in @('M','1','')){$script:pluginLaneHostQueue.Enqueue($value)}
            $script:pluginLanePathQueue=New-Object 'System.Collections.Generic.Queue[string]'
            foreach($value in @($fixture.GameRoot,$source)){$script:pluginLanePathQueue.Enqueue($value)}

            $prerequisites=Test-TpmRequiredPatchPrerequisites -Entry $entry -GameRoot $fixture.GameRoot
            $prerequisites.Satisfied | Should -BeFalse
            @($prerequisites.Missing|Where-Object Id -CEQ 'bepinex-core').Count | Should -Be 1
            $output=Invoke-TpmRequiredPatchMenu -TpRoot $tp -UserProfilesDir (Join-Path $tp 'UserProfiles') -ManagerRoot $manager -ProgramRoot $manager 6>&1
            ($output|Out-String) | Should -Match 'No patch was applied'
            Test-Path -LiteralPath (Join-Path $fixture.GameRoot ($entry.Operations[0].Target.Replace('/','\'))) | Should -BeFalse
            $script:pluginLaneHostQueue.Count | Should -Be 0
            $script:pluginLanePathQueue.Count | Should -Be 0
            @(Get-ChildItem -LiteralPath $temp -Directory -ErrorAction Stop).Count | Should -Be 0
            $script:TpmOwnedLayout=$null
            $script:TpmRequiredPatchCatalogSha256='87DF31451B267F89FCD2CB3E3DEA1860972EDD4C7601ACE1998E80BD7E4CAD9E'
        }
        Assert-MockCalled Invoke-TpmCatalogPatch -Times 0 -Exactly
    }

    It 'applies, skips exact repeats, refuses unknown target bytes, and receipt-undos both recipe-shaped restores' {
        foreach($seed in $script:pluginFragment.Entries){
            & $script:pluginLaneRequiredPatchFixtureSetup
            $fixture=$script:requiredPatchFixture
            $entry=$seed|ConvertTo-Json -Depth 20|ConvertFrom-Json
            $entry.Executable='synthetic.exe'
            $entry.ExecutableSha256=$fixture.ExecutableSha256
            $entry.SourceRole='UserSelected'
            $entry.SourceSet='synthetic-'+$entry.Id+'.zip'
            $entry.SourceSize=[int](Get-Item -LiteralPath $fixture.CreatedPayload).Length
            $entry.SourceSha1=(Get-FileHash -LiteralPath $fixture.CreatedPayload -Algorithm SHA1).Hash
            $entry.SourceSha256=$fixture.CreatedSha256
            $entry.Operations[0].Payload='plugin.dll'
            $entry.Operations[0].AfterSha256=$fixture.CreatedSha256
            $entry.Operations[0].PayloadSha256=$fixture.CreatedSha256
            $content=[pscustomobject]@{Schema=3;Entries=@($entry)}|ConvertTo-Json -Depth 20
            $catalogHash=Get-TpmPatchTextSha256 $content
            $core=Join-Path $fixture.GameRoot 'BepInEx\core\BepInEx.dll'
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($core))
            $missingCore=Test-TpmRequiredPatchPrerequisites -Entry $entry -GameRoot $fixture.GameRoot
            $missingCore.Satisfied | Should -BeFalse
            $target=Join-Path $fixture.GameRoot ($entry.Operations[0].Target.Replace('/','\'))
            Test-Path -LiteralPath $target | Should -BeFalse
            [IO.File]::WriteAllText($core,'synthetic BepInEx core; never load')
            (Test-TpmRequiredPatchPrerequisites -Entry $entry -GameRoot $fixture.GameRoot).Satisfied | Should -BeTrue
            $inputs=@{
                CatalogContent=$content;CatalogSha256=$catalogHash;PatchId=$entry.Id;ProfileId=$entry.ProfileId
                GameRoot=$fixture.GameRoot;PayloadRoot=$fixture.PayloadRoot;RecoveryRoot=$fixture.RecoveryRoot
                ProtectedRoots=@($fixture.ProtectedRoot)
            }
            $plan=Get-TpmPatchPlan @inputs
            $plan.Status | Should -Be 'Ready' -Because ([string]$plan.Reason)
            $applied=Invoke-TpmCatalogPatch @inputs -Confirm:$false
            $applied.Status | Should -Be 'Applied'
            (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash | Should -Be $fixture.CreatedSha256
            (Get-TpmPatchPlan @inputs).Status | Should -Be 'AlreadyApplied'
            (Invoke-TpmCatalogPatch @inputs -Confirm:$false).Status | Should -Be 'AlreadyApplied'
            (Undo-TpmCatalogPatch @inputs -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false).Status | Should -Be 'Restored'
            Test-Path -LiteralPath $target | Should -BeFalse
            [IO.File]::WriteAllText($target,'unknown third-party file; never execute')
            $conflict=Get-TpmPatchPlan @inputs
            $conflict.Status | Should -Be 'Unavailable'
            $conflict.Reason | Should -Be 'Grouped target conflict.'
            [IO.File]::ReadAllText($target) | Should -Be 'unknown third-party file; never execute'
            $script:TpmOwnedLayout=$null
            $script:TpmRequiredPatchCatalogSha256='87DF31451B267F89FCD2CB3E3DEA1860972EDD4C7601ACE1998E80BD7E4CAD9E'
        }
    }
    It 'stages only the exact hash-pinned member from a synthetic ordinary ZIP' {
        $root=Join-Path $TestDrive 'plugin-lane-success'
        $source=Join-Path $root 'source'
        $temp=Join-Path $root 'owned-temp'
        [void][IO.Directory]::CreateDirectory($source)
        [void][IO.Directory]::CreateDirectory($temp)
        $zipPath=Join-Path $source 'synthetic-plugin.zip'
        $bytes=[Text.Encoding]::UTF8.GetBytes('synthetic plugin payload; never executed')
        $hash=(Get-TpmPatchTextSha256 ([Text.Encoding]::UTF8.GetString($bytes)))
        New-PluginLaneSyntheticZip -Path $zipPath -Member 'exact/plugin.dll' -Bytes $bytes
        $script:TpmOwnedLayout=[pscustomobject]@{Root=$root;Temp=$temp}
        $entry=[pscustomobject]@{
            SourceSet='synthetic-plugin.zip';SourceEntry='exact/plugin.dll';SourceSize=$bytes.Length
            SourceSha1=('0'*40);SourceSha256=$hash
            Operations=@([pscustomobject]@{Payload='payload/plugin.dll';PayloadSha256=$hash;AfterSha256=$hash})
        }

        $stage=New-TpmRequiredPatchPayloadStage -Entry $entry -SourceRoot $source
        try {
            $payloadStream=[IO.File]::OpenRead($stage.Payload)
            try { (Get-TpmPatchStreamSha256 -Stream $payloadStream).ToUpperInvariant() | Should -BeExactly $hash.ToUpperInvariant() } finally { $payloadStream.Dispose() }
            $stage.SourceEntry | Should -BeExactly 'exact/plugin.dll'
        } finally {
            if ($stage -and (Test-Path -LiteralPath $stage.Root)) { Remove-Item -LiteralPath $stage.Root -Recurse -Force -ErrorAction Stop }
            $script:TpmOwnedLayout=$null
        }
    }

    It 'rejects a synthetic source member whose bytes do not match the recipe hash and removes staging residue' {
        $root=Join-Path $TestDrive 'plugin-lane-mismatch'
        $source=Join-Path $root 'source'
        $temp=Join-Path $root 'owned-temp'
        [void][IO.Directory]::CreateDirectory($source)
        [void][IO.Directory]::CreateDirectory($temp)
        $zipPath=Join-Path $source 'synthetic-plugin.zip'
        $bytes=[Text.Encoding]::UTF8.GetBytes('wrong synthetic payload')
        New-PluginLaneSyntheticZip -Path $zipPath -Member 'exact/plugin.dll' -Bytes $bytes
        $script:TpmOwnedLayout=[pscustomobject]@{Root=$root;Temp=$temp}
        $entry=[pscustomobject]@{
            SourceSet='synthetic-plugin.zip';SourceEntry='exact/plugin.dll';SourceSize=$bytes.Length
            SourceSha1=('0'*40);SourceSha256=('F'*64)
            Operations=@([pscustomobject]@{Payload='payload/plugin.dll';PayloadSha256=('F'*64);AfterSha256=('F'*64)})
        }

        try {
            { New-TpmRequiredPatchPayloadStage -Entry $entry -SourceRoot $source } | Should -Throw '*does not match the payload and target SHA-256 pins*'
            @(Get-ChildItem -LiteralPath $temp -Directory -ErrorAction Stop).Count | Should -Be 0
        } finally { $script:TpmOwnedLayout=$null }
    }
}
