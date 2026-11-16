#Requires -Module Pester

# GitHub issue 399: on a first run, answering Yes to the optional ReShade offer on a PC with no ReShade file used to print
# "ReShade 64-bit DLL not found yet. Run 'ReShade setup' from the main menu..." and move on. Yes must start the same
# download-or-use-my-copy step as the main-menu ReShade setup (the dgVoodoo2 offer had the same dead end).
# The step is now two functions shared by the menu and the first-run offer. They are tested here with the web, the
# prompts and the file picker replaced. What this CANNOT prove: a real download from reshade.me or GitHub.
# The first-run offer itself is top-level script code, so a source check proves it calls the shared step.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $script:f405Source = [System.IO.File]::ReadAllText($scriptPath)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX405 bootstrap could not parse the production script.' }
    $wanted = @('Request-TpmReShadeSourceDll', 'Request-TpmDgVoodoo2SourceDir', 'Resolve-ReShadeDllAcquisition')
    $functions = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $wanted -contains $args[0].Name }, $true))
    if ($functions.Count -ne $wanted.Count) { throw 'FIX405 could not find the shared acquisition functions.' }
    $functionFile = Join-Path $TestDrive 'fix405-functions.ps1'
    ($functions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    . $functionFile

    # Everything outside these two steps is an inert stub; each test mocks what it needs.
    function Write-Log { param([string]$msg) }
    function Read-TpmChoice { param([string]$Prompt, [string[]]$Choices, [string]$Default) throw 'Read-TpmChoice stub must be mocked.' }
    function Read-PathWithBrowse { param([string]$Prompt, [string]$Mode, [string]$FileFilter) throw 'Read-PathWithBrowse stub must be mocked.' }
    function Get-ReShadeLatestVersion { throw 'stub' }
    function Get-ReShadeSetupDownloadUrl { param([string]$Version) throw 'stub' }
    function Invoke-TpmDownload { param([string]$DownloadUrl, [string]$DestinationPath, [Int64]$ExpectedBytes = 0, [string]$Label = '', [string]$Version = '', [string]$ExpectedSha256 = '') throw 'stub' }
    function Test-ReShadeSetupTrustedSignature { param([string]$Path) throw 'stub' }
    function Expand-ReShadeSelfExtractingArchive { param([string]$SetupExePath, [string]$DestDir) throw 'stub' }
    function Get-DgVoodoo2LatestRelease { throw 'stub' }
    function Expand-DgVoodoo2Zip { param([string]$ZipPath, [string]$DestDir) throw 'stub' }
    function Test-TpmDgVoodoo2SourceFolder { param([string]$Path) return $false }

    $script:TpmOwnedLayout = [pscustomobject]@{ Assets = (Join-Path $TestDrive 'assets') }
    $script:f405Answers = New-Object System.Collections.Generic.Queue[string]
    $script:f405Screen = New-Object System.Collections.Generic.List[string]
}

