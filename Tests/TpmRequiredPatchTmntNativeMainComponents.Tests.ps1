param(
    [string]$RepositoryRoot = ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))),
    [string]$FragmentPath = (Join-Path $RepositoryRoot 'tools/required-patches/fragments/tmnt-native-main-components-20261015.json')
)

BeforeAll {
    $script:tmntProgramRoot = [IO.Path]::GetFullPath($RepositoryRoot)
    $enginePath = Join-Path $script:tmntProgramRoot 'scripts/TpmRequiredPatchEngine.ps1'
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

    $script:tmntFragment=[IO.File]::ReadAllText([IO.Path]::GetFullPath($FragmentPath),[Text.Encoding]::UTF8)|ConvertFrom-Json -ErrorAction Stop
    $script:tmntCatalogPath=Join-Path $script:tmntProgramRoot 'scripts/TpmRequiredPatchRecipes.json'
    $script:tmntCatalog=[IO.File]::ReadAllText($script:tmntCatalogPath,[Text.Encoding]::UTF8)|ConvertFrom-Json -ErrorAction Stop
    $script:tmntCatalogSha256=(Get-FileHash -LiteralPath $script:tmntCatalogPath -Algorithm SHA256).Hash
    $script:TpmRequiredPatchCatalogSha256=$script:tmntCatalogSha256

    $mainPath=Join-Path $script:tmntProgramRoot 'TeknoParrot-Manager.ps1'
    $tokens=$null;$errors=$null
    $mainAst=[System.Management.Automation.Language.Parser]::ParseFile($mainPath,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw 'Unable to parse manager helper source for isolated required-patch transactions.'}
    foreach($name in @('Get-TpmSupportNativeType','Get-TpmSupportFinalPathFromHandle','Remove-TpmSupportHandle','Test-TpmPathOverlap','Get-TpmFileState','Read-HostSafe','Read-PathWithBrowse')){
        $function=$mainAst.Find({param($node)$node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$true)
        if(-not $function){throw "Required manager helper '$name' was not found."}
        . ([scriptblock]::Create($function.Extent.Text))
    }
    [void](Get-TpmSupportNativeType)

    $suitePath=Join-Path $script:tmntProgramRoot 'Tests/TeknoParrot-Manager.Tests.ps1'
    $suiteTokens=$null;$suiteErrors=$null
    $suiteAst=[System.Management.Automation.Language.Parser]::ParseFile($suitePath,[ref]$suiteTokens,[ref]$suiteErrors)
    if($suiteErrors.Count){throw 'Unable to parse the existing required-patch fixture source.'}
    $describe=$suiteAst.Find({param($node)$node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Describe' -and $node.CommandElements.Count -ge 3 -and $node.CommandElements[1].Value -ceq 'Required patch engine and local recipes'},$true)
    if(-not $describe){throw 'The existing required-patch fixture container was not found.'}
    $beforeEach=$describe.CommandElements[2].ScriptBlock.Find({param($node)$node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'BeforeEach'},$true)
    if(-not $beforeEach){throw 'The existing required-patch fixture setup was not found.'}
    $script:tmntFixtureSetup=$beforeEach.CommandElements[-1].ScriptBlock.GetScriptBlock()

    function New-TmntSyntheticContext {
        param([Parameter(Mandatory)]$Recipe,[Parameter(Mandatory)]$Fixture,[switch]$WrongExecutable)
        $entry=$Recipe|ConvertTo-Json -Depth 20|ConvertFrom-Json
        $entry.Executable='synthetic.exe'
        $entry.ExecutableSha256=if($WrongExecutable){'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF'}else{$Fixture.ExecutableSha256}
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


Describe 'TMNT 1.59 exact Main component restorations' {
    AfterEach {
        $script:TpmRequiredPatchCatalogSha256=$script:tmntCatalogSha256
        $script:TpmOwnedLayout=$null
        $script:gamesInstallFolder=$null
        $script:requiredPatchInputQueue=$null
        $script:requiredPatchHostMessages=$null
        $script:requiredPatchBrowsePrompts=$null
    }
    It 'binds both exact Main source members and the integrated catalog' {
        $script:tmntFragment.BaseCatalog.Schema | Should -Be 3
        $script:tmntFragment.BaseCatalog.EntryCount | Should -Be 62
        $script:tmntFragment.BaseCatalog.Sha256 | Should -BeExactly '8F30A2BC8CC8AC6B96A324962F9E12792572E08BE6512B1A1808420D6BDB5195'
        $script:tmntFragment.Entries.Count | Should -Be 2
        $script:tmntCatalog.Schema | Should -Be 3
        $script:tmntCatalog.Entries.Count | Should -Be 64
        @($script:tmntCatalog.Entries.Id|Sort-Object -Unique).Count | Should -Be 64
        @($script:tmntCatalog.Entries.ProfileId|Sort-Object -Unique).Count | Should -Be 23
        @($script:tmntCatalog.Entries|ForEach-Object{$_.Operations}|Where-Object Type -CEQ 'CreateFile').Count | Should -Be 56
        @($script:tmntCatalog.Entries|ForEach-Object{$_.Operations}|Where-Object Type -CEQ 'ReplaceFile').Count | Should -Be 8
        (Get-FileHash -LiteralPath $script:tmntCatalogPath -Algorithm SHA256).Hash | Should -BeExactly $script:TpmRequiredPatchCatalogSha256
        $expected=@{
            'tmnt-orenvid-main-restore'=@{Member='TMNT_Data/Plugins/x86_64/OrenVid.dll';Size=90112;Sha1='8219DDE96F5DDD78C2BD0A7656C100426D4F942D';Sha256='17886C8A04342C254E8666596046D132DB0F63CEB047439F8EB3B5A35902E4AD';Payload='payload/OrenVid.dll'}
            'tmnt-pk-unityplugin-main-restore'=@{Member='TMNT_Data/Plugins/x86_64/PK-UnityPlugin.dll';Size=16210432;Sha1='0254401B2AD3623AA16BF2B2CFD408991084FE80';Sha256='CDC95711BCF10B097A30D4B09F7A304980DABA5000F3813555A80A71ABF04238';Payload='payload/PK-UnityPlugin.dll'}
        }
        foreach($entry in $script:tmntFragment.Entries){
            $pin=$expected[[string]$entry.Id]
            $pin | Should -Not -BeNullOrEmpty
            $entry.ProfileId | Should -BeExactly 'TMNT'
            $entry.BuildName | Should -BeExactly 'Teenage Mutant Ninja Turtles (1.59)(2021-07-26)(USA)[Raw Thrills PC][TP]'
            $entry.Executable | Should -BeExactly 'TMNT.exe'
            $entry.ExecutableSha256 | Should -BeExactly '11AEDEEE2136DA3BF69392B5FE76818707BDD8E413AE99F829F394F8B80B295F'
            $entry.SourceRole | Should -BeExactly 'Main'
            $entry.SourceSet | Should -BeExactly 'Teenage Mutant Ninja Turtles (1.59)(2021-07-26)(USA)[Raw Thrills PC][TP].zip'
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
            $matches=@($script:tmntCatalog.Entries|Where-Object Id -CEQ $entry.Id)
            $matches.Count | Should -Be 1
            ($matches[0]|ConvertTo-Json -Depth 20 -Compress) | Should -BeExactly ($entry|ConvertTo-Json -Depth 20 -Compress)
        }
        $anchor=@($script:tmntCatalog.Entries|Where-Object Id -CEQ 'tmnt-bepinex-plugin-restore')
        $anchor.Count | Should -Be 1
        $anchor[0].ProfileId | Should -BeExactly 'TMNT'
        $anchor[0].BuildName | Should -BeExactly 'Teenage Mutant Ninja Turtles (1.59)(2021-07-26)(USA)[Raw Thrills PC][TP]'
        $anchor[0].Executable | Should -BeExactly 'TMNT.exe'
        $anchor[0].ExecutableSha256 | Should -BeExactly '11AEDEEE2136DA3BF69392B5FE76818707BDD8E413AE99F829F394F8B80B295F'
    }

    It 'stages both exact member paths from a synthetic local Main ZIP without executing bytes' {
        & $script:tmntFixtureSetup
        $fixture=$script:requiredPatchFixture
        Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
        $sourceRoot=Join-Path $fixture.Root 'tmnt-source'
        [void][IO.Directory]::CreateDirectory($sourceRoot)
        $archivePath=Join-Path $sourceRoot $script:tmntFragment.Entries[0].SourceSet
        $archive=[IO.Compression.ZipFile]::Open($archivePath,[IO.Compression.ZipArchiveMode]::Create)
        $references=@{}
        try {
            foreach($recipe in $script:tmntFragment.Entries){
                $bytes=[Text.Encoding]::UTF8.GetBytes(('synthetic ZIP bytes for '+[string]$recipe.Id+'; never execute'))
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
        foreach($recipe in $script:tmntFragment.Entries){
            $entry=$recipe|ConvertTo-Json -Depth 20|ConvertFrom-Json
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

    It 'applies each absent target, recognizes exact repeats, receipt-undos, and preserves siblings and unknown bytes' {
        foreach($recipe in $script:tmntFragment.Entries){
            & $script:tmntFixtureSetup
            $fixture=$script:requiredPatchFixture
            $case=New-TmntSyntheticContext -Recipe $recipe -Fixture $fixture
            $inputs=$case.Inputs
            $parent=[IO.Path]::GetDirectoryName($case.Target)
            [void][IO.Directory]::CreateDirectory($parent)
            $config=Join-Path $parent 'TPFIX.ini';$neighbor=Join-Path $parent 'Neighbor.dll'
            [IO.File]::WriteAllText($config,'manual config; preserve')
            [IO.File]::WriteAllText($neighbor,'unrelated plugin; preserve and never execute')
            (Get-TpmPatchPlan @inputs).Status | Should -BeExactly 'Ready'
            $applied=Invoke-TpmCatalogPatch @inputs -Confirm:$false
            $applied.Status | Should -BeExactly 'Applied'
            (Get-FileHash -LiteralPath $case.Target -Algorithm SHA256).Hash | Should -BeExactly $case.PayloadSha256
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($case.Target)) | Should -Be ([Convert]::ToBase64String($case.PayloadBytes))
            (Get-TpmPatchPlan @inputs).Status | Should -BeExactly 'AlreadyApplied'
            (Invoke-TpmCatalogPatch @inputs -Confirm:$false).Status | Should -BeExactly 'AlreadyApplied'
            (Undo-TpmCatalogPatch @inputs -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false).Status | Should -BeExactly 'Restored'
            Test-Path -LiteralPath $case.Target | Should -BeFalse
            [IO.File]::ReadAllText($config) | Should -BeExactly 'manual config; preserve'
            [IO.File]::ReadAllText($neighbor) | Should -BeExactly 'unrelated plugin; preserve and never execute'
            $unknown=[Text.Encoding]::UTF8.GetBytes('unknown existing native component; never execute')
            [IO.File]::WriteAllBytes($case.Target,$unknown)
            (Get-TpmPatchPlan @inputs).Status | Should -BeExactly 'Unavailable'
            {Invoke-TpmCatalogPatch @inputs -Confirm:$false} | Should -Throw
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($case.Target)) | Should -Be ([Convert]::ToBase64String($unknown))
            [IO.File]::ReadAllText($config) | Should -BeExactly 'manual config; preserve'
            [IO.File]::ReadAllText($neighbor) | Should -BeExactly 'unrelated plugin; preserve and never execute'
        }
    }

    It 'refuses a wrong executable identity before target or recovery mutation' {
        foreach($recipe in $script:tmntFragment.Entries){
            & $script:tmntFixtureSetup
            $fixture=$script:requiredPatchFixture
            $case=New-TmntSyntheticContext -Recipe $recipe -Fixture $fixture -WrongExecutable
            $inputs=$case.Inputs
            (Get-TpmPatchPlan @inputs).Status | Should -BeExactly 'Unavailable'
            {Invoke-TpmCatalogPatch @inputs -Confirm:$false} | Should -Throw
            Test-Path -LiteralPath $case.Target | Should -BeFalse
            @(Get-ChildItem -LiteralPath $fixture.RecoveryRoot -Force).Count | Should -Be 0
        }
    }

    It 'refuses receipt undo after same-byte replacement changes the created file identity' {
        foreach($recipe in $script:tmntFragment.Entries){
            & $script:tmntFixtureSetup
            $fixture=$script:requiredPatchFixture
            $case=New-TmntSyntheticContext -Recipe $recipe -Fixture $fixture
            $inputs=$case.Inputs
            $parent=[IO.Path]::GetDirectoryName($case.Target)
            [void][IO.Directory]::CreateDirectory($parent)
            $applied=Invoke-TpmCatalogPatch @inputs -Confirm:$false
            $applied.Status | Should -BeExactly 'Applied'
            $receiptPath=Join-Path $applied.RecoveryDirectory 'receipt.json'
            $receipt=[IO.File]::ReadAllText($receiptPath)|ConvertFrom-Json
            $boundIdentity=[string]$receipt.Operations[0].AfterFileIdentity
            $boundIdentity | Should -Match '^[A-F0-9]{8}:[A-F0-9]{16}$'
            $held=Join-Path $parent ([IO.Path]::GetFileName($case.Target)+'.held')
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
            $after=[IO.File]::ReadAllText($receiptPath)|ConvertFrom-Json
            $after.State | Should -BeExactly 'Applied'
            $after.Operations[0].AfterFileIdentity | Should -BeExactly $boundIdentity
        }
    }
}
