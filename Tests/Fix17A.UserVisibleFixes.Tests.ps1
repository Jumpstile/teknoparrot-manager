#Requires -Module Pester

# Things a user can see or lose, fixed after the last review:
#   - two detected TeknoParrot copies still find the saved settings
#   - a support package with missing evidence says it is partial
#   - Library Health does not say "OK" when no profile could be read
#   - a profile removed during a failed save is reported truthfully, with the kept copy named
#   - re-running force feedback with TPM's own plugin file does not fail or leave two owners
# Synthetic folders in $TestDrive only.

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
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $fx
    . (Join-Path $script:Tree 'Tests\TpmExtractedScriptState.ps1')
    $script:DisplayVersion = 'v1.0 RC8'
    $script:logPath = Join-Path $TestDrive 'fix17a.log'
    $script:logWarnShown = $false
    $script:TitleTokenStopWords = [System.Collections.Generic.HashSet[string]]::new([string[]]@('the','of','a','an','and'), [System.StringComparer]::OrdinalIgnoreCase)
    $script:FFBBlasterUnsupportedPlatforms = @('pcsx2x6')
    $script:FFBBlasterNamePattern = 'ffb.*blaster|blaster.*ffb'
    $script:RawThrillsPathLimits = @{}
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false
}

Describe 'Two detected TeknoParrot copies' {
    It 'finds the saved settings of the second copy' {
        Mock Find-TeknoParrotRoot {
            $list = New-Object System.Collections.ArrayList
            [void]$list.Add('C:\TP1'); [void]$list.Add('D:\TP2')
            return ,$list
        }
        Mock Get-TpmOwnedConfigPathForRoot { Join-Path (Join-Path $TestDrive 'cfg') (([string]$TeknoParrotRoot).Replace(':', '').Replace('\', '_') + '.json') }
        [void][IO.Directory]::CreateDirectory((Join-Path $TestDrive 'cfg'))
        [IO.File]::WriteAllText((Join-Path $TestDrive 'cfg\D_TP2.json'), '{}')
        @(Get-TpmDetectedRootList) | Should -Be @('C:\TP1', 'D:\TP2')
        $found = Find-TpmSavedConfigPath -ScriptRoot (Join-Path $TestDrive 'noscript') -LocatorPath (Join-Path $TestDrive 'nolocator.json')
        $found | Should -BeExactly (Join-Path $TestDrive 'cfg\D_TP2.json')
    }
}

Describe 'Support package result screen' {
    BeforeEach { Mock Write-TpmOutcome { $script:f17Outcome = @{ Title = $Title; Status = $Status; Blocks = $DetailBlocks } } }

    It 'says partial when evidence is missing, and names what is missing' {
        $result = [pscustomobject]@{
            Succeeded = $true; Partial = $true; PackagePath = (Join-Path $TestDrive 'pkg.zip'); Errors = @()
            PartialReasons = @('Registration ledger could not be collected.')
            Records = @([pscustomobject]@{ Source = 'Log:main'; Status = 'CollectionFailed' })
        }
        Write-TpmSupportPackageResult -Result $result
        $script:f17Outcome.Title | Should -Match 'partial'
        $script:f17Outcome.Status | Should -Be 'Attention'
        (@($script:f17Outcome.Blocks | ForEach-Object { $_.Lines }) -join "`n") | Should -Match 'Registration ledger could not be collected'
    }

    It 'stays a plain success when nothing is missing' {
        $result = [pscustomobject]@{ Succeeded = $true; Partial = $false; PackagePath = (Join-Path $TestDrive 'pkg.zip'); Errors = @(); PartialReasons = @(); Records = @() }
        Write-TpmSupportPackageResult -Result $result
        $script:f17Outcome.Title | Should -Be 'Support package created.'
    }
}

Describe 'Library Health game paths row' {
    It 'does not say OK when no profile could be read' {
        $result = [pscustomobject]@{
            DiscoveryComplete = $true; Registered = 3; Broken = @(); Empty = @(); Valid = @(); Unreadable = @('A', 'B', 'C')
            GpuFixNeeded = @(); FfbBlasterNeeded = @(); DgVoodoo2Needed = @()
        }
        $row = @(Get-TpmLibraryHealthRows -Result $result | Where-Object Area -eq 'Game paths')[0]
        $row.Text | Should -Not -Match '^OK'
        $row.Text | Should -Match '^Could not check'
    }
}

Describe 'PostgreSQL recovery choices while the safety copy is unverified' {
    It 'offers R and P and defaults to R when the safety copy is verified' {
        $menu = Get-TpmPostgresBackupFailureChoices -AuthFailure $true -PasswordRejected $true -EvidenceUnavailable $false
        $menu.Choices | Should -Be @('P', 'X', 'R', 'I', 'D', 'O', 'B')
        $menu.Default | Should -BeExactly 'R'
        $menu.Prompt | Should -Match 'default R'
        $menu.Notice | Should -BeNullOrEmpty
    }

    It 'offers X only after PostgreSQL positively rejected the password' {
        (Get-TpmPostgresBackupFailureChoices -AuthFailure $true -PasswordRejected $false -EvidenceUnavailable $false).Choices | Should -Be @('P', 'R', 'I', 'D', 'O', 'B')
    }

    It 'offers only the choices that are allowed, defaults to B and says what to do when the safety copy is unverified' {
        $menu = Get-TpmPostgresBackupFailureChoices -AuthFailure $true -PasswordRejected $true -EvidenceUnavailable $true
        $menu.Choices | Should -Be @('X', 'I', 'D', 'O', 'B')
        $menu.Default | Should -BeExactly 'B'
        ($menu.Lines -join "`n") | Should -Not -Match '\[R\]|\[P\]'
        $menu.Notice | Should -Match 'start this setup again'
        (Get-TpmPostgresBackupFailureChoices -AuthFailure $false -PasswordRejected $false -EvidenceUnavailable $true).Choices | Should -Be @('I', 'D', 'O', 'B')
    }
}

Describe 'Manual path repair when a save removed the old profile' {
    BeforeEach {
        Mock Write-Log {}
        Mock Write-Host {}
        Mock Write-TpmCompactExtractionProgress {}
        Mock Read-TpmYesNo { 'Y' }
    }

    It 'reports a profile that needs attention and names the kept copy' {
        $root = Join-Path $TestDrive 'repair'
        $profiles = Join-Path $root 'UserProfiles'; $games = Join-Path $root 'Games'
        foreach ($folder in @($profiles, (Join-Path $games 'G'))) { [void][IO.Directory]::CreateDirectory($folder) }
        $exe = Join-Path $games 'G\game.exe'
        [IO.File]::WriteAllText($exe, 'game')
        [IO.File]::WriteAllText((Join-Path $profiles 'GGAME.xml'), '<GameProfile><GamePath>C:\missing\game.exe</GamePath><ExecutableName>game.exe</ExecutableName></GameProfile>')
        $script:f17Exe = $exe
        Mock Read-PathWithBrowse { $script:f17Exe }
        $kept = Join-Path $profiles 'GGAME.xml.abc.tmp'
        $script:f17Kept = $kept
        Mock Save-Xml { throw ("Saving 'x' failed after the previous file was removed; the new content was kept at '" + $script:f17Kept + "'. disk error") }
        $r = Invoke-LibraryHealthManualPathRepair -UserProfilesDir $profiles -GamesInstallFolder $games -BrokenGames @('GGAME')
        (Test-TpmTransactionResult -Result $r) | Should -BeTrue
        $r.Outcome | Should -BeExactly 'ACTION_REQUIRED'
        $r.Summary | Should -Not -Match 'No profile was changed'
        @($r.RetainedCopies) | Should -Be @($kept)
    }
}

Describe 'Force feedback re-run with the plugin already installed by TeknoParrot Manager' {
    It 'replaces its own recorded plugin file without an error and keeps one owner' {
        $root = Join-Path $TestDrive 'rerun'
        $up = Join-Path $root 'UserProfiles'; $tp = Join-Path $root 'TeknoParrot'
        $gd = Join-Path $root 'OverlapGame'; $cache = Join-Path $root 'FFBPlugin'
        New-Item -ItemType Directory -Path $up, (Join-Path $tp 'GameProfiles'), $gd, $cache -Force | Out-Null
        $exe = Join-Path $gd 'overlap.exe'
        [IO.File]::WriteAllBytes($exe, [Text.Encoding]::ASCII.GetBytes('MZ-overlap'))
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
        Mock Read-TpmYesNo { 'N' }

        $first = Invoke-FFBPluginSetup -UserProfilesDir $up -CacheDir $cache -TpRoot $tp -NativeEnabledCodes @('Overlap')
        $first.Deployed | Should -Be 1
        $hook = Join-Path $gd 'd3d9.dll'
        Test-Path -LiteralPath $hook | Should -BeTrue

        # TeknoParrot (or the user) switches native force feedback back on; the user runs the setup again and picks the plugin.
        [IO.File]::WriteAllText((Join-Path $up 'Overlap.xml'), $xml, $enc)
        $second = Invoke-FFBPluginSetup -UserProfilesDir $up -CacheDir $cache -TpRoot $tp -NativeEnabledCodes @('Overlap')
        $second.Errors | Should -Be 0
        $second.Deployed | Should -Be 1
        Test-Path -LiteralPath $hook | Should -BeTrue
        (Read-Xml (Join-Path $up 'Overlap.xml')).SelectSingleNode('/GameProfile/ConfigValues/FieldInformation/FieldValue').InnerText | Should -Be '0'
        $owned = @(Read-FFBPluginOwnership -CacheDir $cache)
        $owned.Count | Should -Be 1
        $owned[0].Destination | Should -BeExactly $hook
        (Get-FileHash -LiteralPath $hook -Algorithm SHA256).Hash | Should -BeExactly ([string]$owned[0].DeployedSha256)

        # Run it once more when the game's 32-bit/64-bit type cannot be read: the game is skipped and keeps its working plugin file and its record.
        Mock Get-ExeArchitecture { $null }
        $third = Invoke-FFBPluginSetup -UserProfilesDir $up -CacheDir $cache -TpRoot $tp
        $third.Deployed | Should -Be 0
        $third.Errors | Should -Be 0
        Test-Path -LiteralPath $hook | Should -BeTrue
        (Get-FileHash -LiteralPath $hook -Algorithm SHA256).Hash | Should -BeExactly ([string]$owned[0].DeployedSha256)
        $keptRecords = @(Read-FFBPluginOwnership -CacheDir $cache)
        $keptRecords.Count | Should -Be 1
        $keptRecords[0].Destination | Should -BeExactly $hook
    }

    It 'removes the two plugin copies it staged in the cache once the setup is finished' {
        # Mutation: remove the cleanup after the setup -> two more random-named DLL copies stay in the cache after every run.
        $root = Join-Path $TestDrive 'stagedcleanup'
        $up = Join-Path $root 'UserProfiles'; $tp = Join-Path $root 'TeknoParrot'
        $gd = Join-Path $root 'OverlapGame'; $cache = Join-Path $root 'FFBPlugin'
        New-Item -ItemType Directory -Path $up, (Join-Path $tp 'GameProfiles'), $gd, $cache -Force | Out-Null
        $exe = Join-Path $gd 'overlap.exe'
        [IO.File]::WriteAllBytes($exe, [Text.Encoding]::ASCII.GetBytes('MZ-overlap'))
        $xml = "<GameProfile><EmulationProfile>Daytona3</EmulationProfile><GamePath>$exe</GamePath><ConfigValues><FieldInformation><CategoryName>FFB Blaster</CategoryName><FieldName>Enable</FieldName><FieldType>Bool</FieldType><FieldValue>1</FieldValue></FieldInformation></ConfigValues></GameProfile>"
        $enc = New-Object System.Text.UTF8Encoding $false
        [IO.File]::WriteAllText((Join-Path $up 'Overlap.xml'), $xml, $enc)
        [IO.File]::WriteAllText((Join-Path $tp 'GameProfiles\Canonical.xml'), $xml, $enc)
        $customCopy = Join-Path $cache 'MAME64.dll'
        [IO.File]::WriteAllBytes($customCopy, [byte[]](9, 9, 9))
        Mock Write-Host {}
        Mock Write-Log {}
        Mock Get-FFBPluginSourceRevision { [pscustomobject]@{ Revision=('a'*40); Repository='f/f'; ManifestUrl='https://x'; Trust='SourcePinnedAuditHash' } }
        Mock Get-FFBPluginGameMap { [ordered]@{ OverlapGame = 'd3d9.dll' } }
        Mock Invoke-FFBPluginDownload {
            param([string]$destDir, [string]$SourceRevision)
            $files = [ordered]@{}; $ev = @()
            foreach ($n in 'MAME32.dll','MAME64.dll') {
                $p = Join-Path $destDir ('TPM-FFB-source-{0}-{1}' -f [guid]::NewGuid().ToString('N'), $n); [IO.File]::WriteAllBytes($p, [byte[]](1,2,3,4)); $files[$n] = $p
                $ev += [pscustomobject]@{ FileName=$n; SourceUrl='https://x'; SourceRevision=$SourceRevision; Sha256=(Get-FileHash $p -Algorithm SHA256).Hash; Trust='SourcePinnedAuditHash'; DownloadPath=$p }
            }
            [pscustomobject]@{ Succeeded=$true; Files=$files; Evidence=$ev; ResiduePaths=@(); Reason=$null }
        }
        Mock Get-ExeArchitecture { 'x64' }
        Mock Read-TpmYesNo { 'N' }

        $result = Invoke-FFBPluginSetup -UserProfilesDir $up -CacheDir $cache -TpRoot $tp -NativeEnabledCodes @('Overlap')

        $result.Deployed | Should -Be 1
        @(Get-ChildItem -LiteralPath $cache -Filter 'TPM-FFB-source-*' -File).Count | Should -Be 0
        Test-Path -LiteralPath $customCopy -PathType Leaf | Should -BeTrue
    }
}