Describe 'The ReShade step shared by the menu and the first-run offer (issue 399)' {
    BeforeEach {
        $script:f405Answers.Clear()
        $script:f405Screen.Clear()
        Mock Write-Log {}
        Mock Write-Host { [void]$script:f405Screen.Add([string]$Object) }
        Mock Read-TpmChoice { return $script:f405Answers.Dequeue() }
    }

    It 'Yes with no ReShade file offers to download it, and a failed download changes nothing' {
        $script:f405Answers.Enqueue('D')   # download
        $script:f405Answers.Enqueue('N')   # after the failure: cancel
        Mock Get-ReShadeLatestVersion { return '6.0.0' }
        Mock Get-ReShadeSetupDownloadUrl { return 'https://reshade.me/downloads/ReShade_Setup_6.0.0.exe' }
        Mock Invoke-TpmDownload { return $false }

        $result = Request-TpmReShadeSourceDll

        $result.State | Should -BeExactly 'Cancelled'
        $result.Path | Should -BeNullOrEmpty
        Should -Invoke Invoke-TpmDownload -Times 1 -Exactly
        # No ReShade file and no half-downloaded installer was left behind.
        @(Get-ChildItem -LiteralPath (Join-Path $TestDrive 'assets') -Recurse -File -ErrorAction SilentlyContinue).Count | Should -Be 0
        ($script:f405Screen -join "`n") | Should -Match 'did not finish'
        ($script:f405Screen -join "`n") | Should -Not -Match 'main menu'
    }

    It 'asks again after a failed download and uses a folder the user already has' {
        $folder = Join-Path $TestDrive 'my-reshade'
        [void][System.IO.Directory]::CreateDirectory($folder)
        [System.IO.File]::WriteAllText((Join-Path $folder 'ReShade64.dll'), 'fixture')
        $script:f405Answers.Enqueue('D')
        $script:f405Answers.Enqueue('B')   # after the failure: use a copy I have
        Mock Get-ReShadeLatestVersion { return $null }
        Mock Read-PathWithBrowse { return $folder }

        $result = Request-TpmReShadeSourceDll

        $result.State | Should -BeExactly 'Acquired'
        $result.Path | Should -BeExactly (Join-Path $folder 'ReShade64.dll')
    }

    It 'accepts the folder that holds ReShade64.dll, refuses a folder without it' {
        $good = Join-Path $TestDrive 'good-folder'
        [void][System.IO.Directory]::CreateDirectory($good)
        [System.IO.File]::WriteAllText((Join-Path $good 'ReShade64.dll'), 'fixture')
        $empty = Join-Path $TestDrive 'empty-folder'
        [void][System.IO.Directory]::CreateDirectory($empty)

        $accepted = Resolve-ReShadeDllAcquisition -Choice 'B' -InputPath ('"' + $good + '"')
        $accepted.State | Should -BeExactly 'Acquired'
        $accepted.Path | Should -BeExactly (Join-Path $good 'ReShade64.dll')
        $refused = Resolve-ReShadeDllAcquisition -Choice 'B' -InputPath $empty
        $refused.State | Should -BeExactly 'Invalid'
        $refused.Reason | Should -BeExactly 'FileMissing'
    }

    It 'the first-run ReShade offer runs this step instead of sending the user to the menu' {
        $start = $script:f405Source.IndexOf('# RESHADE SETUP  (optional, runs after crosshair setup)')
        $end = $script:f405Source.IndexOf('# DGVOODOO2 SETUP  (optional, runs after ReShade setup)')
        $start | Should -BeGreaterThan 0
        $end | Should -BeGreaterThan $start
        $block = $script:f405Source.Substring($start, $end - $start)
        $block | Should -Match 'Request-TpmReShadeSourceDll'
        $block | Should -Not -Match 'not found yet'
        $block | Should -Match 'Nothing was changed'
    }
}

Describe 'The dgVoodoo2 step shared by the menu and the first-run offer (issue 399)' {
    BeforeEach {
        $script:f405Answers.Clear()
        $script:f405Screen.Clear()
        Mock Write-Log {}
        Mock Write-Host { [void]$script:f405Screen.Add([string]$Object) }
        Mock Read-TpmChoice { return $script:f405Answers.Dequeue() }
    }

    It 'a failed download then Cancel changes nothing and says so' {
        $script:f405Answers.Enqueue('D')
        $script:f405Answers.Enqueue('N')
        Mock Get-DgVoodoo2LatestRelease { return $null }

        $result = Request-TpmDgVoodoo2SourceDir

        $result.State | Should -BeExactly 'Cancelled'
        ($script:f405Screen -join "`n") | Should -Match 'could not reach'
        @(Get-ChildItem -LiteralPath (Join-Path $TestDrive 'assets') -Recurse -File -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'a folder the user types is used when it holds the dgVoodoo2 files' {
        $folder = Join-Path $TestDrive 'my-dgvoodoo'
        $script:f405Answers.Enqueue('B')
        Mock Read-PathWithBrowse { return $folder }
        Mock Test-TpmDgVoodoo2SourceFolder { return ($Path -eq $folder) }

        $result = Request-TpmDgVoodoo2SourceDir

        $result.State | Should -BeExactly 'Acquired'
        $result.Path | Should -BeExactly $folder
    }

    It 'an empty answer at the folder prompt cancels without changing anything' {
        $script:f405Answers.Enqueue('B')
        Mock Read-PathWithBrowse { return '' }

        (Request-TpmDgVoodoo2SourceDir).State | Should -BeExactly 'CancelledAtFolder'
    }

    It 'the first-run dgVoodoo2 offer runs this step instead of sending the user to the menu' {
        $start = $script:f405Source.IndexOf('# DGVOODOO2 SETUP  (optional, runs after ReShade setup)')
        $end = $script:f405Source.IndexOf('# CPS3 SUPPLEMENTARY FILES', $start)
        $start | Should -BeGreaterThan 0
        $end | Should -BeGreaterThan $start
        $block = $script:f405Source.Substring($start, $end - $start)
        $block | Should -Match 'Request-TpmDgVoodoo2SourceDir'
        $block | Should -Not -Match 'not found yet'
        $block | Should -Match 'Nothing was changed'
    }
}
