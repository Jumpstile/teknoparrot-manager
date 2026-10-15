param(
    [string]$RepositoryRoot=([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))),
    [string]$FragmentPath=(Join-Path $RepositoryRoot 'tools\required-patches\fragments\native-crossraid-base-shader-20261015.json')
)
BeforeAll {
    . (Join-Path $RepositoryRoot 'scripts\TpmRequiredPatchEngine.ps1')

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


    function Save-CrossRaidProofState {
        $saved=@{}
        foreach($name in @('TpmRequiredPatchCatalogSha256','TpmOwnedLayout','gamesInstallFolder','requiredPatchInputQueue','requiredPatchFixture')){
            $old=Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue
            $saved[$name]=[pscustomobject]@{Exists=($null -ne $old);Value=$(if($null -ne $old){$old.Value}else{$null})}
        }
        return $saved
    }
    function Restore-CrossRaidProofState {
        param($Saved)
        foreach($name in $Saved.Keys){
            if($Saved[$name].Exists){Set-Variable -Name $name -Scope Script -Value $Saved[$name].Value}
            else{Remove-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue}
        }
    }

    $script:crossraidDeltaPath=$FragmentPath
    $script:crossraidDelta=[IO.File]::ReadAllText($script:crossraidDeltaPath,[Text.Encoding]::UTF8)|ConvertFrom-Json -ErrorAction Stop
    $script:crossRaidVendorCatalogPath=Join-Path $RepositoryRoot 'scripts\TpmRequiredPatchRecipes.json'
    $script:crossRaidVendorCatalog=[IO.File]::ReadAllText($script:crossRaidVendorCatalogPath,[Text.Encoding]::UTF8)|ConvertFrom-Json -ErrorAction Stop
    $mainPath=Join-Path $RepositoryRoot 'TeknoParrot-Manager.ps1'
    $tokens=$null;$errors=$null
    $mainAst=[System.Management.Automation.Language.Parser]::ParseFile($mainPath,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw 'Unable to parse manager helper source for isolated Cross Raid transaction proof.'}
    foreach($name in @('Get-TpmSupportNativeType','Get-TpmSupportFinalPathFromHandle','Remove-TpmSupportHandle','Test-TpmPathOverlap','Get-TpmFileState','Read-HostSafe','Read-PathWithBrowse','Get-DetectedGpuVendor','New-ManagerUpdateBackup')){
        $functionAst=$mainAst.Find({param($node)$node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$true)
        if(-not $functionAst){throw ('Missing required Cross Raid proof helper: '+$name)}
        . ([scriptblock]::Create($functionAst.Extent.Text))
    }
    [void](Get-TpmSupportNativeType)
    $suitePath=Join-Path $RepositoryRoot 'Tests\TeknoParrot-Manager.Tests.ps1'
    $suiteTokens=$null;$suiteErrors=$null
    $suiteAst=[System.Management.Automation.Language.Parser]::ParseFile($suitePath,[ref]$suiteTokens,[ref]$suiteErrors)
    if($suiteErrors.Count){throw 'Unable to parse the existing required-patch fixture source.'}
    $describe=$suiteAst.Find({param($node)$node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Describe' -and $node.CommandElements.Count -ge 3 -and $node.CommandElements[1].Value -ceq 'Required patch engine and local recipes'},$true)
    if(-not $describe){throw 'The existing required-patch fixture container was not found.'}
    $beforeEach=$describe.CommandElements[2].ScriptBlock.Find({param($node)$node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'BeforeEach'},$true)
    if(-not $beforeEach){throw 'The existing required-patch fixture setup was not found.'}
    $script:crossraidFixtureSetup=$beforeEach.CommandElements[-1].ScriptBlock.GetScriptBlock()

    function New-CrossRaidProofContext {
        param([ValidateSet('AMD','NVIDIA')][string]$Vendor='AMD')
        & $script:crossraidFixtureSetup
        $f=$script:requiredPatchFixture
        $base=$script:crossraidDelta.Entries[0]|ConvertTo-Json -Depth 20|ConvertFrom-Json
        $baseBytes=[IO.File]::ReadAllBytes($f.CreatedPayload)
        $base.Executable='synthetic.exe';$base.ExecutableSha256=$f.ExecutableSha256
        $base.SourceRole='UserSelected';$base.SourceSet='synthetic-crossraid-base.zip'
        $base.SourceSize=[long]$baseBytes.LongLength
        $base.SourceSha1=(Get-FileHash -LiteralPath $f.CreatedPayload -Algorithm SHA1).Hash
        $base.SourceSha256=$f.CreatedSha256
        $base.Operations[0].AfterSha256=$f.CreatedSha256;$base.Operations[0].PayloadSha256=$f.CreatedSha256
        $recipes=@($base);$vendors=@{}
        foreach($name in @('AMD','NVIDIA')){
            $id='shining-force-cross-raid-105-'+$name.ToLowerInvariant()+'-shader'
            $matches=@($script:crossRaidVendorCatalog.Entries|Where-Object Id -CEQ $id)
            if($matches.Count -ne 1){throw 'Expected exact vendor recipe is missing.'}
            $entry=$matches[0]|ConvertTo-Json -Depth 20|ConvertFrom-Json
            $bytes=[Text.Encoding]::UTF8.GetBytes('Synthetic '+$name+' shader; never execute.')
            $probe=Join-Path $f.Root ('synthetic-'+$name+'.bin')
            [IO.File]::WriteAllBytes($probe,$bytes)
            $sha=(Get-FileHash -LiteralPath $probe -Algorithm SHA256).Hash
            $entry.Executable='synthetic.exe';$entry.ExecutableSha256=$f.ExecutableSha256
            $entry.SourceRole='UserSelected';$entry.SourceSet='synthetic-'+$name+'.zip'
            $entry.SourceSize=[long]$bytes.LongLength
            $entry.SourceSha1=(Get-FileHash -LiteralPath $probe -Algorithm SHA1).Hash
            $entry.SourceSha256=$sha
            $entry.Operations[0].BeforeSha256=$f.CreatedSha256
            $entry.Operations[0].AfterSha256=$sha;$entry.Operations[0].PayloadSha256=$sha
            $entry.Operations[0].Payload='payload/'+$name+'/shader.farc'
            $payload=Join-Path $f.PayloadRoot $entry.Operations[0].Payload.Replace('/','\')
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($payload))
            [IO.File]::WriteAllBytes($payload,$bytes)
            $vendors[$name]=[pscustomobject]@{Entry=$entry;Bytes=$bytes;Sha256=$sha}
            $recipes+=@($entry)
        }
        $basePayload=Join-Path $f.PayloadRoot $base.Operations[0].Payload.Replace('/','\')
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($basePayload))
        [IO.File]::WriteAllBytes($basePayload,$baseBytes)
        $target=Join-Path $f.GameRoot $base.Operations[0].Target.Replace('/','\')
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
        $content=[pscustomobject]@{Schema=3;Entries=$recipes}|ConvertTo-Json -Depth 20
        $adapter=if($Vendor -eq 'AMD'){'AMD Radeon fixture'}else{'NVIDIA GeForce fixture'}
        $hardware=[pscustomobject]@{Adapters=@([pscustomobject]@{Name=$adapter});MultiGpuAmbiguous=$false;ActiveGpuConfidence='INFERRED';ActiveAdapterIndex=0;ActiveAdapterName=$adapter}
        $common=@{CatalogContent=$content;CatalogSha256=(Get-TpmPatchTextSha256 $content);ProfileId=$base.ProfileId;GameRoot=$f.GameRoot;PayloadRoot=$f.PayloadRoot;RecoveryRoot=$f.RecoveryRoot;ProtectedRoots=@($f.ProtectedRoot);HardwareEvidence=$hardware}
        $baseInputs=@{}+$common;$baseInputs.PatchId=$base.Id
        $vendorInputs=@{}+$common;$vendorInputs.PatchId=$vendors[$Vendor].Entry.Id
        return [pscustomobject]@{Fixture=$f;BaseEntry=$base;BaseBytes=$baseBytes;BaseSha256=$f.CreatedSha256;BaseInputs=$baseInputs;Vendors=$vendors;VendorInputs=$vendorInputs;SelectedVendor=$vendors[$Vendor];Target=$target}
    }
}

Describe 'Cross Raid Main-component repair' {
    It 'keeps exact Main identity pins and an absent-only operation' {
        $entries=@($script:crossraidDelta.Entries)
        $entries.Count | Should -Be 1
        $entry=$entries[0]
        $entry.Id | Should -BeExactly 'shining-force-cross-raid-105-base-shader-restoration'
        $entry.ProfileId | Should -BeExactly 'ShiningForceCrossRaid'
        $entry.BuildName | Should -BeExactly 'Shining Force - Cross Raid (1.05 Ver A)(2011-08-03)(JPN)[Sega RingEdge][TP]'
        $entry.Executable | Should -BeExactly 'project_f-ringedge-release.exe'
        $entry.ExecutableSha256 | Should -BeExactly '82E66635A9A91CEC59721DB7BD9258464F70C44377BA707FFCB51EA2D3DB9317'
        $entry.SourceRole | Should -BeExactly 'Main'
        $entry.SourceSet | Should -BeExactly 'Shining Force - Cross Raid (1.05 Ver A)(2011-08-03)(JPN)[Sega RingEdge][TP].zip'
        $entry.SourceEntry | Should -BeExactly 'rom/shader.farc'
        $entry.SourceSize | Should -Be 9173328
        $entry.SourceSha1 | Should -BeExactly '04E0DCEC14CCA1B69BF190A7E02F2F0AB56E0231'
        $entry.SourceSha1.Length | Should -Be 40
        $entry.SourceSha1 | Should -Match '^[A-F0-9]{40}$'
        $entry.SourceSha256 | Should -BeExactly '66E0CC00E84C01F6E77E6B446A019212EBD27610FDD81CA866648C5E97E80933'
        $entry.ExclusiveGroup | Should -BeExactly ''
        @($entry.PSObject.Properties.Name | Where-Object {$_ -ceq 'HardwarePredicate'}).Count | Should -Be 0
        @($entry.Operations).Count | Should -Be 1
        $entry.Operations[0].Type | Should -BeExactly 'CreateFile'
        $entry.Operations[0].Target | Should -BeExactly 'rom/shader.farc'
        $entry.Operations[0].BeforeState | Should -BeExactly 'Absent'
        $entry.Operations[0].AfterSha256 | Should -BeExactly $entry.SourceSha256
        $entry.Operations[0].PayloadSha256 | Should -BeExactly $entry.SourceSha256
        $vendorPins=@(
            [pscustomobject]@{Id='shining-force-cross-raid-105-amd-shader';SourceSet='Shining Force - Cross Raid (1.05) - AMD Shader Fix.zip';Vendor='AMD';SourceSha1='7520194AB599DB8FF68C0D7277DA9DEE0EEC57C8';SourceSha256='B245426428543B89A7A074EDEFD7E72CC437EBED9462F287E646FD8CD4A5A8BB'}
            [pscustomobject]@{Id='shining-force-cross-raid-105-nvidia-shader';SourceSet='Shining Force - Cross Raid (1.05) - NVIDIA Shader Fix.zip';Vendor='NVIDIA';SourceSha1='FF7DE8DB19ABE7695BCE5617894E41667CBF05E7';SourceSha256='DA517CD064CB8B17C8B62DF1783F4D641195B0EB1E90FDD07B8BA72E47511912'}
        )
        foreach($expected in $vendorPins){
            $matches=@($script:crossRaidVendorCatalog.Entries|Where-Object {$_.Id -ceq $expected.Id})
            $matches.Count | Should -Be 1
            $recipe=$matches[0]
            $recipe.ProfileId | Should -BeExactly 'ShiningForceCrossRaid'
            $recipe.BuildName | Should -BeExactly $entry.BuildName
            $recipe.ExecutableSha256 | Should -BeExactly $entry.ExecutableSha256
            $recipe.SourceRole | Should -BeExactly 'Supplementary'
            $recipe.SourceSet | Should -BeExactly $expected.SourceSet
            $recipe.SourceEntry | Should -BeExactly 'rom/shader.farc'
            $recipe.SourceSize | Should -Be 8987472
            $recipe.SourceSha1 | Should -BeExactly $expected.SourceSha1
            $recipe.SourceSha1.Length | Should -Be 40
            $recipe.SourceSha256 | Should -BeExactly $expected.SourceSha256
            $recipe.HardwarePredicate.Vendor | Should -BeExactly $expected.Vendor
            $recipe.ExclusiveGroup | Should -BeExactly 'shining-force-cross-raid-105-shader'
            @($recipe.Operations).Count | Should -Be 1
            $recipe.Operations[0].Type | Should -BeExactly 'ReplaceFile'
            $recipe.Operations[0].Target | Should -BeExactly 'rom/shader.farc'
            $recipe.Operations[0].BeforeSha256 | Should -BeExactly $entry.SourceSha256
            $recipe.Operations[0].AfterSha256 | Should -BeExactly $expected.SourceSha256
            $recipe.Operations[0].PayloadSha256 | Should -BeExactly $expected.SourceSha256
        }
    }

    It 'creates absent bytes, reads them back, skips repeat, undoes to absent, and refuses foreign bytes' {
        $saved=Save-CrossRaidProofState
        try {
            & $script:crossraidFixtureSetup
            $fixture=$script:requiredPatchFixture
            $entry=$script:crossraidDelta.Entries[0]|ConvertTo-Json -Depth 20|ConvertFrom-Json
            $entry.Executable='synthetic.exe';$entry.ExecutableSha256=$fixture.ExecutableSha256
            $entry.SourceRole='UserSelected';$entry.SourceSet='synthetic-crossraid-base.zip'
            $entry.SourceSize=[int](Get-Item -LiteralPath $fixture.CreatedPayload).Length
            $entry.SourceSha1=(Get-FileHash -LiteralPath $fixture.CreatedPayload -Algorithm SHA1).Hash
            $entry.SourceSha256=$fixture.CreatedSha256
            $entry.Operations[0].AfterSha256=$fixture.CreatedSha256
            $entry.Operations[0].PayloadSha256=$fixture.CreatedSha256
            $content=[pscustomobject]@{Schema=3;Entries=@($entry)}|ConvertTo-Json -Depth 20
            $catalogHash=Get-TpmPatchTextSha256 $content
            $payload=Join-Path $fixture.PayloadRoot $entry.Operations[0].Payload.Replace('/','\')
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($payload))
            [IO.File]::WriteAllBytes($payload,[IO.File]::ReadAllBytes($fixture.CreatedPayload))
            $target=Join-Path $fixture.GameRoot $entry.Operations[0].Target.Replace('/','\')
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
            $inputs=@{CatalogContent=$content;CatalogSha256=$catalogHash;PatchId=$entry.Id;ProfileId=$entry.ProfileId;GameRoot=$fixture.GameRoot;PayloadRoot=$fixture.PayloadRoot;RecoveryRoot=$fixture.RecoveryRoot;ProtectedRoots=@($fixture.ProtectedRoot)}
            (Test-Path -LiteralPath $target) | Should -BeFalse
            (Get-TpmPatchPlan @inputs).Status | Should -Be 'Ready'
            $applied=Invoke-TpmCatalogPatch @inputs -Confirm:$false
            $applied.Status | Should -Be 'Applied'
            (Get-Item -LiteralPath $target).Length | Should -Be (Get-Item -LiteralPath $fixture.CreatedPayload).Length
            (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash | Should -BeExactly $fixture.CreatedSha256
            (Invoke-TpmCatalogPatch @inputs -Confirm:$false).Status | Should -Be 'AlreadyApplied'
            (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash | Should -BeExactly $fixture.CreatedSha256
            (Undo-TpmCatalogPatch @inputs -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false).Status | Should -Be 'Restored'
            Test-Path -LiteralPath $target | Should -BeFalse
            [IO.File]::WriteAllText($target,'foreign shader bytes; never execute')
            $foreign=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
            (Get-TpmPatchPlan @inputs).Status | Should -Be 'Unavailable'
            {Invoke-TpmCatalogPatch @inputs -Confirm:$false}|Should -Throw
            (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash | Should -BeExactly $foreign
        } finally {Restore-CrossRaidProofState $saved}
    }

    It 'refuses a wrong executable before changing the target or recovery state' {
        $saved=Save-CrossRaidProofState
        try {
            & $script:crossraidFixtureSetup
            $fixture=$script:requiredPatchFixture
            $entry=$script:crossraidDelta.Entries[0]|ConvertTo-Json -Depth 20|ConvertFrom-Json
            $entry.Executable='synthetic.exe';$entry.ExecutableSha256=('0'*64)
            $entry.SourceRole='UserSelected';$entry.SourceSet='synthetic-crossraid-wrong-exe.zip'
            $entry.SourceSize=[int](Get-Item -LiteralPath $fixture.CreatedPayload).Length
            $entry.SourceSha1=(Get-FileHash -LiteralPath $fixture.CreatedPayload -Algorithm SHA1).Hash
            $entry.SourceSha256=$fixture.CreatedSha256
            $entry.Operations[0].AfterSha256=$fixture.CreatedSha256
            $entry.Operations[0].PayloadSha256=$fixture.CreatedSha256
            $content=[pscustomobject]@{Schema=3;Entries=@($entry)}|ConvertTo-Json -Depth 20
            $catalogHash=Get-TpmPatchTextSha256 $content
            $payload=Join-Path $fixture.PayloadRoot $entry.Operations[0].Payload.Replace('/','\')
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($payload))
            [IO.File]::WriteAllBytes($payload,[IO.File]::ReadAllBytes($fixture.CreatedPayload))
            $target=Join-Path $fixture.GameRoot $entry.Operations[0].Target.Replace('/','\')
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
            $inputs=@{CatalogContent=$content;CatalogSha256=$catalogHash;PatchId=$entry.Id;ProfileId=$entry.ProfileId;GameRoot=$fixture.GameRoot;PayloadRoot=$fixture.PayloadRoot;RecoveryRoot=$fixture.RecoveryRoot;ProtectedRoots=@($fixture.ProtectedRoot)}
            $wrongPlan=Get-TpmPatchPlan @inputs
            $wrongPlan.Status | Should -Be 'Unavailable'
            $wrongPlan.Reason | Should -BeExactly 'Executable revision mismatch.'
            {Invoke-TpmCatalogPatch @inputs -Confirm:$false}|Should -Throw
            Test-Path -LiteralPath $target | Should -BeFalse
            @(Get-ChildItem -LiteralPath $fixture.RecoveryRoot -Force).Count | Should -Be 0
        } finally {Restore-CrossRaidProofState $saved}
    }

    It 'refuses AMD and NVIDIA after-states without overwrite' {
        $saved=Save-CrossRaidProofState
        try {
            $c=New-CrossRaidProofContext
            $baseInputs=$c.BaseInputs
            foreach($name in @('AMD','NVIDIA')){
                [IO.File]::WriteAllBytes($c.Target,$c.Vendors[$name].Bytes)
                (Get-FileHash -LiteralPath $c.Target -Algorithm SHA256).Hash | Should -BeExactly $c.Vendors[$name].Sha256
                (Get-TpmPatchPlan @baseInputs).Status | Should -Be 'Unavailable'
                {Invoke-TpmCatalogPatch @baseInputs -Confirm:$false}|Should -Throw
                (Get-FileHash -LiteralPath $c.Target -Algorithm SHA256).Hash | Should -BeExactly $c.Vendors[$name].Sha256
            }
        } finally {Restore-CrossRaidProofState $saved}
    }

    It 'stages synthetic pinned Main-shaped bytes within the owned temporary root' {
        $saved=Save-CrossRaidProofState
        try {
            $c=New-CrossRaidProofContext
            $sourceRoot=Join-Path $c.Fixture.Root 'source'
            [void][IO.Directory]::CreateDirectory($sourceRoot)
            $zipPath=Join-Path $sourceRoot $c.BaseEntry.SourceSet
            Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
            $zip=[IO.Compression.ZipFile]::Open($zipPath,[IO.Compression.ZipArchiveMode]::Create)
            try{
                $member=$zip.CreateEntry('rom/shader.farc')
                $stream=$member.Open()
                try{$stream.Write($c.BaseBytes,0,$c.BaseBytes.Length)}finally{$stream.Dispose()}
            }finally{$zip.Dispose()}
            $owned=Join-Path $c.Fixture.Root 'owned-stage'
            $temp=Join-Path $owned 'temp'
            [void][IO.Directory]::CreateDirectory($temp)
            $script:TpmOwnedLayout=[pscustomobject]@{Root=$owned;Temp=$temp}
            $stage=New-TpmRequiredPatchPayloadStage -Entry $c.BaseEntry -SourceRoot $sourceRoot
            $stage.SourceEntry | Should -BeExactly 'rom/shader.farc'
            $stage.Size | Should -Be $c.BaseBytes.LongLength
            $stage.Sha256 | Should -BeExactly $c.BaseSha256
            (Get-FileHash -LiteralPath $stage.Payload -Algorithm SHA1).Hash | Should -BeExactly $c.BaseEntry.SourceSha1
            (Get-FileHash -LiteralPath $stage.Payload -Algorithm SHA256).Hash | Should -BeExactly $c.BaseSha256
            (Test-PathInside $stage.Payload $temp) | Should -BeTrue
        } finally {Restore-CrossRaidProofState $saved}
    }

    It 'allows valid <Vendor> undo after base creation without weakening ownership' -ForEach @(@{Vendor='AMD'},@{Vendor='NVIDIA'}) {
        param($Vendor)
        $saved=Save-CrossRaidProofState
        try {
            $c=New-CrossRaidProofContext -Vendor $Vendor
            $baseInputs=$c.BaseInputs;$vendorInputs=$c.VendorInputs
            $base=Invoke-TpmCatalogPatch @baseInputs -Confirm:$false
            $base.Status | Should -Be 'Applied'
            $receipt=[IO.File]::ReadAllText((Join-Path $base.RecoveryDirectory 'receipt.json'))|ConvertFrom-Json
            $createdIdentity=$receipt.Operations[0].AfterFileIdentity
            $createdIdentity | Should -Match '^[A-F0-9]{8}:[A-F0-9]{16}$'
            $vendorApply=Invoke-TpmCatalogPatch @vendorInputs -Confirm:$false
            $vendorApply.Status | Should -Be 'Applied'
            {Undo-TpmCatalogPatch @baseInputs -RecoveryDirectory $base.RecoveryDirectory -Confirm:$false} | Should -Throw
            (Get-FileHash -LiteralPath $c.Target -Algorithm SHA256).Hash | Should -BeExactly $c.SelectedVendor.Sha256
            $undo=Undo-TpmCatalogPatch @vendorInputs -RecoveryDirectory $vendorApply.RecoveryDirectory -Confirm:$false
            $undo.Status | Should -Be 'Restored'
            (Get-FileHash -LiteralPath $c.Target -Algorithm SHA256).Hash | Should -BeExactly $c.BaseSha256
            $opened=Open-TpmPatchCreationFile $c.Target
            try{$currentIdentity=[TpmSupportNativeMethods]::PatchFileIdentity($opened.SafeFileHandle)}finally{$opened.Dispose()}
            $vendorReceiptAfter=[IO.File]::ReadAllText((Join-Path $vendorApply.RecoveryDirectory 'receipt.json'))|ConvertFrom-Json
            $vendorReceiptAfter.State | Should -BeExactly 'Restored'
            $restoredIdentity=[string]$vendorReceiptAfter.Operations[0].RestoredFileIdentity
            $restoredIdentity | Should -Match '^[A-F0-9]{8}:[A-F0-9]{16}$'
            $currentIdentity | Should -BeExactly $restoredIdentity
            $currentIdentity | Should -Not -BeExactly $createdIdentity
            $baseReceiptAfter=[IO.File]::ReadAllText((Join-Path $base.RecoveryDirectory 'receipt.json'))|ConvertFrom-Json
            $baseReceiptAfter.Operations[0].AfterFileIdentity | Should -BeExactly $createdIdentity
            $baseUndoFailure=$null
            try{[void](Undo-TpmCatalogPatch @baseInputs -RecoveryDirectory $base.RecoveryDirectory -Confirm:$false)}catch{$baseUndoFailure=$_}
            $baseUndoFailure | Should -Not -BeNullOrEmpty
            $baseUndoFailure.Exception.Message | Should -BeExactly 'Grouped target object identity changed.'
            (Get-FileHash -LiteralPath $c.Target -Algorithm SHA256).Hash | Should -BeExactly $c.BaseSha256
        } finally {Restore-CrossRaidProofState $saved}
    }
}
