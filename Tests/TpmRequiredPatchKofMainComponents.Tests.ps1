param(
    [string]$RepositoryRoot = ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))),
    [string]$FragmentPath = (Join-Path $RepositoryRoot 'tools/required-patches/fragments/kof-main-wined3d-components-20261015.json')
)

BeforeAll {
    $script:kofProgramRoot = [IO.Path]::GetFullPath($RepositoryRoot)
    $enginePath = Join-Path $script:kofProgramRoot 'scripts/TpmRequiredPatchEngine.ps1'
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

    $script:kofFragment=[IO.File]::ReadAllText([IO.Path]::GetFullPath($FragmentPath),[Text.Encoding]::UTF8)|ConvertFrom-Json -ErrorAction Stop
    $script:kofCatalogPath=Join-Path $script:kofProgramRoot 'scripts/TpmRequiredPatchRecipes.json'
    $script:kofCatalog=[IO.File]::ReadAllText($script:kofCatalogPath,[Text.Encoding]::UTF8)|ConvertFrom-Json -ErrorAction Stop
    $script:kofCatalogSha256=(Get-FileHash -LiteralPath $script:kofCatalogPath -Algorithm SHA256).Hash

    $mainPath=Join-Path $script:kofProgramRoot 'TeknoParrot-Manager.ps1'
    $tokens=$null;$errors=$null
    $mainAst=[System.Management.Automation.Language.Parser]::ParseFile($mainPath,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw 'Unable to parse manager helper source for isolated required-patch transactions.'}
    foreach($name in @('Get-TpmSupportNativeType','Get-TpmSupportFinalPathFromHandle','Remove-TpmSupportHandle','Test-TpmPathOverlap','Get-TpmFileState','Read-HostSafe','Read-PathWithBrowse')){
        $function=$mainAst.Find({param($node)$node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$true)
        if(-not $function){throw "Required manager helper '$name' was not found."}
        . ([scriptblock]::Create($function.Extent.Text))
    }
    [void](Get-TpmSupportNativeType)

    $suitePath=Join-Path $script:kofProgramRoot 'Tests/TeknoParrot-Manager.Tests.ps1'
    $suiteTokens=$null;$suiteErrors=$null
    $suiteAst=[System.Management.Automation.Language.Parser]::ParseFile($suitePath,[ref]$suiteTokens,[ref]$suiteErrors)
    if($suiteErrors.Count){throw 'Unable to parse the existing required-patch fixture source.'}
    $describe=$suiteAst.Find({param($node)$node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Describe' -and $node.CommandElements.Count -ge 3 -and $node.CommandElements[1].Value -ceq 'Required patch engine and local recipes'},$true)
    if(-not $describe){throw 'The existing required-patch fixture container was not found.'}
    $beforeEach=$describe.CommandElements[2].ScriptBlock.Find({param($node)$node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'BeforeEach'},$true)
    if(-not $beforeEach){throw 'The existing required-patch fixture setup was not found.'}
    $script:kofFixtureSetup=$beforeEach.CommandElements[-1].ScriptBlock.GetScriptBlock()

    function New-KofSyntheticContext {
        param([Parameter(Mandatory)]$Recipe,[Parameter(Mandatory)]$Fixture,[switch]$WrongExecutable)
        $entry=$Recipe|ConvertTo-Json -Depth 20|ConvertFrom-Json
        $entry.Executable='synthetic.exe'
        $entry.ExecutableSha256=if($WrongExecutable){'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF'}else{$Fixture.ExecutableSha256}
        $entry.SourceUrl=''
        $entry.SourceRevision=''
        $entry.SourceRole='Main'
        $bytes=[Text.Encoding]::UTF8.GetBytes(('synthetic payload for '+[string]$entry.Id+'; never execute'))
        $payloadRelative='payload/'+[string]$entry.Id+'.bin'
        $payload=Join-Path $Fixture.PayloadRoot ($payloadRelative.Replace('/','\\'))
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($payload))
        [IO.File]::WriteAllBytes($payload,$bytes)
        $entry.SourceSize=[int]$bytes.Length
        $entry.SourceSha1=(Get-FileHash -LiteralPath $payload -Algorithm SHA1).Hash
        $entry.SourceSha256=(Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash
        $entry.Operations[0].Payload=$payloadRelative
        $entry.Operations[0].AfterSha256=$entry.SourceSha256
        $entry.Operations[0].PayloadSha256=$entry.SourceSha256
        $content=[pscustomobject]@{Schema=3;Entries=@($entry)}|ConvertTo-Json -Depth 20 -Compress
        $inputs=@{
            CatalogContent=$content;CatalogSha256=(Get-TpmPatchTextSha256 $content);PatchId=$entry.Id;ProfileId=$entry.ProfileId
            GameRoot=$Fixture.GameRoot;PayloadRoot=$Fixture.PayloadRoot;RecoveryRoot=$Fixture.RecoveryRoot;ProtectedRoots=@($Fixture.ProtectedRoot)
        }
        $target=Join-Path $Fixture.GameRoot ($entry.Operations[0].Target.Replace('/','\\'))
        return [pscustomobject]@{Entry=$entry;Inputs=$inputs;Target=$target;Payload=$payload;PayloadBytes=$bytes;PayloadSha256=$entry.SourceSha256}
    }
}

Describe 'KOF Maximum Impact Regulation A exact Main component restorations' {
    AfterEach {
        $script:TpmRequiredPatchCatalogSha256=$script:kofCatalogSha256
        $script:TpmOwnedLayout=$null
        $script:gamesInstallFolder=$null
        $script:requiredPatchInputQueue=$null
        $script:requiredPatchHostMessages=$null
        $script:requiredPatchBrowsePrompts=$null
    }

    It 'binds the four exact Main source members and the integrated catalog' {
        $script:kofFragment.BaseCatalog.Schema | Should -Be 3
        $script:kofFragment.BaseCatalog.EntryCount | Should -Be 64
        $script:kofFragment.BaseCatalog.Sha256 | Should -BeExactly '214415946FBD9C64EE37A673119A43DE9334F54F42E4B7910DF3784F6908D250'
        $script:kofFragment.Entries.Count | Should -Be 4
        $script:kofCatalog.Schema | Should -Be 3
        $script:kofCatalog.Entries.Count | Should -Be 69
        @($script:kofCatalog.Entries.Id|Sort-Object -Unique).Count | Should -Be 69
        @($script:kofCatalog.Entries.ProfileId|Sort-Object -Unique).Count | Should -Be 25
        @($script:kofCatalog.Entries|ForEach-Object{'{0}|{1}|{2}|{3}' -f $_.ProfileId,$_.BuildName,$_.Executable,$_.ExecutableSha256}|Sort-Object -Unique).Count | Should -Be 25
        @($script:kofCatalog.Entries|ForEach-Object{$_.Operations}|Where-Object Type -CEQ 'CreateFile').Count | Should -Be 61
        @($script:kofCatalog.Entries|ForEach-Object{$_.Operations}|Where-Object Type -CEQ 'ReplaceFile').Count | Should -Be 8
        (Get-FileHash -LiteralPath $script:kofCatalogPath -Algorithm SHA256).Hash | Should -BeExactly $script:TpmRequiredPatchCatalogSha256
        $script:kofCatalogSha256 | Should -BeExactly $script:TpmRequiredPatchCatalogSha256
        $expected=@{
            'kof-mi-reg-a-main-d3d8-restore'=@{Member='d3d8.dll';Size=286015;Sha1='55542B7AB1B628FC2D7057A5FBE3B9048383F9A5';Sha256='33B625B818B450203A4FCA0CC6068B722434535B94615FF3077239079866B115';Payload='payload/d3d8.dll'}
            'kof-mi-reg-a-main-d3d9-restore'=@{Member='d3d9.dll';Size=381363;Sha1='BB46749FA47DA8A79A21171B1A93E9CA7F06E75C';Sha256='A7FBE8B9AC236CE657E966925C5C7A8C1F0B5AA19011C1B983508CC07B3D7F13';Payload='payload/d3d9.dll'}
            'kof-mi-reg-a-main-ddraw-restore'=@{Member='ddraw.dll';Size=928562;Sha1='7C6B0D12A06830C184726440AEEBDFA8A3D90F4C';Sha256='BD7E1717B82E33046C0E2CF9A402E55630F3EE3B3299892FA82684B2F7E8D0B3';Payload='payload/ddraw.dll'}
            'kof-mi-reg-a-main-wined3d-restore'=@{Member='wined3d.dll';Size=4145581;Sha1='3C592F1C9956709359B50FBAD7C31F88010E7B50';Sha256='5F74F2BB715BFAA9A94127CD830050FDA15D34C02047633053C35D85D5469926';Payload='payload/wined3d.dll'}
        }
        foreach($entry in $script:kofFragment.Entries){
            $pin=$expected[[string]$entry.Id]
            $pin | Should -Not -BeNullOrEmpty
            $entry.ProfileId | Should -BeExactly 'KingofFightersMaximumImpactRegulationA'
            $entry.BuildName | Should -BeExactly 'King of Fighters Maximum Impact Regulation A (2007)[Taito Type X2][TP]'
            $entry.Executable | Should -BeExactly 'game.exe'
            $entry.ExecutableSha256 | Should -BeExactly 'CC40C926E19F17DD373C87A3D83120CB6C22C2F3CA9B492E28A6178813F6256F'
            $entry.SourceRole | Should -BeExactly 'Main'
            $entry.SourceSet | Should -BeExactly 'King of Fighters Maximum Impact Regulation A (2007)[Taito Type X2][TP].zip'
            $entry.SourceUrl | Should -BeExactly ''
            $entry.SourceRevision | Should -BeExactly ''
            $entry.SourceEntry | Should -BeExactly $pin.Member
            $entry.SourceSize | Should -Be $pin.Size
            $entry.SourceSha1 | Should -BeExactly $pin.Sha1
            $entry.SourceSha1.Length | Should -Be 40
            $entry.SourceSha256 | Should -BeExactly $pin.Sha256
            @($entry.Prerequisites).Count | Should -Be 0
            [string]$entry.ExclusiveGroup | Should -BeExactly ''
            $entry.PSObject.Properties['HardwarePredicate'] | Should -BeNullOrEmpty
            $entry.PSObject.Properties['AllowExecutableSelfPatch'] | Should -BeNullOrEmpty
            $entry.Operations.Count | Should -Be 1
            $entry.Operations[0].Type | Should -BeExactly 'CreateFile'
            $entry.Operations[0].Target | Should -BeExactly $pin.Member
            $entry.Operations[0].BeforeState | Should -BeExactly 'Absent'
            $entry.Operations[0].AfterSha256 | Should -BeExactly $pin.Sha256
            $entry.Operations[0].Payload | Should -BeExactly $pin.Payload
            $entry.Operations[0].PayloadSha256 | Should -BeExactly $pin.Sha256
            $matches=@($script:kofCatalog.Entries|Where-Object Id -CEQ $entry.Id)
            $matches.Count | Should -Be 1
            ($matches[0]|ConvertTo-Json -Depth 20 -Compress) | Should -BeExactly ($entry|ConvertTo-Json -Depth 20 -Compress)
        }
        @($script:kofFragment.Entries|Where-Object SourceEntry -CEQ 'dddraw.dll').Count | Should -Be 0
    }

    It 'stages each exact member from a synthetic local Main ZIP without executing bytes' {
        & $script:kofFixtureSetup
        $fixture=$script:requiredPatchFixture
        Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
        $sourceRoot=Join-Path $fixture.Root 'kof-source'
        [void][IO.Directory]::CreateDirectory($sourceRoot)
        $archivePath=Join-Path $sourceRoot $script:kofFragment.Entries[0].SourceSet
        $archive=[IO.Compression.ZipFile]::Open($archivePath,[IO.Compression.ZipArchiveMode]::Create)
        $references=@{}
        try {
            foreach($recipe in $script:kofFragment.Entries){
                $bytes=[Text.Encoding]::UTF8.GetBytes(('synthetic Main ZIP bytes for '+[string]$recipe.Id+'; never execute'))
                $reference=Join-Path $fixture.PayloadRoot ([string]$recipe.Id+'.reference')
                [IO.File]::WriteAllBytes($reference,$bytes)
                $member=$archive.CreateEntry([string]$recipe.SourceEntry,[IO.Compression.CompressionLevel]::Optimal)
                $stream=$member.Open()
                try{$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
                $references[[string]$recipe.Id]=[pscustomobject]@{Bytes=$bytes;Size=$bytes.Length;Sha1=(Get-FileHash -LiteralPath $reference -Algorithm SHA1).Hash;Sha256=(Get-FileHash -LiteralPath $reference -Algorithm SHA256).Hash}
            }
        } finally {$archive.Dispose()}
        $owned=Join-Path $fixture.Root 'manager/owned'
        $temp=Join-Path $owned 'Temp'
        [void][IO.Directory]::CreateDirectory($temp)
        $script:TpmOwnedLayout=[pscustomobject]@{Root=$owned;Temp=$temp;Backups=(Join-Path $owned 'Backups')}
        foreach($recipe in $script:kofFragment.Entries){
            $entry=$recipe|ConvertTo-Json -Depth 20|ConvertFrom-Json
            $entry.SourceUrl='';$entry.SourceRevision='';$entry.SourceRole='Main'
            $pin=$references[[string]$entry.Id]
            $entry.SourceSize=[int]$pin.Size;$entry.SourceSha1=$pin.Sha1;$entry.SourceSha256=$pin.Sha256
            $entry.Operations[0].AfterSha256=$pin.Sha256;$entry.Operations[0].PayloadSha256=$pin.Sha256
            $stage=New-TpmRequiredPatchPayloadStage -Entry $entry -SourceRoot $sourceRoot
            $stage.SourceArchive | Should -BeExactly $archivePath
            $stage.SourceEntry | Should -BeExactly $entry.SourceEntry
            $stage.Size | Should -Be $pin.Size
            $stage.Sha256 | Should -BeExactly $pin.Sha256
            (Get-Item -LiteralPath $stage.Payload).Length | Should -Be $pin.Size
            (Get-FileHash -LiteralPath $stage.Payload -Algorithm SHA1).Hash | Should -BeExactly $pin.Sha1
            (Get-FileHash -LiteralPath $stage.Payload -Algorithm SHA256).Hash | Should -BeExactly $pin.Sha256
            Test-PathInside $stage.Root $temp | Should -BeTrue
            Test-PathInside $stage.Payload $stage.Root | Should -BeTrue
        }
    }

    It 'applies each absent target, recognizes exact repeats, receipt-undos, and preserves siblings' {
        foreach($recipe in $script:kofFragment.Entries){
            & $script:kofFixtureSetup
            $fixture=$script:requiredPatchFixture
            $case=New-KofSyntheticContext -Recipe $recipe -Fixture $fixture
            $inputs=$case.Inputs
            $sibling=Join-Path $fixture.GameRoot 'kof-sibling-sentinel.txt'
            [IO.File]::WriteAllText($sibling,'preserve unrelated sibling')
            (Get-TpmPatchPlan @inputs).Status | Should -BeExactly 'Ready'
            $applied=Invoke-TpmCatalogPatch @inputs -Confirm:$false
            $applied.Status | Should -BeExactly 'Applied'
            (Get-FileHash -LiteralPath $case.Target -Algorithm SHA256).Hash | Should -BeExactly $case.PayloadSha256
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($case.Target)) | Should -Be ([Convert]::ToBase64String($case.PayloadBytes))
            (Get-TpmPatchPlan @inputs).Status | Should -BeExactly 'AlreadyApplied'
            (Invoke-TpmCatalogPatch @inputs -Confirm:$false).Status | Should -BeExactly 'AlreadyApplied'
            (Undo-TpmCatalogPatch @inputs -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false).Status | Should -BeExactly 'Restored'
            Test-Path -LiteralPath $case.Target | Should -BeFalse
            [IO.File]::ReadAllText($sibling) | Should -BeExactly 'preserve unrelated sibling'
        }
    }

    It 'refuses unknown existing bytes and wrong executable identity before mutation' {
        foreach($recipe in $script:kofFragment.Entries){
            & $script:kofFixtureSetup
            $fixture=$script:requiredPatchFixture
            $case=New-KofSyntheticContext -Recipe $recipe -Fixture $fixture
            $unknown=[Text.Encoding]::UTF8.GetBytes('unknown existing KOF component; never execute')
            [IO.File]::WriteAllBytes($case.Target,$unknown)
            $inputs=$case.Inputs
            (Get-TpmPatchPlan @inputs).Status | Should -BeExactly 'Unavailable'
            {Invoke-TpmCatalogPatch @inputs -Confirm:$false} | Should -Throw
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($case.Target)) | Should -Be ([Convert]::ToBase64String($unknown))
            @(Get-ChildItem -LiteralPath $fixture.RecoveryRoot -Force).Count | Should -Be 0

            & $script:kofFixtureSetup
            $fixture=$script:requiredPatchFixture
            $wrong=New-KofSyntheticContext -Recipe $recipe -Fixture $fixture -WrongExecutable
            $wrongInputs=$wrong.Inputs
            (Get-TpmPatchPlan @wrongInputs).Status | Should -BeExactly 'Unavailable'
            {Invoke-TpmCatalogPatch @wrongInputs -Confirm:$false} | Should -Throw
            Test-Path -LiteralPath $wrong.Target | Should -BeFalse
            @(Get-ChildItem -LiteralPath $fixture.RecoveryRoot -Force).Count | Should -Be 0
        }
    }

    It 'refuses receipt undo after same-byte replacement changes the created file identity' {
        foreach($recipe in $script:kofFragment.Entries){
            & $script:kofFixtureSetup
            $fixture=$script:requiredPatchFixture
            $case=New-KofSyntheticContext -Recipe $recipe -Fixture $fixture
            $sibling=Join-Path $fixture.GameRoot 'kof-sibling-sentinel.txt'
            [IO.File]::WriteAllText($sibling,'preserve unrelated sibling')
            $inputs=$case.Inputs
            $applied=Invoke-TpmCatalogPatch @inputs -Confirm:$false
            $applied.Status | Should -BeExactly 'Applied'
            $receiptPath=Join-Path $applied.RecoveryDirectory 'receipt.json'
            $receipt=[IO.File]::ReadAllText($receiptPath)|ConvertFrom-Json
            $boundIdentity=[string]$receipt.Operations[0].AfterFileIdentity
            $boundIdentity | Should -Match '^[A-F0-9]{8}:[A-F0-9]{16}$'
            $held=Join-Path $fixture.GameRoot ($case.Entry.Operations[0].Target+'.held')
            [IO.File]::Move($case.Target,$held)
            [IO.File]::WriteAllBytes($case.Target,[byte[]]$case.PayloadBytes)
            $opened=Open-TpmPatchCreationFile $case.Target
            try{$newIdentity=[TpmSupportNativeMethods]::PatchFileIdentity($opened.SafeFileHandle)}finally{$opened.Dispose()}
            $newIdentity | Should -Not -BeExactly $boundIdentity
            $failure=$null
            try{$null=Undo-TpmCatalogPatch @inputs -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false}catch{$failure=$_.Exception.Message}
            $failure | Should -Match 'Grouped target object identity changed'
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($case.Target)) | Should -Be ([Convert]::ToBase64String($case.PayloadBytes))
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($held)) | Should -Be ([Convert]::ToBase64String($case.PayloadBytes))
            [IO.File]::ReadAllText($sibling) | Should -BeExactly 'preserve unrelated sibling'
            $after=[IO.File]::ReadAllText($receiptPath)|ConvertFrom-Json
            $after.State | Should -BeExactly 'Applied'
            $after.Operations[0].AfterFileIdentity | Should -BeExactly $boundIdentity
        }
    }
}
