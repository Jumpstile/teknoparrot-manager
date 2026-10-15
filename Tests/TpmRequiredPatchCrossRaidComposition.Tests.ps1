BeforeAll {
    . (Join-Path $PSScriptRoot '..\scripts\TpmRequiredPatchEngine.ps1')
    $managerPath=Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1';$tokens=$null;$errors=$null
    $mainAst=[System.Management.Automation.Language.Parser]::ParseFile($managerPath,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw "Manager parse failed: $($errors -join '; ')"}
    $extracted=Join-Path $TestDrive ('composition-functions-'+[guid]::NewGuid().ToString('N')+'.ps1')
    $functionText=($mainAst.FindAll({$args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst]},$true)|ForEach-Object {$_.Extent.Text}) -join "`r`n"
    [IO.File]::WriteAllText($extracted,$functionText,(New-Object System.Text.UTF8Encoding($false)))
    . $extracted
    [void](Get-TpmSupportNativeType)
    function New-CompositionContext([string]$Vendor){
        $root=Join-Path $TestDrive ('cx'+[guid]::NewGuid().ToString('N').Substring(0,8));$game=Join-Path $root 'game';$payload=Join-Path $root 'payload';$recovery=Join-Path $root 'recovery';$protected=Join-Path $root 'protected'
        foreach($dir in @($game,$payload,$recovery,$protected)){[void][IO.Directory]::CreateDirectory($dir)}
        $exe=Join-Path $game 'synthetic.exe';[IO.File]::WriteAllText($exe,'synthetic executable');$exeHash=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
        $bp=Join-Path $payload 'base.bin';$vp=Join-Path $payload 'vendor.bin';$ap=Join-Path $payload 'alternate.bin';$op=Join-Path $payload 'other.bin'
        $alternateVendor=if($Vendor -eq 'AMD'){'NVIDIA'}else{'AMD'}
        [IO.File]::WriteAllText($bp,'base bytes');[IO.File]::WriteAllText($vp,($Vendor+' bytes'));[IO.File]::WriteAllText($ap,($alternateVendor+' bytes'));[IO.File]::WriteAllText($op,'independent bytes')
        $alternateTarget=Join-Path $game 'rom\alternate-shader.farc';[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($alternateTarget));[IO.File]::WriteAllText($alternateTarget,'alternate before bytes')
        $alternateBeforeHash=(Get-FileHash -LiteralPath $alternateTarget -Algorithm SHA256).Hash
$bh=(Get-FileHash -LiteralPath $bp -Algorithm SHA256).Hash;$vh=(Get-FileHash -LiteralPath $vp -Algorithm SHA256).Hash;$ah=(Get-FileHash -LiteralPath $ap -Algorithm SHA256).Hash;$oh=(Get-FileHash -LiteralPath $op -Algorithm SHA256).Hash
        $base=[pscustomobject]@{Id='fixture.base';ProfileId='Fixture';Executable='synthetic.exe';ExecutableSha256=$exeHash;SourceUrl='https://example.invalid/base';SourceRevision=('A'*40);ExclusiveGroup='';Operations=@([pscustomobject]@{Type='CreateFile';Target='rom/shader.farc';BeforeState='Absent';AfterSha256=$bh;Payload='base.bin';PayloadSha256=$bh})}
        $vendorEntry=[pscustomobject]@{Id=('fixture.'+$Vendor);ProfileId='Fixture';Executable='synthetic.exe';ExecutableSha256=$exeHash;SourceUrl='https://example.invalid/vendor';SourceRevision=('B'*40);ExclusiveGroup='fixture.gpu';HardwarePredicate=[pscustomobject]@{Vendor=$Vendor};Operations=@([pscustomobject]@{Type='ReplaceFile';Target='rom/shader.farc';BeforeSha256=$bh;AfterSha256=$vh;Payload='vendor.bin';PayloadSha256=$vh})}
        $alternateEntry=[pscustomobject]@{Id=('fixture.'+$alternateVendor);ProfileId='Fixture';Executable='synthetic.exe';ExecutableSha256=$exeHash;SourceUrl='https://example.invalid/alternate';SourceRevision=('D'*40);ExclusiveGroup='fixture.gpu';HardwarePredicate=[pscustomobject]@{Vendor=$alternateVendor};Operations=@([pscustomobject]@{Type='ReplaceFile';Target='rom/alternate-shader.farc';BeforeSha256=$alternateBeforeHash;AfterSha256=$ah;Payload='alternate.bin';PayloadSha256=$ah})}
        $other=[pscustomobject]@{Id='fixture.other';ProfileId='Fixture';Executable='synthetic.exe';ExecutableSha256=$exeHash;SourceUrl='https://example.invalid/other';SourceRevision=('C'*40);ExclusiveGroup='';Operations=@([pscustomobject]@{Type='CreateFile';Target='data/independent.bin';BeforeState='Absent';AfterSha256=$oh;Payload='other.bin';PayloadSha256=$oh})}
        $content=[pscustomobject]@{Schema=3;Entries=@($base,$vendorEntry,$alternateEntry,$other)}|ConvertTo-Json -Depth 10
        $adapter=if($Vendor -eq 'AMD'){'AMD Radeon fixture'}else{'NVIDIA GeForce fixture'}
        $hw=[pscustomobject]@{Adapters=@([pscustomobject]@{Name=$adapter});MultiGpuAmbiguous=$false;ActiveGpuConfidence='INFERRED';ActiveAdapterIndex=0;ActiveAdapterName=$adapter}
        $common=@{CatalogContent=$content;CatalogSha256=(Get-TpmPatchTextSha256 $content);ProfileId='Fixture';GameRoot=$game;PayloadRoot=$payload;RecoveryRoot=$recovery;ProtectedRoots=@($protected);HardwareEvidence=$hw}
        $bi=@{}+$common;$bi.PatchId=$base.Id;$vi=@{}+$common;$vi.PatchId=$vendorEntry.Id
        $ai=@{}+$common;$ai.PatchId=$alternateEntry.Id;$oi=@{}+$common;$oi.PatchId=$other.Id
        $target=Join-Path $game 'rom\shader.farc';$otherTarget=Join-Path $game 'data\independent.bin'
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target));[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($otherTarget))
        return [pscustomobject]@{BaseInputs=$bi;VendorInputs=$vi;AlternateInputs=$ai;OtherInputs=$oi;BaseHash=$bh;VendorHash=$vh;AlternateHash=$ah;OtherHash=$oh;Target=$target;OtherTarget=$otherTarget}
    }
    function Invoke-Cx([hashtable]$Inputs){$copy=@{}+$Inputs;Invoke-TpmCatalogPatch @copy -Confirm:$false}
    function Plan-Cx([hashtable]$Inputs){$copy=@{}+$Inputs;Get-TpmPatchPlan @copy}
    function Undo-Cx([hashtable]$Inputs,[string]$Recovery){$copy=@{}+$Inputs;Undo-TpmCatalogPatch @copy -RecoveryDirectory $Recovery -Confirm:$false}
    function Set-CxHardware([hashtable]$Inputs,[string]$Vendor){
        $name=if($Vendor -eq 'AMD'){'AMD Radeon fixture'}else{'NVIDIA GeForce fixture'}
$Inputs['HardwareEvidence']=[pscustomobject]@{Adapters=@([pscustomobject]@{Name=$name});MultiGpuAmbiguous=$false;ActiveGpuConfidence='INFERRED';ActiveAdapterIndex=0;ActiveAdapterName=$name}
    }
    function Assert-Cycle([string]$Vendor){
        $c=New-CompositionContext $Vendor;$a=Invoke-Cx $c.BaseInputs;$b=Invoke-Cx $c.VendorInputs
        $undo=Undo-Cx $c.VendorInputs $b.RecoveryDirectory;$undo.Status|Should -BeExactly 'Restored'
        $baseReceipt=[IO.File]::ReadAllText((Join-Path $a.RecoveryDirectory 'receipt.json'))|ConvertFrom-Json
        $vendorReceipt=[IO.File]::ReadAllText((Join-Path $b.RecoveryDirectory 'receipt.json'))|ConvertFrom-Json
        $baseReceipt.Operations[0].AfterFileIdentity|Should -Not -BeExactly $vendorReceipt.Operations[0].RestoredFileIdentity
        (Get-FileHash -LiteralPath $c.Target -Algorithm SHA256).Hash|Should -BeExactly $c.BaseHash
        {Undo-Cx $c.BaseInputs $a.RecoveryDirectory}|Should -Throw -ExpectedMessage 'Grouped target object identity changed.'
        (Get-FileHash -LiteralPath $c.Target -Algorithm SHA256).Hash|Should -BeExactly $c.BaseHash
        $again=Invoke-Cx $c.VendorInputs;$again.RecoveryDirectory|Should -Not -BeExactly $b.RecoveryDirectory
        $undoAgain=Undo-Cx $c.VendorInputs $again.RecoveryDirectory;$undoAgain.Status|Should -BeExactly 'Restored'
        (Get-FileHash -LiteralPath $c.Target -Algorithm SHA256).Hash|Should -BeExactly $c.BaseHash
    }
}
Describe 'Cross Raid receipt composition' {
    It 'records exact predecessor and successor hash and object identity links' {
        $c=New-CompositionContext 'AMD';$a=Invoke-Cx $c.BaseInputs;$b=Invoke-Cx $c.VendorInputs
        $ra=[IO.File]::ReadAllText((Join-Path $a.RecoveryDirectory 'receipt.json'))|ConvertFrom-Json;$rb=[IO.File]::ReadAllText((Join-Path $b.RecoveryDirectory 'receipt.json'))|ConvertFrom-Json
        $ra.CatalogSha256|Should -BeExactly $rb.CatalogSha256;$ra.ProfileId|Should -BeExactly $rb.ProfileId;$ra.GameRoot|Should -BeExactly $rb.GameRoot
        $ra.Operations[0].Target|Should -BeExactly $rb.Operations[0].Target;$ra.Operations[0].AfterSha256|Should -BeExactly $rb.Operations[0].BeforeSha256
        $ra.Operations[0].AfterFileIdentity|Should -BeExactly $rb.Operations[0].BeforeFileIdentity
    }
    It 'completes AMD apply undo identity refusal and reapply lifecycle' { Assert-Cycle 'AMD' }
    It 'completes NVIDIA apply undo identity refusal and reapply lifecycle' { Assert-Cycle 'NVIDIA' }
    It 'retains unrelated live-target tamper protection after a valid apply' {
        $c=New-CompositionContext 'AMD';(Plan-Cx $c.OtherInputs).Status|Should -BeExactly 'Ready'
        $other=Invoke-Cx $c.OtherInputs;$other.Status|Should -BeExactly 'Applied'
        $ready=Plan-Cx $c.OtherInputs;$ready.Status|Should -BeExactly 'AlreadyApplied';$ready.UndoAvailable|Should -BeTrue
        $base=Invoke-Cx $c.BaseInputs;$base.Status|Should -BeExactly 'Applied'
        (Get-FileHash -LiteralPath $c.Target -Algorithm SHA256).Hash|Should -BeExactly $c.BaseHash
        (Plan-Cx $c.VendorInputs).Status|Should -BeExactly 'Ready'
        [IO.File]::WriteAllText($c.OtherTarget,'foreign changed bytes');$foreign=(Get-FileHash -LiteralPath $c.OtherTarget -Algorithm SHA256).Hash
        {Invoke-Cx $c.VendorInputs}|Should -Throw -ExpectedMessage 'Grouped target conflict.'
        (Get-FileHash -LiteralPath $c.OtherTarget -Algorithm SHA256).Hash|Should -BeExactly $foreign
        (Get-FileHash -LiteralPath $c.Target -Algorithm SHA256).Hash|Should -BeExactly $c.BaseHash
    }
    It 'refuses a structurally valid Prepared transaction after a healthy applied base' {
        $c=New-CompositionContext 'AMD';$base=Invoke-Cx $c.BaseInputs;$base.Status|Should -BeExactly 'Applied'
        $id=[guid]::NewGuid().ToString('N');$dir=Join-Path $c.BaseInputs.RecoveryRoot $id;[void][IO.Directory]::CreateDirectory($dir)
        $operation=[ordered]@{Type='CreateFile';Target='rom/shader.farc';BeforeSha256='';AfterSha256=$c.BaseHash;Backup='';BeforeFileIdentity='';AfterFileIdentity='';RestoredFileIdentity=''}
        $prepared=[ordered]@{Schema=3;PatchId=$c.BaseInputs.PatchId;CatalogSha256=$c.BaseInputs.CatalogSha256;ProfileId=$c.BaseInputs.ProfileId;GameRoot=$c.BaseInputs.GameRoot;TransactionId=$id;ExclusiveGroup='';State='Prepared';Operations=@($operation)}
        [IO.File]::WriteAllText((Join-Path $dir 'receipt.json'),($prepared|ConvertTo-Json -Depth 8))
        {Invoke-Cx $c.VendorInputs}|Should -Throw -ExpectedMessage 'A grouped transaction is unresolved; preserve its recovery evidence.'
        (Get-FileHash -LiteralPath $c.Target -Algorithm SHA256).Hash|Should -BeExactly $c.BaseHash
    }
    It 'refuses same-byte foreign object identity without changing bytes' {
        $c=New-CompositionContext 'AMD';$base=Invoke-Cx $c.BaseInputs
        $receipt=[IO.File]::ReadAllText((Join-Path $base.RecoveryDirectory 'receipt.json'))|ConvertFrom-Json
        $replacement=$c.Target+'.new';$held=$c.Target+'.held';[IO.File]::WriteAllText($replacement,'base bytes');[IO.File]::Move($c.Target,$held);[IO.File]::Move($replacement,$c.Target)
        $opened=Open-TpmPatchCreationFile $c.Target
        try{$foreignIdentity=[TpmSupportNativeMethods]::PatchFileIdentity($opened.SafeFileHandle)}finally{$opened.Dispose()}
        $foreignIdentity|Should -Not -BeExactly $receipt.Operations[0].AfterFileIdentity
        {Invoke-Cx $c.VendorInputs}|Should -Throw -ExpectedMessage 'Grouped target object identity changed.'
        (Get-FileHash -LiteralPath $c.Target -Algorithm SHA256).Hash|Should -BeExactly $c.BaseHash
    }
    It 'validates retained replacement backup before vendor undo' {
        $c=New-CompositionContext 'AMD';$base=Invoke-Cx $c.BaseInputs;$vendor=Invoke-Cx $c.VendorInputs
        $receipt=[IO.File]::ReadAllText((Join-Path $vendor.RecoveryDirectory 'receipt.json'))|ConvertFrom-Json
        [IO.File]::WriteAllText($receipt.Operations[0].Backup,'tampered backup')
        {Undo-Cx $c.VendorInputs $vendor.RecoveryDirectory}|Should -Throw -ExpectedMessage 'Grouped retained backup invalid.'
        (Get-FileHash -LiteralPath $c.Target -Algorithm SHA256).Hash|Should -BeExactly $c.VendorHash
    }
    It 'refuses reapply when the restored predecessor has no retained successor witness' {
        $c=New-CompositionContext 'AMD';$base=Invoke-Cx $c.BaseInputs;$vendor=Invoke-Cx $c.VendorInputs
        (Undo-Cx $c.VendorInputs $vendor.RecoveryDirectory).Status|Should -BeExactly 'Restored'
        (Get-FileHash -LiteralPath $c.Target -Algorithm SHA256).Hash|Should -BeExactly $c.BaseHash
        [IO.File]::Delete((Join-Path $vendor.RecoveryDirectory 'receipt.json'))
        $plan=Plan-Cx $c.VendorInputs;$plan.Status|Should -BeExactly 'Unavailable';$plan.Reason|Should -BeExactly 'Grouped target object identity changed.'
        (Get-FileHash -LiteralPath $c.Target -Algorithm SHA256).Hash|Should -BeExactly $c.BaseHash
    }
    It 'refuses a restored chain whose terminal checkpoint was tampered' {
        $c=New-CompositionContext 'AMD';$base=Invoke-Cx $c.BaseInputs;$vendor=Invoke-Cx $c.VendorInputs
        (Undo-Cx $c.VendorInputs $vendor.RecoveryDirectory).Status|Should -BeExactly 'Restored'
        $snapshot=Join-Path (Join-Path (Join-Path $c.BaseInputs.RecoveryRoot 'ReceiptHistory') 'Snapshots') ($vendor.RecoveryDirectory.Split([IO.Path]::DirectorySeparatorChar)[-1]+'_Restored')
        [IO.File]::WriteAllText((Join-Path $snapshot 'manifest.json'),'tampered')
        $plan=Plan-Cx $c.VendorInputs;$plan.Status|Should -BeExactly 'Unavailable'
        $plan.Reason|Should -BeExactly 'Grouped terminal receipt history is unavailable or corrupt.'
        (Get-FileHash -LiteralPath $c.Target -Algorithm SHA256).Hash|Should -BeExactly $c.BaseHash
    }
    It 'keeps hardware selection independent of receipt-chain validation' {
        $c=New-CompositionContext 'AMD';Set-CxHardware $c.VendorInputs 'NVIDIA'
        $plan=Plan-Cx $c.VendorInputs;$plan.Status|Should -BeExactly 'Unavailable'
        $plan.Reason|Should -BeExactly 'A different exclusive hardware variant applies: fixture.NVIDIA'
        (Test-Path -LiteralPath $c.Target)|Should -BeFalse
    }
    It 'retains same-group exclusion between hardware variants' {
        $c=New-CompositionContext 'AMD';[IO.File]::Copy((Join-Path $c.VendorInputs.PayloadRoot 'base.bin'),$c.Target);$amd=Invoke-Cx $c.VendorInputs;$amd.Status|Should -BeExactly 'Applied'
        Set-CxHardware $c.AlternateInputs 'NVIDIA'
        $plan=Plan-Cx $c.AlternateInputs;$plan.Status|Should -BeExactly 'Unavailable'
        $plan.Reason|Should -BeExactly 'An exclusive recipe is active; undo it before selecting another variant.'
        (Get-FileHash -LiteralPath $c.Target -Algorithm SHA256).Hash|Should -BeExactly $c.VendorHash
    }
    It 'refuses ambiguous outgoing receipt edges' {
        $c=New-CompositionContext 'AMD';$base=Invoke-Cx $c.BaseInputs;$vendor=Invoke-Cx $c.VendorInputs
        $receiptPath=Join-Path $vendor.RecoveryDirectory 'receipt.json';$receipt=[IO.File]::ReadAllText($receiptPath)|ConvertFrom-Json
        $duplicateId=[guid]::NewGuid().ToString('N');$duplicateDirectory=Join-Path $c.VendorInputs.RecoveryRoot $duplicateId
        [void][IO.Directory]::CreateDirectory($duplicateDirectory)
        $duplicateBackup=Join-Path $duplicateDirectory 'retained.bin';[IO.File]::Copy($receipt.Operations[0].Backup,$duplicateBackup)
        $receipt.TransactionId=$duplicateId;$receipt.Operations[0].Backup=$duplicateBackup
        [IO.File]::WriteAllText((Join-Path $duplicateDirectory 'receipt.json'),($receipt|ConvertTo-Json -Depth 12))
        $plan=Plan-Cx $c.VendorInputs;$plan.Status|Should -BeExactly 'Unavailable'
        $plan.Reason|Should -BeExactly 'Grouped receipt chain is ambiguous.'
        (Get-FileHash -LiteralPath $c.Target -Algorithm SHA256).Hash|Should -BeExactly $c.VendorHash
    }
    It 'binds the prevalidated root receipt to the bounded snapshot' {
        $c=New-CompositionContext 'AMD';$base=Invoke-Cx $c.BaseInputs;$vendor=Invoke-Cx $c.VendorInputs
        $plan=Plan-Cx $c.VendorInputs;$plan.Status|Should -BeExactly 'AlreadyApplied'
        $rootPath=Join-Path $base.RecoveryDirectory 'receipt.json';$rootReceipt=[IO.File]::ReadAllText($rootPath)|ConvertFrom-Json
        $changed=[IO.File]::ReadAllText($rootPath)|ConvertFrom-Json;$changed|Add-Member -NotePropertyName UntrustedExtra -NotePropertyValue 'changed'
        [IO.File]::WriteAllText($rootPath,($changed|ConvertTo-Json -Depth 12))
        {Test-TpmMultiPatchReceiptChain -Plan $plan -RootReceipt $rootReceipt -RootDirectory $base.RecoveryDirectory -CatalogSha256 $c.VendorInputs.CatalogSha256}|Should -Throw -ExpectedMessage 'Grouped receipt-chain root changed during bounded census.'
        (Get-FileHash -LiteralPath $c.Target -Algorithm SHA256).Hash|Should -BeExactly $c.VendorHash
    }
    It 'fails closed when the bounded receipt census exceeds its directory limit' {
        $c=New-CompositionContext 'AMD';$base=Invoke-Cx $c.BaseInputs;$vendor=Invoke-Cx $c.VendorInputs
        for($i=0;$i -lt 257;$i++){[void][IO.Directory]::CreateDirectory((Join-Path $c.VendorInputs.RecoveryRoot ([guid]::NewGuid().ToString('N'))))}
        $plan=Plan-Cx $c.VendorInputs;$plan.Status|Should -BeExactly 'Unavailable'
        $plan.Reason|Should -BeExactly 'Exclusive-group receipt census exceeds the 256-directory bound.'
        (Get-FileHash -LiteralPath $c.Target -Algorithm SHA256).Hash|Should -BeExactly $c.VendorHash
    }
    It 'preserves ordinary schema two replacement undo' {
        $root=Join-Path $TestDrive ('legacy'+[guid]::NewGuid().ToString('N').Substring(0,8));$game=Join-Path $root 'game';$payload=Join-Path $root 'payload';$recovery=Join-Path $root 'recovery';$protected=Join-Path $root 'protected'
        foreach($dir in @($game,$payload,$recovery,$protected)){[void][IO.Directory]::CreateDirectory($dir)}
        $exe=Join-Path $game 'legacy.exe';[IO.File]::WriteAllText($exe,'legacy executable')
        $target=Join-Path $game 'asset.bin';$source=Join-Path $payload 'after.bin';[IO.File]::WriteAllText($target,'before');[IO.File]::WriteAllText($source,'after')
        $before=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash;$after=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        $entry=[pscustomobject]@{Id='legacy.replace';ProfileId='Legacy';Executable='legacy.exe';ExecutableSha256=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash;SourceUrl='https://example.invalid/legacy';SourceRevision=('E'*40);Operations=@([pscustomobject]@{Type='ReplaceFile';Target='asset.bin';BeforeSha256=$before;AfterSha256=$after;Payload='after.bin';PayloadSha256=$after})}
        $content=[pscustomobject]@{Schema=2;Entries=@($entry)}|ConvertTo-Json -Depth 8
        $inputs=@{CatalogContent=$content;CatalogSha256=(Get-TpmPatchTextSha256 $content);PatchId=$entry.Id;ProfileId='Legacy';GameRoot=$game;PayloadRoot=$payload;RecoveryRoot=$recovery;ProtectedRoots=@($protected)}
        $applied=Invoke-Cx $inputs;$applied.Status|Should -BeExactly 'Applied'
        (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash|Should -BeExactly $after
        $undone=Undo-Cx $inputs $applied.RecoveryDirectory;$undone.Status|Should -BeExactly 'Restored'
        (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash|Should -BeExactly $before
    }
    It 'refuses a cyclic terminal witness' {
        $c=New-CompositionContext 'AMD';$base=Invoke-Cx $c.BaseInputs;$vendor=Invoke-Cx $c.VendorInputs
        (Undo-Cx $c.VendorInputs $vendor.RecoveryDirectory).Status|Should -BeExactly 'Restored'
        $plan=Plan-Cx $c.VendorInputs;$plan.Status|Should -BeExactly 'Ready'
        $baseReceipt=[IO.File]::ReadAllText((Join-Path $base.RecoveryDirectory 'receipt.json'))|ConvertFrom-Json
        $originalReceiptPath=Join-Path $vendor.RecoveryDirectory 'receipt.json';$receipt=[IO.File]::ReadAllText($originalReceiptPath)|ConvertFrom-Json
        $cycleId=[guid]::NewGuid().ToString('N');$cycleDirectory=Join-Path $c.VendorInputs.RecoveryRoot $cycleId
        [void][IO.Directory]::CreateDirectory($cycleDirectory)
        $cycleBackup=Join-Path $cycleDirectory 'retained.bin';[IO.File]::Copy($receipt.Operations[0].Backup,$cycleBackup)
        $receipt.TransactionId=$cycleId;$receipt.Operations[0].Backup=$cycleBackup
        $receipt.Operations[0].RestoredFileIdentity=$baseReceipt.Operations[0].AfterFileIdentity
        [IO.File]::WriteAllText((Join-Path $cycleDirectory 'receipt.json'),($receipt|ConvertTo-Json -Depth 12))
        $checkpoint=New-TpmResetSnapshot -BackupsRoot $c.VendorInputs.RecoveryRoot -StoreRoot (Join-Path $c.VendorInputs.RecoveryRoot 'ReceiptHistory') -SnapshotId ($cycleId+'_Restored') -Kind Checkpoint -TargetPaths @((Join-Path $cycleDirectory 'receipt.json')) -PayloadRetention StateOnly
        $checkpoint.Status|Should -BeExactly 'VERIFIED'
        [IO.File]::Delete($originalReceiptPath)
        $refused=Plan-Cx $c.VendorInputs;$refused.Status|Should -BeExactly 'Unavailable'
        $refused.Reason|Should -BeExactly 'Grouped receipt chain contains a cycle.'
        (Get-FileHash -LiteralPath $c.Target -Algorithm SHA256).Hash|Should -BeExactly $c.BaseHash
    }
    It 'rejects oversized and cumulative receipt snapshots before accepting a chain' {
        $c=New-CompositionContext 'AMD';$base=Invoke-Cx $c.BaseInputs;$vendor=Invoke-Cx $c.VendorInputs
        $oversizeId=[guid]::NewGuid().ToString('N');$oversizeDirectory=Join-Path $c.VendorInputs.RecoveryRoot $oversizeId
        [void][IO.Directory]::CreateDirectory($oversizeDirectory);[IO.File]::WriteAllText((Join-Path $oversizeDirectory 'receipt.json'),('x'*262145))
        $oversized=Plan-Cx $c.VendorInputs;$oversized.Status|Should -BeExactly 'Unavailable'
        $oversized.Reason|Should -BeExactly 'Exclusive-group receipt exceeds the supported bound.'
        [IO.File]::Delete((Join-Path $oversizeDirectory 'receipt.json'));[IO.Directory]::Delete($oversizeDirectory)
        $padded='{}'+(' '*262142)
        for($i=0;$i -lt 65;$i++){
            $id=[guid]::NewGuid().ToString('N');$dir=Join-Path $c.VendorInputs.RecoveryRoot $id
            [void][IO.Directory]::CreateDirectory($dir);[IO.File]::WriteAllText((Join-Path $dir 'receipt.json'),$padded)
        }
        $cumulative=Plan-Cx $c.VendorInputs;$cumulative.Status|Should -BeExactly 'Unavailable'
        $cumulative.Reason|Should -BeExactly 'Exclusive-group receipt census exceeds the 16 MiB bound.'
        (Get-FileHash -LiteralPath $c.Target -Algorithm SHA256).Hash|Should -BeExactly $c.VendorHash
    }
    It 'rejects direct external use of structural receipt modes' {
        $c=New-CompositionContext 'AMD';$catalog=$c.BaseInputs.CatalogContent|ConvertFrom-Json;$baseEntry=@($catalog.Entries|Where-Object Id -CEQ $c.BaseInputs.PatchId)[0]
        {Get-TpmMultiPatchPlan -Entry $baseEntry -PatchId $baseEntry.Id -ProfileId $baseEntry.ProfileId -GameRoot $c.BaseInputs.GameRoot -PayloadRoot $c.BaseInputs.PayloadRoot -RecoveryRoot $c.BaseInputs.RecoveryRoot -CatalogSha256 $c.BaseInputs.CatalogSha256 -CatalogEntries @($catalog.Entries) -ForUndo -Probe -ReceiptChainTarget 'rom/shader.farc'}|Should -Throw -ExpectedMessage 'Receipt-chain structural inspection is internal to the exclusive gate.'
        $applied=Invoke-Cx $c.BaseInputs;$plan=Plan-Cx $c.BaseInputs;$plan|Add-Member -NotePropertyName Status -NotePropertyValue 'Structural' -Force
        $receipt=[IO.File]::ReadAllText((Join-Path $applied.RecoveryDirectory 'receipt.json'))|ConvertFrom-Json
        {Assert-TpmMultiPatchReceipt -Plan $plan -Receipt $receipt -CatalogSha256 $c.BaseInputs.CatalogSha256 -Directory $applied.RecoveryDirectory -ReceiptChainTarget 'rom/shader.farc'}|Should -Throw -ExpectedMessage 'Receipt-chain validation is internal to the exclusive gate.'
    }
}
