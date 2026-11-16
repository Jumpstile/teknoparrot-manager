BeforeAll {
    $script:Tree = (Split-Path -Parent $PSScriptRoot)
    $scriptPath = Join-Path $script:Tree 'TeknoParrot-Manager.ps1'
    $tokens = $null; $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errs)
    if ($errs.Count -gt 0) { throw 'parse failed' }
    $fa = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $fx = Join-Path $TestDrive 'fn.ps1'
    ($fa | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $fx -Encoding utf8
    $pm = Join-Path $TestDrive 'scripts'
    [void][IO.Directory]::CreateDirectory($pm)
    Copy-Item -LiteralPath (Join-Path $script:Tree 'scripts\TpmProgress.psm1') -Destination $pm -Force
    . $fx
    . (Join-Path $script:Tree 'Tests\TpmExtractedScriptState.ps1')
    $script:TitleTokenStopWords = [System.Collections.Generic.HashSet[string]]::new([string[]]@('the','of','a','an','and'), [System.StringComparer]::OrdinalIgnoreCase)
    $script:FFBBlasterUnsupportedPlatforms = @('pcsx2x6')
    $script:FFBBlasterNamePattern = 'ffb.*blaster|blaster.*ffb'
    $script:RawThrillsPathLimits = @{}
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false
}
Describe 'Finding 9: overlap switch vs hook-DLL collision' {
    It 'keeps native FFB on when the plugin is skipped because d3d9.dll already exists' {
        $root = Join-Path $TestDrive 'ov'
        $up = Join-Path $root 'UserProfiles'; $tp = Join-Path $root 'TeknoParrot'
        $gd = Join-Path $root 'OverlapGame'; $cache = Join-Path $root 'FFBPlugin'
        New-Item -ItemType Directory -Path $up, (Join-Path $tp 'GameProfiles'), $gd, $cache -Force | Out-Null
        $exe = Join-Path $gd 'overlap.exe'
        [IO.File]::WriteAllBytes($exe, [Text.Encoding]::ASCII.GetBytes('MZ-overlap'))
        # a foreign hook DLL (e.g. TPM's own ReShade d3d9.dll) already owns the plugin destination
        [IO.File]::WriteAllText((Join-Path $gd 'd3d9.dll'), 'reshade-hook')
        $xml = "<GameProfile><EmulationProfile>Daytona3</EmulationProfile><GamePath>$exe</GamePath><ConfigValues><FieldInformation><CategoryName>FFB Blaster</CategoryName><FieldName>Enable</FieldName><FieldType>Bool</FieldType><FieldValue>1</FieldValue></FieldInformation></ConfigValues></GameProfile>"
        $enc = New-Object System.Text.UTF8Encoding $false
        [IO.File]::WriteAllText((Join-Path $up 'Overlap.xml'), $xml, $enc)
        [IO.File]::WriteAllText((Join-Path $tp 'GameProfiles\Canonical.xml'), $xml, $enc)
        Mock Write-Host {}
        Mock Write-Log {}
        Mock Get-FFBPluginSourceRevision { [pscustomobject]@{ Revision=('a'*40); Repository='f/f'; ManifestUrl='https://x'; Trust='SourcePinnedAuditHash' } }
        Mock Get-FFBPluginGameMap { [ordered]@{ OverlapGame = 'd3d9.dll' } }
        Mock Invoke-FFBPluginDownload {
            param([string]$destDir, [string]$SourceRevision)
            $files = [ordered]@{}; $ev = @()
            foreach ($n in 'MAME32.dll','MAME64.dll') {
                $p = Join-Path $destDir "TPM-FFB-t-$n"; [IO.File]::WriteAllBytes($p, [byte[]](1,2,3,4)); $files[$n] = $p
                $ev += [pscustomobject]@{ FileName=$n; SourceUrl='https://x'; SourceRevision=$SourceRevision; Sha256=(Get-FileHash $p -Algorithm SHA256).Hash; Trust='SourcePinnedAuditHash'; DownloadPath=$p }
            }
            [pscustomobject]@{ Succeeded=$true; Files=$files; Evidence=$ev; ResiduePaths=@(); Reason=$null }
        }
        Mock Get-ExeArchitecture { 'x64' }
        Mock Read-HostSafe { 'N' }
        $r = Invoke-FFBPluginSetup -UserProfilesDir $up -CacheDir $cache -TpRoot $tp -NativeEnabledCodes @('Overlap')
        $native = (Read-Xml (Join-Path $up 'Overlap.xml')).SelectSingleNode('/GameProfile/ConfigValues/FieldInformation/FieldValue').InnerText
        $pluginDeployed = (Get-Content -LiteralPath (Join-Path $gd 'd3d9.dll') -Raw) -ne 'reshade-hook'
        [Console]::Error.WriteLine(("OBSERVED Succeeded={0} Reason={1} Deployed={2} SkippedCollision={3} NativeFieldValue={4} PluginDeployed={5}" -f $r.Succeeded,$r.Reason,$r.Deployed,$r.SkippedCollision,$native,$pluginDeployed))
        # No FFB at all is the bug: plugin not installed AND native off.
        ($native -eq '1' -or $pluginDeployed) | Should -BeTrue -Because 'the game must keep one FFB owner'
    }
    It 'keeps the ownership entry of a plugin game planned before a keep-native game' {
        $root = Join-Path $TestDrive 'order'
        $up = Join-Path $root 'UserProfiles'; $tp = Join-Path $root 'TeknoParrot'; $cache = Join-Path $root 'FFBPlugin'
        New-Item -ItemType Directory -Path $up, (Join-Path $tp 'GameProfiles'), $cache -Force | Out-Null
        $enc = New-Object System.Text.UTF8Encoding $false
        foreach ($g in @(@{N='AGame';Native=0}, @{N='BGame';Native=1})) {
            $gd = Join-Path $root $g.N
            [void][IO.Directory]::CreateDirectory($gd)
            $exe = Join-Path $gd ($g.N.ToLower() + '.exe')
            [IO.File]::WriteAllBytes($exe, [Text.Encoding]::ASCII.GetBytes('MZ-' + $g.N))
            $xml = "<GameProfile><EmulationProfile>Daytona3</EmulationProfile><GamePath>$exe</GamePath><ConfigValues><FieldInformation><CategoryName>FFB Blaster</CategoryName><FieldName>Enable</FieldName><FieldType>Bool</FieldType><FieldValue>$($g.Native)</FieldValue></FieldInformation></ConfigValues></GameProfile>"
            [IO.File]::WriteAllText((Join-Path $up ($g.N + '.xml')), $xml, $enc)
        }
        [IO.File]::WriteAllText((Join-Path $tp 'GameProfiles\Canonical.xml'), '<GameProfile/>', $enc)
        Mock Write-Host {}
        Mock Write-Log {}
        Mock Get-FFBPluginSourceRevision { [pscustomobject]@{ Revision=('a'*40); Repository='f/f'; ManifestUrl='https://x'; Trust='SourcePinnedAuditHash' } }
        Mock Get-FFBPluginGameMap { [ordered]@{ AGame = 'd3d9.dll'; BGame = 'd3d9.dll' } }
        Mock Invoke-FFBPluginDownload {
            param([string]$destDir, [string]$SourceRevision)
            $files = [ordered]@{}; $ev = @()
            foreach ($n in 'MAME32.dll','MAME64.dll') {
                $p = Join-Path $destDir "TPM-FFB-t-$n"; [IO.File]::WriteAllBytes($p, [byte[]](1,2,3,4)); $files[$n] = $p
                $ev += [pscustomobject]@{ FileName=$n; SourceUrl='https://x'; SourceRevision=$SourceRevision; Sha256=(Get-FileHash $p -Algorithm SHA256).Hash; Trust='SourcePinnedAuditHash'; DownloadPath=$p }
            }
            [pscustomobject]@{ Succeeded=$true; Files=$files; Evidence=$ev; ResiduePaths=@(); Reason=$null }
        }
        Mock Get-ExeArchitecture { 'x64' }
        Mock Read-TpmYesNo { 'Y' }
        $r = Invoke-FFBPluginSetup -UserProfilesDir $up -CacheDir $cache -TpRoot $tp -NativeEnabledCodes @('BGame')
        $r.Deployed | Should -Be 1
        $installed = Join-Path $root 'AGame\d3d9.dll'
        Test-Path -LiteralPath $installed | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root 'BGame\d3d9.dll') | Should -BeFalse
        $owned = @(Read-FFBPluginOwnership -CacheDir $cache)
        $owned.Count | Should -Be 1
        $owned[0].Destination | Should -BeExactly $installed
    }
}
