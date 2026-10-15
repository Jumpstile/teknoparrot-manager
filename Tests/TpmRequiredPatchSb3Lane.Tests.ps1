BeforeAll {
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


    $script:sb3DeltaPath=Join-Path $PSScriptRoot '..\tools\required-patches\fragments\plugins-sb3-20261015.json'
    $script:sb3Delta=[IO.File]::ReadAllText($script:sb3DeltaPath,[Text.Encoding]::UTF8)|ConvertFrom-Json -ErrorAction Stop
    $mainPath=Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens=$null;$errors=$null
    $mainAst=[System.Management.Automation.Language.Parser]::ParseFile($mainPath,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw 'Unable to parse manager helper source for isolated SB3 transaction proof.'}
    foreach($name in @('Get-TpmSupportNativeType','Get-TpmSupportFinalPathFromHandle','Remove-TpmSupportHandle','Test-TpmPathOverlap','Get-TpmFileState','Read-HostSafe','Read-PathWithBrowse')){
        $functionAst=$mainAst.Find({param($node)$node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$true)
        if(-not $functionAst){throw ('Missing required SB3 proof helper: '+$name)}
        . ([scriptblock]::Create($functionAst.Extent.Text))
    }
    [void](Get-TpmSupportNativeType)
    $suitePath=Join-Path $PSScriptRoot 'TeknoParrot-Manager.Tests.ps1'
    $suiteTokens=$null;$suiteErrors=$null
    $suiteAst=[System.Management.Automation.Language.Parser]::ParseFile($suitePath,[ref]$suiteTokens,[ref]$suiteErrors)
    if($suiteErrors.Count){throw 'Unable to parse the existing required-patch fixture source.'}
    $describe=$suiteAst.Find({param($node)$node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Describe' -and $node.CommandElements.Count -ge 3 -and $node.CommandElements[1].Value -ceq 'Required patch engine and local recipes'},$true)
    if(-not $describe){throw 'The existing required-patch fixture container was not found.'}
    $beforeEach=$describe.CommandElements[2].ScriptBlock.Find({param($node)$node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'BeforeEach'},$true)
    if(-not $beforeEach){throw 'The existing required-patch fixture setup was not found.'}
    $script:sb3FixtureSetup=$beforeEach.CommandElements[-1].ScriptBlock.GetScriptBlock()
}

Describe 'SB3 required BepInEx plugin delta' {
    It 'binds the exact guide build, official profile executable and absent-only source target' {
        $entry=@($script:sb3Delta.Entries)
        $entry.Count | Should -Be 1
        $entry[0].ProfileId | Should -BeExactly 'SB3'
        $entry[0].BuildName | Should -BeExactly 'Super Bikes 3 (1.91 x64)(2021-10-01)[Raw Thrills][TP]'
        $entry[0].Executable | Should -BeExactly 'fnfmega.exe'
        $entry[0].ExecutableSha256 | Should -BeExactly '7F84AE68A35587EA87312ED59247EB0379F00826B8F2473A09155792A90AEEAD'
        $entry[0].SourceRole | Should -BeExactly 'UserSelected'
        $entry[0].SourceSet | Should -BeExactly 'Super Bikes 3 (1.91 x64) - TPPlugin_v1.09 x64.zip'
        $entry[0].SourceEntry | Should -BeExactly 'SB3TPPlugin.dll'
        $entry[0].SourceSize | Should -Be 121856
        $entry[0].SourceSha1 | Should -BeExactly 'E4BCCBCBB32EEE7DCE2E24AAF8990E4812BC81F5'
        $entry[0].SourceSha1.Length | Should -Be 40
        $entry[0].SourceSha1 | Should -Match '^[A-F0-9]{40}$'
        $entry[0].SourceSha256 | Should -BeExactly '9E8464FD54F272398CDE3E2AACB2D5F6D8508A2F90C3E7D7793166016BFFF3D5'
        $entry[0].Prerequisites[0].Path | Should -BeExactly 'BepInEx/core/BepInEx.dll'
        $entry[0].Operations[0].Type | Should -BeExactly 'CreateFile'
        $entry[0].Operations[0].Target | Should -BeExactly 'BepInEx/plugins/SB3TPPlugin.dll'
        $entry[0].Operations[0].BeforeState | Should -BeExactly 'Absent'
        $entry[0].Operations[0].AfterSha256 | Should -BeExactly $entry[0].SourceSha256
    }

    It 'applies absent-only, skips an exact repeat, undoes to absence, and refuses foreign bytes' {
        & $script:sb3FixtureSetup
        $fixture=$script:requiredPatchFixture
        $entry=$script:sb3Delta.Entries[0]|ConvertTo-Json -Depth 20|ConvertFrom-Json
        $priorPin=$script:TpmRequiredPatchCatalogSha256
        $priorLayout=$script:TpmOwnedLayout
        try {
            $entry.Executable='synthetic.exe'
            $entry.ExecutableSha256=$fixture.ExecutableSha256
            $entry.SourceRole='UserSelected'
            $entry.SourceSet='synthetic-sb3-plugin.zip'
            $entry.SourceSize=[int](Get-Item -LiteralPath $fixture.CreatedPayload).Length
            $entry.SourceSha1=(Get-FileHash -LiteralPath $fixture.CreatedPayload -Algorithm SHA1).Hash
            $entry.SourceSha256=$fixture.CreatedSha256
            $entry.Operations[0].Payload='payload/SB3TPPlugin.dll'
            $entry.Operations[0].AfterSha256=$fixture.CreatedSha256
            $entry.Operations[0].PayloadSha256=$fixture.CreatedSha256
            $content=[pscustomobject]@{Schema=3;Entries=@($entry)}|ConvertTo-Json -Depth 20
            $catalogHash=Get-TpmPatchTextSha256 $content
            $core=Join-Path $fixture.GameRoot 'BepInEx\core\BepInEx.dll'
            $target=Join-Path $fixture.GameRoot ($entry.Operations[0].Target.Replace('/','\'))
            $missing=Test-TpmRequiredPatchPrerequisites -Entry $entry -GameRoot $fixture.GameRoot
            $missing.Satisfied | Should -BeFalse
            @($missing.Missing|Where-Object Id -CEQ 'bepinex-core').Count | Should -Be 1
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($core))
            [IO.File]::WriteAllText($core,'synthetic BepInEx core; never load')
            (Test-TpmRequiredPatchPrerequisites -Entry $entry -GameRoot $fixture.GameRoot).Satisfied | Should -BeTrue
            $payload=Join-Path $fixture.PayloadRoot $entry.Operations[0].Payload.Replace('/','\')
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($payload))
            [IO.File]::WriteAllBytes($payload,[IO.File]::ReadAllBytes($fixture.CreatedPayload))
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
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
            (Undo-TpmCatalogPatch @inputs -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false).Status | Should -Be 'Restored'
            Test-Path -LiteralPath $target | Should -BeFalse
            [IO.File]::WriteAllText($target,'foreign bytes; never execute')
            (Get-TpmPatchPlan @inputs).Status | Should -Be 'Unavailable'
            [IO.File]::ReadAllText($target) | Should -Be 'foreign bytes; never execute'
        } finally {
            $script:TpmOwnedLayout=$priorLayout
            $script:TpmRequiredPatchCatalogSha256=$priorPin
        }
    }
}
