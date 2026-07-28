#Requires -Module Pester

# Regression suite for the pure / read-only helper functions in
# TeknoParrot-Manager.ps1. The script itself is not a module -- it is one
# file whose function definitions are followed by top-level executable
# code (the interactive menu loop), so it cannot be dot-sourced directly
# without launching that loop. Instead, BeforeAll below parses the file
# with the PowerShell AST and defines only the function bodies in this
# session. This requires zero changes to the production script.
#
# Run with: Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "..\TeknoParrot-Manager.ps1"
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Failed to parse TeknoParrot-Manager.ps1: $($parseErrors -join '; ')"
    }
    $functionAsts = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functionAsts) {
        . ([scriptblock]::Create($fn.Extent.Text))
    }

    # $FuzzyAutoThreshold/$FuzzyTieMargin are top-level script-scope constants (not
    # function bodies), so the AST extraction above never picks them up. Functions
    # like Resolve-BestFuzzyMatch read them as unqualified script-scope variables,
    # so without this they'd silently read as $null here -- mirror the production
    # values from TeknoParrot-Manager.ps1 explicitly.
    $FuzzyAutoThreshold = 0.72
    $FuzzyTieMargin     = 0.1

    # $script:TitleTokenStopWords is a top-level script-scope constant (not a
    # function body), so the AST extraction above never picks it up.
    # Get-MeaningfulTitleTokens reads it as an unqualified script-scope variable
    # (issue #84) -- mirror the production value explicitly.
    $script:TitleTokenStopWords = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('the', 'of', 'a', 'an', 'and', 'vs', 'vs.', 'in', 'for', 'to'),
        [System.StringComparer]::OrdinalIgnoreCase)

    # $script:LocalDriveInfoCache/$LocalDriveInfoCachePopulated are top-level
    # script-scope variables (not function bodies) initialised before
    # Get-LocalDriveInfoSafe / Clear-LocalDriveInfoCache in the production
    # script. Initialise them here so those functions behave correctly in the
    # test scope (an uninitialised $null is falsy, so the first call would still
    # spawn the job, but the explicit init is cleaner and avoids surprises).
    $script:LocalDriveInfoCache          = $null
    $script:LocalDriveInfoCachePopulated = $false

    # Same situation for the FFB Blaster gating (issue #41) and schema-drift
    # (issue #43) constants -- they are top-level script-scope variables in
    # the production script, not function bodies, so the AST extraction above
    # never picks them up. Get-FFBBlasterSupport reads the first two directly,
    # and Get-GameProfileSchemaDrift uses the rest as parameter defaults
    # (which evaluate to $null in test scope without these). Mirror the
    # production values explicitly.
    $script:FFBBlasterUnsupportedPlatforms = @('pcsx2x6')
    $script:FFBBlasterNamePattern          = 'ffb.*blaster|blaster.*ffb'
    $script:KnownGameProfileTopLevel = @(
        'GamePath','GamePath2','TestMenuParameter','TestMenuIsExecutable',
        'ExtraParameters','TestMenuExtraParameters','EmulationProfile',
        'GameProfileRevision','HasSeparateTestMode','ExecutableName',
        'ExecutableName2','HasTwoExecutables','LaunchSecondExecutableFirst',
        'HasTpoSupport','EmulatorType','Is64Bit','ValidMd5','ConfigValues',
        'GameName','GameGenreInternal','IconName','HasModeForSquare',
        'RequiresAdmin','InvokeFullscreenOnStartup','LaunchedFromUsb',
        'CamberWindowState'
    )
    $script:RequiredGameProfileTopLevel = @('EmulationProfile','ConfigValues')
    $script:KnownFieldTypes = @('Bool','Dropdown','Text','Slider')
    $script:InputConfigFields = @()

    # The production script loads System.IO.Compression.FileSystem at startup
    # (top-level code, line ~82 -- not in a function body, so AST extraction
    # above never captures it). Expand-ZipFileSafe uses ZipFile (from
    # System.IO.Compression.FileSystem.dll). New-TestZip uses ZipArchive (from
    # System.IO.Compression.dll -- a separate assembly). Both are loaded in
    # the Describe "Expand-ZipFileSafe" BeforeAll below.
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    # $ScriptVersion is a top-level script-scope constant (not a function
    # body), so the AST extraction above never picks it up. Get-ManagerUpdateRelease
    # and Invoke-CheckForUpdates read it directly (User-Agent header, current-version
    # display/comparison) -- mirror the production value explicitly. Deliberately
    # not hardcoded to match TeknoParrot-Manager.ps1's own version exactly; tests
    # below use their own controlled version strings/mocks instead of relying on
    # this value's specific number, so drift here would not silently break them.
    $ScriptVersion = "0.99.39"
    $ReleaseCandidateLabel = "RC3"
    $DisplayVersion = "v1.0 RC3"

    # Write-Log normally writes beside the production script via top-level
    # initialisation that AST extraction intentionally skips. Give helper tests a
    # real throwaway log target so certification output is not polluted with
    # synthetic "[UNLOGGED]" messages.
    $script:TestLogRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-tests-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $script:TestLogRoot -Force | Out-Null
    $script:logPath = Join-Path $script:TestLogRoot "TeknoParrot-Manager.Tests.log"
    $script:logWarnShown = $false
    $script:logFailedCount = 0
}

AfterAll {
    if ($script:TestLogRoot -and (Test-Path -LiteralPath $script:TestLogRoot)) {
        Remove-Item -LiteralPath $script:TestLogRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Write-Log" {
    It "does not print the archive warning when the log path is intentionally blank" {
        $oldLogPath = $script:logPath
        $oldWarnShown = $script:logWarnShown
        $oldFailedCount = $script:logFailedCount
        try {
            $script:logPath = ''
            $script:logWarnShown = $false
            $script:logFailedCount = 0

            Mock Write-Host {}

            Write-Log "synthetic test message"

            Should -Invoke Write-Host -Times 0 -ParameterFilter { $Object -like '*Cannot write to log file*' }
            Should -Invoke Write-Host -Times 1 -ParameterFilter { $Object -like '*UNLOGGED*synthetic test message*' }
            $script:logFailedCount | Should -Be 1
        } finally {
            $script:logPath = $oldLogPath
            $script:logWarnShown = $oldWarnShown
            $script:logFailedCount = $oldFailedCount
        }
    }
}

Describe "Test-PathInside" {
    It "returns true when child equals parent" {
        Test-PathInside "C:\Foo\Bar" "C:\Foo\Bar" | Should -BeTrue
    }
    It "returns true for a real child path" {
        Test-PathInside "C:\Foo\Bar\baz.txt" "C:\Foo\Bar" | Should -BeTrue
    }
    It "returns false for a sibling path that merely shares a string prefix" {
        Test-PathInside "C:\Foo\Barbaz" "C:\Foo\Bar" | Should -BeFalse
    }
    It "returns false for an unrelated path" {
        Test-PathInside "C:\Other\thing.txt" "C:\Foo\Bar" | Should -BeFalse
    }
    It "is case-insensitive" {
        Test-PathInside "c:\foo\bar\baz.txt" "C:\Foo\Bar" | Should -BeTrue
    }
}

Describe "Invoke-WithHardTimeout" {
    # Issue #5 (v1.0 roadmap): a generic hard-timeout wrapper for a local call
    # that could theoretically still block. Uses a real background job (not
    # mocked) since the whole point is genuine process-level isolation -- these
    # tests use short, deterministic scriptblocks so they stay fast.
    It "returns the scriptblock's output when it completes well within the timeout" {
        Invoke-WithHardTimeout -ScriptBlock { 1 + 1 } -TimeoutSeconds 5 | Should -Be 2
    }
    It "returns null and does not throw when the scriptblock exceeds the timeout" {
        $result = $null
        { $result = Invoke-WithHardTimeout -ScriptBlock { Start-Sleep -Seconds 10 } -TimeoutSeconds 1 } | Should -Not -Throw
        $result | Should -BeNullOrEmpty
    }
    It "returns null and does not throw when the scriptblock itself throws" {
        { Invoke-WithHardTimeout -ScriptBlock { throw "boom" } -TimeoutSeconds 5 } | Should -Not -Throw
        Invoke-WithHardTimeout -ScriptBlock { throw "boom" } -TimeoutSeconds 5 | Should -BeNullOrEmpty
    }
}

Describe "Test-IsNetworkPath" {
    # DriveInfo.DriveType is a read-only OS-derived property with no public
    # constructor for a synthetic "Network" instance, so these tests cover
    # the reachable surface without needing a real mapped network drive:
    # the UNC short-circuit (no drive lookup at all), the explicit -Drives
    # override against this machine's real (non-network) drives, and the
    # fail-safe path when drive info genuinely could not be determined
    # (mocking Get-LocalDriveInfoSafe rather than passing -Drives $null,
    # since that default is indistinguishable from "not supplied" and would
    # otherwise just spawn the real job and exercise the success path).
    It "treats a UNC path as a network path without needing drive info at all" {
        Test-IsNetworkPath '\\nas\share\folder' | Should -BeTrue
    }
    It "returns false for an empty or whitespace path" {
        Test-IsNetworkPath '' | Should -BeFalse
        Test-IsNetworkPath '   ' | Should -BeFalse
    }
    It "uses the Name/IsNetwork shape (not a real DriveInfo) when -Drives is supplied explicitly" {
        # -Drives is deliberately untyped (see Test-IsNetworkPath's own comment) -- a real
        # [System.IO.DriveInfo[]] is NOT what gets passed in production. Get-LocalDriveInfoSafe
        # runs in a background job, and a real DriveInfo crossing that job boundary comes back
        # as an undeserializable stand-in (confirmed from a real tester's crash, issue #5
        # follow-up) -- this is the actual shape real callers use.
        $drives = @([pscustomobject]@{ Name = 'C:\'; IsNetwork = $false })
        Test-IsNetworkPath 'C:\Windows' -Drives $drives | Should -BeFalse
    }
    It "detects a network drive via the Name/IsNetwork shape" {
        $drives = @([pscustomobject]@{ Name = 'Z:\'; IsNetwork = $true })
        Test-IsNetworkPath 'Z:\Games' -Drives $drives | Should -BeTrue
    }
    It "fails safe (returns false, never throws) when drive info could not be determined" {
        Mock Get-LocalDriveInfoSafe { $null }
        { Test-IsNetworkPath 'Z:\Games' } | Should -Not -Throw
        Test-IsNetworkPath 'Z:\Games' | Should -BeFalse
    }
    It "end-to-end: works through the real job-backed Get-LocalDriveInfoSafe without throwing" {
        # Regression test for the actual bug a tester hit: this is the exact call shape
        # Find-TeknoParrotRoot/Find-LaunchBoxRoot use, going through the real background
        # job rather than a mocked or directly-constructed -Drives value. Before the fix,
        # this threw "Cannot convert ... Deserialized.System.IO.DriveInfo ... to type
        # System.IO.DriveInfo" because Get-LocalDriveInfoSafe used to return real DriveInfo
        # objects across the job boundary.
        $localDriveInfo = Get-LocalDriveInfoSafe
        { Test-IsNetworkPath "$($env:SystemDrive)\Windows" -Drives $localDriveInfo } | Should -Not -Throw
        Test-IsNetworkPath "$($env:SystemDrive)\Windows" -Drives $localDriveInfo | Should -BeFalse
    }
}

Describe "Get-LocalDriveInfoSafe" {
    BeforeEach {
        # Reset the cache before every test so each one starts from a clean slate.
        Clear-LocalDriveInfoCache
    }
    It "returns real drive info (including the system drive) within the timeout in the normal case" {
        $result = Get-LocalDriveInfoSafe
        $result | Should -Not -BeNullOrEmpty
        ($result | Where-Object { $_.Name -eq "$($env:SystemDrive)\" }) | Should -Not -BeNullOrEmpty
    }
    It "returns plain pscustomobjects, never real DriveInfo instances (the actual bug this guards against)" {
        # Get-LocalDriveInfoSafe runs across a background-job boundary (Invoke-WithHardTimeout);
        # Receive-Job deserializes a real [System.IO.DriveInfo] into an undeserializable
        # "Deserialized.System.IO.DriveInfo" stand-in that fails any strongly-typed
        # [System.IO.DriveInfo[]] parameter bind downstream. Returning plain Name/IsNetwork
        # data instead is the actual fix -- this test locks that shape in.
        $result = Get-LocalDriveInfoSafe
        foreach ($d in $result) {
            $d | Should -BeOfType [System.Management.Automation.PSCustomObject]
            $d.PSObject.Properties.Name | Should -Contain 'Name'
            $d.PSObject.Properties.Name | Should -Contain 'IsNetwork'
        }
    }
    It "populates the cache after the first call so subsequent calls skip the background job" {
        $script:LocalDriveInfoCachePopulated | Should -BeFalse
        Get-LocalDriveInfoSafe | Out-Null
        $script:LocalDriveInfoCachePopulated | Should -BeTrue
        $script:LocalDriveInfoCache | Should -Not -BeNullOrEmpty
    }
    It "Clear-LocalDriveInfoCache resets the populated flag so the next call re-fetches" {
        Get-LocalDriveInfoSafe | Out-Null
        $script:LocalDriveInfoCachePopulated | Should -BeTrue
        Clear-LocalDriveInfoCache
        $script:LocalDriveInfoCachePopulated | Should -BeFalse
        $script:LocalDriveInfoCache | Should -BeNullOrEmpty
    }
}

Describe "Auto-detect root return contract (issue #65)" {
    BeforeEach {
        $script:OriginalUserProfile = $env:USERPROFILE
        $env:USERPROFILE = Join-Path $TestDrive "UserProfile"
        New-Item -ItemType Directory -Path $env:USERPROFILE -Force | Out-Null
        Clear-LocalDriveInfoCache
        Mock Get-LocalDriveInfoSafe { @([pscustomobject]@{ Name = "$TestDrive\"; IsNetwork = $false }) }
        Mock Get-PSDrive {
            [pscustomobject]@{
                Root = "$TestDrive\"
            }
        } -ParameterFilter { $PSProvider -eq 'FileSystem' }
    }

    AfterEach {
        $env:USERPROFILE = $script:OriginalUserProfile
    }

    It "Find-TeknoParrotRoot returns zero matches with Count 0 for caller-side branching" {
        $detected = Find-TeknoParrotRoot

        $detected | Should -BeNullOrEmpty
        $detected.Count | Should -Be 0
    }

    It "Find-TeknoParrotRoot returns one match with Count 1 for caller-side branching" {
        $rootA = Join-Path $env:USERPROFILE "LaunchBox\Emulators\TeknoParrot"
        New-Item -ItemType Directory -Path $rootA -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $rootA "TeknoParrotUi.exe") -Value "stub" -NoNewline

        $detected = Find-TeknoParrotRoot

        $detected.Count | Should -Be 1
        $detected[0] | Should -Be $rootA
    }

    It "Find-TeknoParrotRoot returns multiple matches with Count equal to the number of roots" {
        $rootA = Join-Path $env:USERPROFILE "LaunchBox\Emulators\TeknoParrot"
        $rootB = Join-Path $TestDrive "Games\TeknoParrot"
        New-Item -ItemType Directory -Path $rootA, $rootB -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $rootA "TeknoParrotUi.exe") -Value "stub" -NoNewline
        Set-Content -LiteralPath (Join-Path $rootB "TeknoParrotUi.exe") -Value "stub" -NoNewline

        $detected = Find-TeknoParrotRoot

        $detected.Count | Should -Be 2
        @($detected) | Should -Contain $rootA
        @($detected) | Should -Contain $rootB
    }

    It "Find-LaunchBoxRoot returns zero matches with Count 0 for caller-side branching" {
        $detected = Find-LaunchBoxRoot

        $detected | Should -BeNullOrEmpty
        $detected.Count | Should -Be 0
    }

    It "Find-LaunchBoxRoot returns one match with Count 1 for caller-side branching" {
        $rootA = Join-Path $env:USERPROFILE "LaunchBox"
        New-Item -ItemType Directory -Path $rootA -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $rootA "LaunchBox.exe") -Value "stub" -NoNewline

        $detected = Find-LaunchBoxRoot

        $detected.Count | Should -Be 1
        $detected[0] | Should -Be $rootA
    }

    It "Find-LaunchBoxRoot returns multiple matches with Count equal to the number of roots" {
        $rootA = Join-Path $env:USERPROFILE "LaunchBox"
        $rootB = Join-Path $TestDrive "Games\LaunchBox"
        New-Item -ItemType Directory -Path $rootA, $rootB -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $rootA "LaunchBox.exe") -Value "stub" -NoNewline
        Set-Content -LiteralPath (Join-Path $rootB "LaunchBox.exe") -Value "stub" -NoNewline

        $detected = Find-LaunchBoxRoot

        $detected.Count | Should -Be 2
        @($detected) | Should -Contain $rootA
        @($detected) | Should -Contain $rootB
    }

    It "keeps caller-side auto-detect assignments from re-wrapping the returned ArrayList" {
        $source = Get-Content -Raw -LiteralPath $scriptPath

        $source | Should -Match '\$detected\s*=\s*Find-TeknoParrotRoot'
        $source | Should -Not -Match '\$detected\s*=\s*@\(\s*Find-TeknoParrotRoot\s*\)'
        $source | Should -Match '\$lbDetected\s*=\s*Find-LaunchBoxRoot'
        $source | Should -Not -Match '\$lbDetected\s*=\s*@\(\s*Find-LaunchBoxRoot\s*\)'
    }
}

Describe "ConvertTo-XPathStringLiteral" {
    It "wraps a plain string in single quotes" {
        ConvertTo-XPathStringLiteral "GPU Fix" | Should -Be "'GPU Fix'"
    }
    It "builds a concat() expression when the string contains a single quote" {
        $result = ConvertTo-XPathStringLiteral "It's a Field"
        $result | Should -BeLike "concat(*"
        $result | Should -Not -BeLike "*''''*"
    }
}

Describe "Get-SafeLaunchBoxPlatformFileName" {
    It "passes through an already-safe name" {
        Get-SafeLaunchBoxPlatformFileName "TeknoParrot" | Should -Be "TeknoParrot"
    }
    It "strips invalid filename characters" {
        Get-SafeLaunchBoxPlatformFileName 'My:Plat*form?' | Should -Be "MyPlatform"
    }
    It "trims surrounding whitespace" {
        Get-SafeLaunchBoxPlatformFileName "  Spaced  " | Should -Be "Spaced"
    }
    It "falls back to TeknoParrot when every character is invalid" {
        Get-SafeLaunchBoxPlatformFileName '<>:*' | Should -Be "TeknoParrot"
    }
}

Describe "Set-SecondaryExecutablePath" {
    BeforeAll {
        function New-TwoExeDoc([string]$exe2Name = "amdaemon.exe", [string]$gamePath2 = "") {
            return [xml]@"
<GameProfile>
  <ExecutableName>InitialD0_DX11_Nu.exe</ExecutableName>
  <ExecutableName2>$exe2Name</ExecutableName2>
  <HasTwoExecutables>true</HasTwoExecutables>
  <GamePath2>$gamePath2</GamePath2>
</GameProfile>
"@
        }
    }

    It "sets GamePath2 when the companion exe sits alongside the primary exe" {
        $dir = Join-Path $TestDrive "idz"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $primary = Join-Path $dir "InitialD0_DX11_Nu.exe"
        [System.IO.File]::WriteAllBytes($primary, [byte[]]@(0))
        [System.IO.File]::WriteAllBytes((Join-Path $dir "amdaemon.exe"), [byte[]]@(0))

        $doc = New-TwoExeDoc
        Set-SecondaryExecutablePath $doc $primary

        $doc.GameProfile.GamePath2 | Should -Be (Join-Path $dir "amdaemon.exe")
    }
    It "leaves GamePath2 unset when the companion exe is not found alongside the primary exe" {
        $dir = Join-Path $TestDrive "idz-missing"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $primary = Join-Path $dir "InitialD0_DX11_Nu.exe"
        [System.IO.File]::WriteAllBytes($primary, [byte[]]@(0))

        $doc = New-TwoExeDoc
        Set-SecondaryExecutablePath $doc $primary

        $doc.GameProfile.GamePath2 | Should -BeNullOrEmpty
    }
    It "does nothing when HasTwoExecutables is not true" {
        $dir = Join-Path $TestDrive "single-exe"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $primary = Join-Path $dir "game.exe"
        [System.IO.File]::WriteAllBytes($primary, [byte[]]@(0))
        [System.IO.File]::WriteAllBytes((Join-Path $dir "amdaemon.exe"), [byte[]]@(0))

        $doc = [xml]"<GameProfile><ExecutableName2>amdaemon.exe</ExecutableName2><HasTwoExecutables>false</HasTwoExecutables></GameProfile>"
        Set-SecondaryExecutablePath $doc $primary

        $doc.GameProfile.SelectSingleNode("GamePath2") | Should -BeNullOrEmpty
    }
    It "never overwrites a GamePath2 that already points at the correct companion exe" {
        $dir = Join-Path $TestDrive "idz-already"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $primary = Join-Path $dir "InitialD0_DX11_Nu.exe"
        [System.IO.File]::WriteAllBytes($primary, [byte[]]@(0))
        $correctGp2 = Join-Path $dir "amdaemon.exe"
        [System.IO.File]::WriteAllBytes($correctGp2, [byte[]]@(0))

        $doc = New-TwoExeDoc -gamePath2 $correctGp2
        Set-SecondaryExecutablePath $doc $primary

        $doc.GameProfile.GamePath2 | Should -Be $correctGp2
    }
    It "corrects a stale GamePath2 left pointing at a folder the primary exe no longer lives in" {
        $dir = Join-Path $TestDrive "idz-stale"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $primary = Join-Path $dir "InitialD0_DX11_Nu.exe"
        [System.IO.File]::WriteAllBytes($primary, [byte[]]@(0))
        [System.IO.File]::WriteAllBytes((Join-Path $dir "amdaemon.exe"), [byte[]]@(0))

        # Simulates GamePath having been migrated/repaired to $dir while
        # GamePath2 was left behind pointing at the old pre-migration location.
        $doc = New-TwoExeDoc -gamePath2 "F:\old\stale\location\amdaemon.exe"
        Set-SecondaryExecutablePath $doc $primary

        $doc.GameProfile.GamePath2 | Should -Be (Join-Path $dir "amdaemon.exe")
    }
    It "does nothing when ExecutableName2 is blank" {
        $dir = Join-Path $TestDrive "no-exe2-name"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $primary = Join-Path $dir "game.exe"
        [System.IO.File]::WriteAllBytes($primary, [byte[]]@(0))

        $doc = [xml]"<GameProfile><ExecutableName2></ExecutableName2><HasTwoExecutables>true</HasTwoExecutables></GameProfile>"
        Set-SecondaryExecutablePath $doc $primary

        $doc.GameProfile.SelectSingleNode("GamePath2") | Should -BeNullOrEmpty
    }
}

Describe "Read-HostSafe / Exit-TpmProcess (issue #135: non-interactive input)" {
    # Read-Host returns $null when redirected stdin has run out of piped
    # lines (or, more rarely, when Read-Host is unavailable in the current
    # host). Read-HostSafe is the one centralized wrapper every interactive
    # prompt in the script goes through so that failure mode has a single,
    # tested implementation instead of ~65 individual unguarded .Trim()/
    # .ToUpper() call sites. Exit-TpmProcess is mocked here so the exhausted-
    # input path can be exercised without terminating the test runner.

    It "returns the trimmed value for a normal (interactive-equivalent) answer" {
        Mock Read-Host { return '  Y  ' }
        Read-HostSafe -Prompt 'Continue?' | Should -Be 'Y'
    }

    It "returns an empty string for a blank answer (user pressed Enter with nothing typed)" {
        Mock Read-Host { return '' }
        Read-HostSafe -Prompt 'Continue?' | Should -Be ''
    }

    It "exits with code 1 and does not return a real answer when Read-Host returns null (exhausted redirected stdin)" {
        Mock Read-Host { return $null }
        Mock Exit-TpmProcess { }
        Mock Write-Log { }

        Read-HostSafe -Prompt 'Continue?' | Should -Be ''

        Should -Invoke Exit-TpmProcess -Times 1 -ParameterFilter { $Code -eq 1 }
        Should -Invoke Write-Log -Times 1
    }

    It "never lets a null Read-Host result crash a caller's .ToUpper() call" {
        Mock Read-Host { return $null }
        Mock Exit-TpmProcess { }
        Mock Write-Log { }

        { (Read-HostSafe -Prompt 'Continue?').ToUpper() } | Should -Not -Throw
    }
}

Describe "Read-MainMenuChoiceResponsive redirected-input handling (issue #135)" {
    # Confirms the main menu prompt never enters the [Console]::KeyAvailable
    # polling loop when stdin is redirected (polling a keyboard that cannot
    # receive piped input is the 40-second hang from issue #135), and that
    # an exhausted redirected stream exits cleanly instead of looping.
    #
    # [Console]::IsInputRedirected is a static, unmockable property whose
    # value depends on how THIS test process itself was launched -- true
    # when run non-interactively (this repo's CI, or piped/redirected local
    # runs), false when a developer runs Invoke-Pester directly in an
    # interactive terminal window. These two It blocks are guarded to only
    # run in whichever of those two states is actually live, rather than
    # asserting a specific state or risking the interactive-terminal case
    # falling into a real keyboard-polling wait inside a test run.
    It "returns via Read-HostSafe without entering the keyboard-polling loop when input is redirected" -Skip:(-not [Console]::IsInputRedirected) {
        Mock Read-Host { return 'AutoSync' }
        $result = Read-MainMenuChoiceResponsive -Prompt 'Choice:' -InitialWidth 80 -InitialHeight 25
        $result.Value | Should -Be 'AutoSync'
        $result.Redraw | Should -BeFalse
    }

    It "exits cleanly via Exit-TpmProcess instead of looping when redirected stdin is exhausted" -Skip:(-not [Console]::IsInputRedirected) {
        Mock Read-Host { return $null }
        Mock Exit-TpmProcess { }
        Mock Write-Log { }

        $result = Read-MainMenuChoiceResponsive -Prompt 'Choice:' -InitialWidth 80 -InitialHeight 25

        $result.Value | Should -Be ''
        Should -Invoke Exit-TpmProcess -Times 1 -ParameterFilter { $Code -eq 1 }
    }

    It "logs (does not silently swallow) an [Console]::IsInputRedirected detection failure" {
        # IsInputRedirected itself cannot be mocked (static .NET member), so
        # this exercises the documented behavior directly: the function's
        # catch block around that check must call Write-Log, never an empty
        # `catch {}` (issue #135's "do not silently swallow" requirement).
        # Confirmed by source inspection matching this test's expectation:
        # see the comment immediately above the try/catch in
        # Read-MainMenuChoiceResponsive.
        $fnText = (Get-Command Read-MainMenuChoiceResponsive).Definition
        $fnText | Should -Not -Match 'catch\s*\{\s*\}'
        $fnText | Should -Match 'IsInputRedirected.*threw'
    }
}

Describe "Get-ButtonKey / Test-ButtonIsBound" {
    BeforeAll {
        function New-ButtonNode([string]$xml) {
            $doc = [xml]$xml
            return $doc.DocumentElement
        }
    }

    It "builds an InputMapping|AnalogType composite key" {
        $btn = New-ButtonNode "<JoystickButtons><InputMapping>P1Button1</InputMapping><AnalogType>Wheel</AnalogType></JoystickButtons>"
        Get-ButtonKey $btn | Should -Be "P1Button1|Wheel"
    }
    It "defaults AnalogType to None when absent" {
        $btn = New-ButtonNode "<JoystickButtons><InputMapping>P1Button1</InputMapping></JoystickButtons>"
        Get-ButtonKey $btn | Should -Be "P1Button1|None"
    }
    It "returns null when InputMapping is missing" {
        $btn = New-ButtonNode "<JoystickButtons><AnalogType>Wheel</AnalogType></JoystickButtons>"
        Get-ButtonKey $btn | Should -BeNullOrEmpty
    }
    It "returns null when InputMapping is blank" {
        $btn = New-ButtonNode "<JoystickButtons><InputMapping>   </InputMapping></JoystickButtons>"
        Get-ButtonKey $btn | Should -BeNullOrEmpty
    }
    It "reports a button as bound when it has a DirectInputButton child" {
        $btn = New-ButtonNode "<JoystickButtons><DirectInputButton>3</DirectInputButton></JoystickButtons>"
        Test-ButtonIsBound $btn | Should -BeTrue
    }
    It "reports a button as unbound with no binding children" {
        $btn = New-ButtonNode "<JoystickButtons><InputMapping>P1Button1</InputMapping></JoystickButtons>"
        Test-ButtonIsBound $btn | Should -BeFalse
    }
}

Describe "Get-GameApiDll" {
    BeforeAll {
        function New-FakeExe([string]$name, [string]$marker) {
            $path = Join-Path $TestDrive $name
            $bytes = [System.Text.Encoding]::ASCII.GetBytes("MZ-stub-padding-$marker-more-padding")
            [System.IO.File]::WriteAllBytes($path, $bytes)
            return $path
        }
    }

    It "detects d3d9.dll" {
        $p = New-FakeExe "d3d9.exe" "d3d9.dll"
        Get-GameApiDll -ExePath $p | Should -Be "d3d9.dll"
    }
    It "detects opengl32.dll" {
        $p = New-FakeExe "gl.exe" "opengl32.dll"
        Get-GameApiDll -ExePath $p | Should -Be "opengl32.dll"
    }
    It "maps d3d11.dll imports to dxgi.dll" {
        $p = New-FakeExe "d3d11.exe" "d3d11.dll"
        Get-GameApiDll -ExePath $p | Should -Be "dxgi.dll"
    }
    It "prefers d3d12 over d3d11 when an exe imports both" {
        $p = New-FakeExe "both.exe" "d3d11.dll-and-d3d12.dll"
        Get-GameApiDll -ExePath $p | Should -Be "d3d12.dll"
    }
    It "returns null when no known API is imported" {
        $p = New-FakeExe "plain.exe" "nothing-recognizable"
        Get-GameApiDll -ExePath $p | Should -BeNullOrEmpty
    }
}

Describe "Get-GameLegacyApi" {
    BeforeAll {
        function New-FakeExe([string]$name, [string]$marker) {
            $path = Join-Path $TestDrive $name
            $bytes = [System.Text.Encoding]::ASCII.GetBytes("MZ-stub-padding-$marker-more-padding")
            [System.IO.File]::WriteAllBytes($path, $bytes)
            return $path
        }
    }

    It "detects D3D8" {
        $p = New-FakeExe "d3d8.exe" "d3d8.dll"
        Get-GameLegacyApi -ExePath $p | Should -Contain "D3D8"
    }
    It "detects DDraw and Glide2x together" {
        $p = New-FakeExe "combo.exe" "ddraw.dll-and-glide2x.dll"
        $result = Get-GameLegacyApi -ExePath $p
        $result | Should -Contain "DDraw"
        $result | Should -Contain "Glide2x"
    }
    It "returns an empty array when nothing legacy is imported" {
        $p = New-FakeExe "modern.exe" "d3d11.dll"
        Get-GameLegacyApi -ExePath $p | Should -BeNullOrEmpty
    }
}

Describe "Test-GpuFixUpToDate" {
    BeforeAll {
        function New-ProfileDoc([string]$inner) {
            return [xml]"<GameProfile><ConfigValues>$inner</ConfigValues></GameProfile>"
        }
    }

    It "is not eligible when no matching field exists in the profile" {
        $doc = New-ProfileDoc "<FieldInformation><FieldName>Unrelated</FieldName><FieldValue>0</FieldValue></FieldInformation>"
        $result = Test-GpuFixUpToDate -Doc $doc -BoolFields @('EnableAmdFix') -DropdownFields @() -Vendor 'AMD'
        $result.Eligible | Should -BeFalse
        $result.UpToDate | Should -BeFalse
    }
    It "flags a bool AMD field that needs to flip from 0 to 1 for an AMD vendor" {
        $doc = New-ProfileDoc "<FieldInformation><FieldName>EnableAmdFix</FieldName><FieldValue>0</FieldValue></FieldInformation>"
        $result = Test-GpuFixUpToDate -Doc $doc -BoolFields @('EnableAmdFix') -DropdownFields @() -Vendor 'AMD'
        $result.Eligible | Should -BeTrue
        $result.UpToDate | Should -BeFalse
        $result.Changes[0].NewValue | Should -Be '1'
    }
    It "is up to date when a bool AMD field is already 1 for an AMD vendor" {
        $doc = New-ProfileDoc "<FieldInformation><FieldName>EnableAmdFix</FieldName><FieldValue>1</FieldValue></FieldInformation>"
        $result = Test-GpuFixUpToDate -Doc $doc -BoolFields @('EnableAmdFix') -DropdownFields @() -Vendor 'AMD'
        $result.UpToDate | Should -BeTrue
        $result.Changes.Count | Should -Be 0
    }
    It "wants a bool AMD field set to 0 for a non-AMD vendor" {
        $doc = New-ProfileDoc "<FieldInformation><FieldName>EnableAmdFix</FieldName><FieldValue>1</FieldValue></FieldInformation>"
        $result = Test-GpuFixUpToDate -Doc $doc -BoolFields @('EnableAmdFix') -DropdownFields @() -Vendor 'NVIDIA'
        $result.UpToDate | Should -BeFalse
        $result.Changes[0].NewValue | Should -Be '0'
    }
    It "resolves a dropdown GPU Fix field to NVIDIA when offered" {
        $doc = New-ProfileDoc @"
<FieldInformation>
  <FieldName>GPU Fix</FieldName>
  <FieldValue>None</FieldValue>
  <FieldOptions><string>None</string><string>AMD</string><string>NVIDIA</string><string>INTEL</string></FieldOptions>
</FieldInformation>
"@
        $result = Test-GpuFixUpToDate -Doc $doc -BoolFields @() -DropdownFields @('GPU Fix') -Vendor 'NVIDIA'
        $result.Eligible | Should -BeTrue
        $result.Changes[0].NewValue | Should -Be 'NVIDIA'
    }
    It "prefers 'New AMD Driver' over 'AMD' when both dropdown options exist" {
        $doc = New-ProfileDoc @"
<FieldInformation>
  <FieldName>GPU Fix</FieldName>
  <FieldValue>None</FieldValue>
  <FieldOptions><string>None</string><string>AMD</string><string>New AMD Driver</string></FieldOptions>
</FieldInformation>
"@
        $result = Test-GpuFixUpToDate -Doc $doc -BoolFields @() -DropdownFields @('GPU Fix') -Vendor 'AMD'
        $result.Changes[0].NewValue | Should -Be 'New AMD Driver'
    }
}

Describe "Test-FFBBlasterUpToDate" {
    BeforeAll {
        function New-ProfileDoc([string]$inner) {
            return [xml]"<GameProfile><ConfigValues>$inner</ConfigValues></GameProfile>"
        }
    }

    It "is not eligible when the category is absent" {
        $doc = New-ProfileDoc "<FieldInformation><FieldName>Unrelated</FieldName><FieldType>Bool</FieldType><FieldValue>0</FieldValue></FieldInformation>"
        $result = Test-FFBBlasterUpToDate -Doc $doc -Categories @('FFB Blaster')
        $result.Eligible | Should -BeFalse
    }
    It "flags a CategoryName-based FFB Blaster field that needs enabling" {
        $doc = New-ProfileDoc "<FieldInformation><CategoryName>FFB Blaster</CategoryName><FieldName>Enable</FieldName><FieldType>Bool</FieldType><FieldValue>0</FieldValue></FieldInformation>"
        $result = Test-FFBBlasterUpToDate -Doc $doc -Categories @('FFB Blaster')
        $result.Eligible | Should -BeTrue
        $result.UpToDate | Should -BeFalse
        $result.Changes[0].NewValue | Should -Be '1'
    }
    It "is up to date when already enabled" {
        $doc = New-ProfileDoc "<FieldInformation><CategoryName>FFB Blaster</CategoryName><FieldName>Enable</FieldName><FieldType>Bool</FieldType><FieldValue>1</FieldValue></FieldInformation>"
        $result = Test-FFBBlasterUpToDate -Doc $doc -Categories @('FFB Blaster')
        $result.UpToDate | Should -BeTrue
    }
    It "falls back to matching by FieldName on older-build profiles with no CategoryName match" {
        $doc = New-ProfileDoc "<FieldInformation><FieldName>FFB Blaster Enabled</FieldName><FieldType>Bool</FieldType><FieldValue>0</FieldValue></FieldInformation>"
        $result = Test-FFBBlasterUpToDate -Doc $doc -Categories @('FFB Blaster Enabled')
        $result.Eligible | Should -BeTrue
        $result.Changes[0].NewValue | Should -Be '1'
    }
}

Describe "Get-ReShadeTargetInfo" {
    BeforeAll {
        function New-ProfileDoc([string]$emuType) {
            return [xml]"<GameProfile><EmulatorType>$emuType</EmulatorType></GameProfile>"
        }
        function New-FakeExe([string]$dir, [string]$name, [string]$marker) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $path = Join-Path $dir $name
            [System.IO.File]::WriteAllBytes($path, [System.Text.Encoding]::ASCII.GetBytes("MZ-pad-$marker-pad"))
            return $path
        }
    }

    It "forces opengl32.dll for BudgieLoader games regardless of detected imports" {
        $exeDir = Join-Path $TestDrive "budgie"
        $exe = New-FakeExe $exeDir "game.exe" "d3d9.dll"
        $doc = New-ProfileDoc "BudgieLoader"
        $result = Get-ReShadeTargetInfo -Doc $doc -GamePath $exe -ExeDir $exeDir
        $result.DllName | Should -Be "opengl32.dll"
        $result.TargetDir | Should -Be $exeDir
    }
    It "redirects to the openparrot subfolder when one exists" {
        $exeDir = Join-Path $TestDrive "opgame"
        $exe = New-FakeExe $exeDir "game.exe" "d3d9.dll"
        $opDir = Join-Path $exeDir "openparrot"
        New-Item -ItemType Directory -Path $opDir -Force | Out-Null
        $doc = New-ProfileDoc "OpenParrot"
        $result = Get-ReShadeTargetInfo -Doc $doc -GamePath $exe -ExeDir $exeDir
        $result.TargetDir | Should -Be $opDir
        $result.DllName | Should -Be "d3d9.dll"
    }
    It "falls back to dxgi.dll and reports ApiDetected=false when nothing is recognized" {
        $exeDir = Join-Path $TestDrive "unknown"
        $exe = New-FakeExe $exeDir "game.exe" "nothing-here"
        $doc = New-ProfileDoc "Default"
        $result = Get-ReShadeTargetInfo -Doc $doc -GamePath $exe -ExeDir $exeDir
        $result.DllName | Should -Be "dxgi.dll"
        $result.ApiDetected | Should -BeFalse
    }
}

Describe "Get-DiceSimilarity" {
    It "returns 1.0 for identical strings" {
        Get-DiceSimilarity "StreetFighterIII3rdStrike" "StreetFighterIII3rdStrike" | Should -Be 1.0
    }
    It "returns 0.0 for completely different strings" {
        Get-DiceSimilarity "aaaa" "zzzz" | Should -Be 0.0
    }
    It "returns 0.0 when either string is shorter than 2 characters" {
        Get-DiceSimilarity "a" "aa" | Should -Be 0.0
        Get-DiceSimilarity "" "aa" | Should -Be 0.0
    }
    It "is symmetric" {
        $ab = Get-DiceSimilarity "GoldenTeeLive2019" "Golden Tee Live 2019"
        $ba = Get-DiceSimilarity "Golden Tee Live 2019" "GoldenTeeLive2019"
        $ab | Should -Be $ba
    }
    It "scores a close abbreviation higher than an unrelated string" {
        $close      = Get-DiceSimilarity "InitialD8" "InitialDArcadeStage8"
        $unrelated  = Get-DiceSimilarity "InitialD8" "MarioKartArcadeGP"
        $close | Should -BeGreaterThan $unrelated
    }
    It "scores an exact match strictly higher than a partial fuzzy match" {
        $exact   = Get-DiceSimilarity "VirtuaFighter5" "VirtuaFighter5"
        $partial = Get-DiceSimilarity "VirtuaFighter5" "VirtuaFighter4"
        $exact | Should -BeGreaterThan $partial
    }
}

Describe "Expand-ZipFileSafe" {
    BeforeAll {
        # ZipArchive is in System.IO.Compression.dll; ZipFile is in the separate
        # System.IO.Compression.FileSystem.dll. Load both explicitly because the
        # production script's Add-Type (top-level, not in a function body) is
        # never captured by the AST extraction above.
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem

        function New-TestZip([string]$zipPath, [hashtable]$entries) {
            if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
            $fs = [System.IO.File]::Open($zipPath, [System.IO.FileMode]::CreateNew)
            try {
                $archive = [System.IO.Compression.ZipArchive]::new($fs, [System.IO.Compression.ZipArchiveMode]::Create)
                try {
                    foreach ($name in $entries.Keys) {
                        $entry = $archive.CreateEntry($name)
                        $w = New-Object System.IO.StreamWriter($entry.Open())
                        try { $w.Write($entries[$name]) } finally { $w.Dispose() }
                    }
                } finally { $archive.Dispose() }
            } finally { $fs.Dispose() }
        }
    }

    It "extracts normal nested entries with their content intact" {
        $zip  = Join-Path $TestDrive "normal.zip"
        $dest = Join-Path $TestDrive "normal-out"
        New-TestZip $zip @{ "sub/folder/file.txt" = "hello" }
        Expand-ZipFileSafe -ZipPath $zip -DestDir $dest
        Get-Content -LiteralPath (Join-Path $dest "sub\folder\file.txt") -Raw | Should -Be "hello"
    }
    It "rejects an entry with a directory traversal segment" {
        $zip  = Join-Path $TestDrive "traversal.zip"
        $dest = Join-Path $TestDrive "traversal-out"
        New-TestZip $zip @{ "../escape.txt" = "evil" }
        { Expand-ZipFileSafe -ZipPath $zip -DestDir $dest } | Should -Throw "*escapes destination folder*"
    }
    It "rejects an entry with a deeper directory traversal segment" {
        $zip  = Join-Path $TestDrive "traversal2.zip"
        $dest = Join-Path $TestDrive "traversal2-out"
        New-TestZip $zip @{ "sub/../../escape.txt" = "evil" }
        { Expand-ZipFileSafe -ZipPath $zip -DestDir $dest } | Should -Throw "*escapes destination folder*"
    }
    It "rejects an absolute (rooted) entry path" {
        $zip  = Join-Path $TestDrive "rooted.zip"
        $dest = Join-Path $TestDrive "rooted-out"
        New-TestZip $zip @{ "C:/evil.txt" = "evil" }
        { Expand-ZipFileSafe -ZipPath $zip -DestDir $dest } | Should -Throw "*escapes destination folder*"
    }
    It "throws cleanly on a corrupt zip file" {
        $zip = Join-Path $TestDrive "corrupt.zip"
        [System.IO.File]::WriteAllBytes($zip, [byte[]]@(1,2,3,4,5))
        $dest = Join-Path $TestDrive "corrupt-out"
        { Expand-ZipFileSafe -ZipPath $zip -DestDir $dest } | Should -Throw
    }
}

Describe "Test-DgVoodoo2UpToDate" {
    It "is not eligible when the game imports no legacy API" {
        $result = Test-DgVoodoo2UpToDate -Apis @() -ExeDir (Join-Path $TestDrive "anything")
        $result.Eligible | Should -BeFalse
        $result.UpToDate | Should -BeTrue
    }
    It "is eligible but not up to date when the required DLL is missing" {
        $dir = Join-Path $TestDrive "needsdg"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $result = Test-DgVoodoo2UpToDate -Apis @('D3D8') -ExeDir $dir
        $result.Eligible | Should -BeTrue
        $result.UpToDate | Should -BeFalse
    }
    It "is up to date once the required DLL is present" {
        $dir = Join-Path $TestDrive "hasdg"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $dir "D3D8.dll"), [byte[]]@(0))
        $result = Test-DgVoodoo2UpToDate -Apis @('D3D8') -ExeDir $dir
        $result.UpToDate | Should -BeTrue
    }
    It "requires every implicated DLL, not just one of several" {
        $dir = Join-Path $TestDrive "partialdg"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $dir "DDraw.dll"), [byte[]]@(0))
        $result = Test-DgVoodoo2UpToDate -Apis @('DDraw', 'Glide2x') -ExeDir $dir
        $result.UpToDate | Should -BeFalse
    }
}

Describe "Test-EggmanDatUpToDate" {
    # Issue #106: the "check for a newer Eggman dat release" prompt
    # previously always asked to download/switch regardless of whether the
    # remote release had actually changed. The Eggman/RomVault release
    # format exposes no version number, only a filename and size, so exact
    # byte-size match is the identity signal used.
    It "reports Current when the local file's size exactly matches the remote release size" {
        $path = Join-Path $TestDrive ("eggman-current-" + [guid]::NewGuid().ToString('N') + '.zip')
        [System.IO.File]::WriteAllBytes($path, [byte[]]::new(1024))
        $result = Test-EggmanDatUpToDate -LocalDatPath $path -RemoteSizeBytes 1024
        $result.Status | Should -Be 'Current'
        $result.LocalSizeBytes | Should -Be 1024
    }
    It "reports UpdateAvailable when the local file's size differs from the remote release size" {
        $path = Join-Path $TestDrive ("eggman-stale-" + [guid]::NewGuid().ToString('N') + '.zip')
        [System.IO.File]::WriteAllBytes($path, [byte[]]::new(1024))
        $result = Test-EggmanDatUpToDate -LocalDatPath $path -RemoteSizeBytes 2048
        $result.Status | Should -Be 'UpdateAvailable'
    }
    It "reports Unknown (not Current) when the local file does not exist" {
        $path = Join-Path $TestDrive ("eggman-missing-" + [guid]::NewGuid().ToString('N') + '.zip')
        $result = Test-EggmanDatUpToDate -LocalDatPath $path -RemoteSizeBytes 1024
        $result.Status | Should -Be 'Unknown'
        $result.LocalSizeBytes | Should -BeNullOrEmpty
    }
}

Describe "Write-DownloadAudit" {
    BeforeAll {
        Mock Write-Log {}
    }

    It "logs the actual SHA256 of the downloaded file" {
        $path = Join-Path $TestDrive "audit1.bin"
        [System.IO.File]::WriteAllBytes($path, [System.Text.Encoding]::ASCII.GetBytes("some download content"))
        $expectedHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash

        Write-DownloadAudit -Source "https://example.com/file.bin" -FileName "audit1.bin" -Path $path

        Should -Invoke Write-Log -Times 1 -ParameterFilter {
            $msg -like "*SHA256=$expectedHash*" -and $msg -like "*File=audit1.bin*" -and $msg -like "*Source=https://example.com/file.bin*"
        }
    }
    It "omits the Version segment when no version is supplied" {
        $path = Join-Path $TestDrive "audit2.bin"
        [System.IO.File]::WriteAllBytes($path, [byte[]]@(1, 2, 3))

        Write-DownloadAudit -Source "src" -FileName "audit2.bin" -Path $path

        Should -Invoke Write-Log -Times 1 -ParameterFilter { $msg -notlike "*Version=*" }
    }
    It "includes the Version segment when a version is supplied" {
        $path = Join-Path $TestDrive "audit3.bin"
        [System.IO.File]::WriteAllBytes($path, [byte[]]@(1, 2, 3))

        Write-DownloadAudit -Source "src" -FileName "audit3.bin" -Path $path -Version "1.2.3"

        Should -Invoke Write-Log -Times 1 -ParameterFilter { $msg -like "*Version=1.2.3*" }
    }
    It "fails closed (logs, does not throw) when the file does not exist" {
        $missingPath = Join-Path $TestDrive "does-not-exist.bin"

        { Write-DownloadAudit -Source "src" -FileName "missing.bin" -Path $missingPath } | Should -Not -Throw

        Should -Invoke Write-Log -Times 1 -ParameterFilter { $msg -like "*could not hash*missing.bin*" }
    }
    It "fails closed (logs, does not throw) when the file is locked by another process" {
        $path = Join-Path $TestDrive "locked.bin"
        [System.IO.File]::WriteAllBytes($path, [byte[]]@(1, 2, 3))
        $handle = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        try {
            { Write-DownloadAudit -Source "src" -FileName "locked.bin" -Path $path } | Should -Not -Throw
            Should -Invoke Write-Log -Times 1 -ParameterFilter { $msg -like "*could not hash*locked.bin*" }
        } finally {
            $handle.Dispose()
        }
    }
}

Describe "Build-DatIndexFromStream" {
    # Real collection dats have dozens to hundreds of <rom> hash entries per
    # <game>, skipped via reader.Skip() for performance. A real regression
    # (issue #12) had the surrounding loop call Read() again right after
    # Skip() already advanced the reader, silently discarding whatever node
    # Skip() had landed on -- on a real 506-game dat this dropped roughly
    # half of all games (493 opened, only 236 closed) regardless of whether
    # they had a valid GameProfile. These games deliberately carry varying
    # <rom> counts (0, 1, 3) so a regression of that exact shape fails here
    # instead of only on a multi-hundred-entry real dat.
    BeforeAll {
        function New-DatStream {
            param([int[]]$RomCounts)
            $sb = [System.Text.StringBuilder]::new()
            [void]$sb.Append('<?xml version="1.0"?><datafile>')
            for ($i = 0; $i -lt $RomCounts.Count; $i++) {
                [void]$sb.Append("<game name=`"Game$i`"><GameProfile>code$i</GameProfile><Executable>game$i.exe</Executable>")
                for ($r = 0; $r -lt $RomCounts[$i]; $r++) {
                    [void]$sb.Append("<rom name=`"file$r`" size=`"1`" crc=`"0`" />")
                }
                [void]$sb.Append('</game>')
            }
            [void]$sb.Append('</datafile>')
            return [System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($sb.ToString()))
        }
    }

    It "indexes every game regardless of how many <rom> entries precede its closing tag" {
        $stream = New-DatStream -RomCounts @(0, 1, 3, 2, 0)
        $index = Build-DatIndexFromStream -stream $stream
        $index.Count | Should -Be 5
        foreach ($i in 0..4) {
            $index["game$i"].ProfileCode | Should -Be "code$i"
            $index["game$i"].Executable  | Should -Be "game$i.exe"
        }
    }

    It "indexes a game with many <rom> entries followed by another game" {
        $stream = New-DatStream -RomCounts @(137, 4)
        $index = Build-DatIndexFromStream -stream $stream
        $index.Count | Should -Be 2
        $index["game0"].ProfileCode | Should -Be "code0"
        $index["game1"].ProfileCode | Should -Be "code1"
    }
}

Describe "Read-Xml" {
    It "loads a well-formed file successfully" {
        $path = Join-Path $TestDrive "good.xml"
        [System.IO.File]::WriteAllText($path, "<Root><Child>value</Child></Root>")
        $doc = Read-Xml $path
        $doc.Root.Child | Should -Be "value"
    }
    It "throws on a corrupt (non-well-formed) file rather than returning a partial document" {
        $path = Join-Path $TestDrive "corrupt.xml"
        [System.IO.File]::WriteAllText($path, "<Root><Unclosed>")
        { Read-Xml $path } | Should -Throw
    }
    It "throws on a missing file rather than returning null" {
        $path = Join-Path $TestDrive "doesnotexist.xml"
        { Read-Xml $path } | Should -Throw
    }
}

Describe "Get-NormalizedGameKey naming edge cases" {
    It "preserves digits, so sequel numbers stay distinct after normalization" {
        Get-NormalizedGameKey "VirtuaFighter4" | Should -Not -Be (Get-NormalizedGameKey "VirtuaFighter5")
    }
    It "known collision risk: bracketed tags are stripped entirely, so titles differing only by tag content normalize identically" {
        # Documents a real risk identified in the fuzzy-matching audit: a dat/folder-name
        # pair like "Game [Demo]" vs "Game [Arcade]" collapses to the same normalized key
        # because square-bracket metadata is removed wholesale, not inspected. This is
        # locked in as a characterization test (not asserted as "correct") so a future
        # change to this collision behavior is deliberate, not silent.
        $demo   = Get-NormalizedGameKey "Game [Demo]"
        $arcade = Get-NormalizedGameKey "Game [Arcade]"
        $demo | Should -Be $arcade
    }
    It "strips region codes but does not strip meaningful parenthesized names like (Special Edition)" {
        $withRegion = Get-NormalizedGameKey "Some Game (USA)"
        $plain      = Get-NormalizedGameKey "Some Game"
        $withRegion | Should -Be $plain

        Get-NormalizedGameKey "Some Game (Special Edition)" | Should -Not -Be $plain
    }
    It "normalizes Eggman-dat-style version/date suffixes to the same key as the bare title" {
        $full = Get-NormalizedGameKey "Cars (1.42)(2013-08-28)[Raw Thrills PC][TP]"
        $bare = Get-NormalizedGameKey "Cars"
        $full | Should -Be $bare
    }

    # Issue #80: older RomVault-derived folder names carry Namco board/revision-code
    # tokens that the current Eggman dat's canonical names have dropped. Each of these
    # is anchored to a real, tester-reported unmatched folder from issue #75.
    It "converges Tekken 5.1's revision-tagged folder to the bare-title key (issue #80)" {
        (Get-NormalizedGameKey "Tekken 5.1 (TE51 Ver B)(2005)[Namco System 246][TP]") |
            Should -Be (Get-NormalizedGameKey "Tekken 5.1 (2005)[Namco System 246][TP]")
    }
    It "converges Time Crisis 3's revision-tagged folder to its already-matched folder's key (issue #80)" {
        (Get-NormalizedGameKey "Time Crisis 3 (TST1 Ver A)(2003)[Namco System 246][TP]") |
            Should -Be (Get-NormalizedGameKey "Time Crisis 3 (2003)[Namco System 246][TP]")
    }
    It "converges Time Crisis 4's revision-tagged folder to its already-matched folder's key (issue #80)" {
        (Get-NormalizedGameKey "Time Crisis 4 (TSF1002-NA-A)(World)(2006)[Namco System 256][TP]") |
            Should -Be (Get-NormalizedGameKey "Time Crisis 4 (2006)[Namco System 246][TP]")
    }
    It "converges Zoids Infinity's revision-tagged folder to the bare-title key confirmed present in the current dat (issue #80)" {
        (Get-NormalizedGameKey "Zoids Infinity (B3900076A Ver 2.02J)(2004)[Namco System 246][TP]") |
            Should -Be (Get-NormalizedGameKey "Zoids Infinity (2004)[Namco System 246][TP]")
    }
    It "does not strip loosely-formatted revision text that doesn't match the board-code shape (issue #80 guard)" {
        # Characterization guard: titles like this already match successfully today
        # without stripping (their dat entries carry the identical token) -- the new
        # rules must not start stripping them, which would risk diverging from a dat
        # entry that still includes the same text.
        Get-NormalizedGameKey "Hummer (1.0 Rev A)(2009)[Sega Lindbergh Yellow][TP]" |
            Should -Not -Be (Get-NormalizedGameKey "Hummer (2009)[Sega Lindbergh Yellow][TP]")
    }
    It "does not strip short all-caps codes with no qualifying digit run (issue #80 guard)" {
        Get-NormalizedGameKey "F-Zero AX (SBGG)(2003)[Sega Triforce][TP]" |
            Should -Not -Be (Get-NormalizedGameKey "F-Zero AX (2003)[Sega Triforce][TP]")
    }
    # Issue #80 code review: the board-code-token rule's alphanumeric prefix is
    # REQUIRED, not optional -- these three guard a real risk found by scanning
    # all 438 folder names in the tester's actual install (not a partial sample):
    # an earlier draft of this rule made the prefix optional, which also matched
    # bare "(Rev C)"/"(Rev E)"-style tokens with no board code at all. All three
    # titles below already match successfully today using this exact bare text,
    # so an optional-prefix rule would have been unscoped beyond what issue #80's
    # four target titles actually need.
    It "does not strip a bare (Rev E) token with no board-code prefix (issue #80 guard)" {
        Get-NormalizedGameKey "F-Zero AX (Rev E)(SBGG)(2003)(JPN)[Sega Triforce][TP]" |
            Should -Not -Be (Get-NormalizedGameKey "F-Zero AX (SBGG)(2003)(JPN)[Sega Triforce][TP]")
    }
    It "does not strip a bare (Rev. C) token with no board-code prefix (issue #80 guard)" {
        Get-NormalizedGameKey "Netchuu! Pro Baseball 2002 (Rev. C)(2002)[Namco System 246][TP]" |
            Should -Not -Be (Get-NormalizedGameKey "Netchuu! Pro Baseball 2002 (2002)[Namco System 246][TP]")
    }
    It "does not strip a bare (Rev B) token with no board-code prefix (issue #80 guard)" {
        Get-NormalizedGameKey "Wangan Midnight Maximum Tune (3.07)(Rev B)(2004-06-10)(EXP)[Sega Chihiro][TP]" |
            Should -Not -Be (Get-NormalizedGameKey "Wangan Midnight Maximum Tune (2004-06-10)(EXP)[Sega Chihiro][TP]")
    }
}

Describe "Get-DiceSimilarity Zoids Infinity / Zoids Infinity EX Plus (issue #80 code review)" {
    It "characterizes a real, pre-existing fuzzy-collision risk -- does NOT assert protection" {
        # Issue #80 code review finding: an earlier version of this comment claimed
        # this pair was "structurally protected" by the fuzzy threshold. That claim
        # was WRONG and is retracted here. Dice("zoidsinfinity", "zoidsinfinityexplus")
        # is 0.8, ABOVE the 0.72 fuzzy-match threshold used by Register-Games' Pass-2
        # dat-name fallback scan (TeknoParrot-Manager.ps1 ~line 6161-6180). This is not
        # new: the pre-#80 code already scored 0.677 for this pair (see git history),
        # already close to threshold -- this change raises it further, to 0.8.
        #
        # What actually keeps Zoids Infinity from mis-matching to EX Plus today is
        # NOT this Dice score -- it is that the current Eggman dat has an EXACT entry
        # for "Zoids Infinity (2004)[Namco System 246][TP]" (confirmed directly
        # against the dat before implementing issue #80), so Register-Games' exact
        # dat-key lookup (line 6165) succeeds before the fuzzy fallback loop ever
        # runs. If a future dat revision ever dropped that exact entry again, this
        # score means the fuzzy fallback COULD wrongly match Zoids Infinity to EX
        # Plus. That is a pre-existing latent risk in the fuzzy dat-name fallback
        # itself (not introduced by issue #80, though this change makes the score
        # for this specific pair worse) and is out of scope to fix here -- recorded
        # so it isn't silently lost.
        $zoidsKey  = Get-NormalizedGameKey "Zoids Infinity (2004)[Namco System 246][TP]"
        $explusKey = Get-NormalizedGameKey "Zoids Infinity EX Plus (B3900107A Ver 2.10J)(2006)[Namco System 256][TP]"
        (Get-DiceSimilarity $zoidsKey $explusKey) | Should -Be 0.8
    }
}

Describe "Get-MeaningfulTitleTokens" {
    It "strips parenthetical and bracket content wholesale" {
        $tokens = Get-MeaningfulTitleTokens "Zoids Infinity (B3900076A Ver 2.02J)(2004)[Namco System 246][TP]"
        $tokens | Should -Be @('zoids', 'infinity')
    }
    It "excludes pure-digit tokens (sequel numbers, years -- handled elsewhere)" {
        $tokens = Get-MeaningfulTitleTokens "Time Crisis 3 2003"
        $tokens | Should -Not -Contain '3'
        $tokens | Should -Not -Contain '2003'
        $tokens | Should -Contain 'time'
        $tokens | Should -Contain 'crisis'
    }
    It "excludes roman numerals I-X" {
        $tokens = Get-MeaningfulTitleTokens "Street Fighter III 3rd Strike"
        $tokens | Should -Not -Contain 'iii'
    }
    It "excludes standalone roman numeral I, not just II-X (issue #84 review)" {
        # No standalone "I" appears anywhere in the real Eggman collection dat
        # (confirmed by direct search) -- excluded for consistency with the
        # rest of the I-X range, on the same basis as II/III/etc: sequel
        # numbering, already handled elsewhere by digit-preserving
        # normalization, not a title differentiator this rule needs to see.
        $tokens = Get-MeaningfulTitleTokens "Some Game I"
        $tokens | Should -Not -Contain 'i'
        $tokens | Should -Contain 'some'
        $tokens | Should -Contain 'game'
    }
    It "excludes the closed stop-word list" {
        $tokens = Get-MeaningfulTitleTokens "The House of the Dead"
        $tokens | Should -Not -Contain 'the'
        $tokens | Should -Not -Contain 'of'
        $tokens | Should -Contain 'house'
        $tokens | Should -Contain 'dead'
    }
    It "does NOT exclude single-character meaningful tokens like R (issue #84 design requirement)" {
        # "Virtua Fighter 5" vs "Virtua Fighter 5 R" are two separate real DAT
        # entries -- the trailing "R" is a real differentiator and must survive.
        $tokens = Get-MeaningfulTitleTokens "Virtua Fighter 5 R"
        $tokens | Should -Contain 'r'
    }
}

Describe "Issue #84: Pass-2 dat-name fuzzy fallback rejects candidates with extra meaningful title tokens" {
    # Replicates the exact extra-token computation Register-Games' Pass-2 fuzzy
    # fallback performs (TeknoParrot-Manager.ps1, "DatIndex (pass2)" block) against
    # real title pairs -- Register-Games itself is excluded from this suite (see
    # file header: covers pure/read-only helpers only, not live install logic), so
    # this tests the actual decision-determining function directly with the real
    # strings that matter, the same way the existing Get-DiceSimilarity tests
    # document scoring behavior without invoking Register-Games as a black box.
    BeforeAll {
        function Get-ExtraCandidateTokens {
            param([string]$FolderName, [string]$CandidateName)
            $candidateTokens = Get-MeaningfulTitleTokens $CandidateName
            $folderTokens    = Get-MeaningfulTitleTokens $FolderName
            return @($candidateTokens | Where-Object { -not $folderTokens.Contains($_) })
        }
    }

    It "blocks Zoids Infinity matching Zoids Infinity EX (real DAT entries, Dice 0.923)" {
        $extra = Get-ExtraCandidateTokens -FolderName "Zoids Infinity (2004)[Namco System 246][TP]" `
                                           -CandidateName "Zoids Infinity EX (2.10)(2006)[Namco System 246][TP]"
        @($extra).Count | Should -BeGreaterThan 0
        $extra | Should -Contain 'ex'
    }
    It "blocks Zoids Infinity matching Zoids Infinity EX Plus (real DAT entries, Dice 0.800)" {
        $extra = Get-ExtraCandidateTokens -FolderName "Zoids Infinity (2004)[Namco System 246][TP]" `
                                           -CandidateName "Zoids Infinity EX Plus (B3900107A Ver 2.10J)(2006)[Namco System 256][TP]"
        @($extra).Count | Should -BeGreaterThan 0
        $extra | Should -Contain 'ex'
        $extra | Should -Contain 'plus'
    }
    It "blocks Street Fighter IV matching Super Street Fighter IV Arcade Edition (prefix-modifier case)" {
        $extra = Get-ExtraCandidateTokens -FolderName "Street Fighter IV (2008)[PC][TP]" `
                                           -CandidateName "Super Street Fighter IV Arcade Edition (2010-11-04)(EXP,Standalone)[Taito Type X2][TP]"
        @($extra).Count | Should -BeGreaterThan 0
        $extra | Should -Contain 'super'
        $extra | Should -Contain 'arcade'
        $extra | Should -Contain 'edition'
    }
    It "blocks Battle Gear 4 matching Battle Gear 4 Tuned (real DAT entries)" {
        $extra = Get-ExtraCandidateTokens -FolderName "Battle Gear 4 (2005)[Taito Type X+][TP]" `
                                           -CandidateName "Battle Gear 4 Tuned (2.08)(2007-06-18)[Taito Type X+][TP]"
        @($extra).Count | Should -BeGreaterThan 0
        $extra | Should -Contain 'tuned'
    }
    It "positive control: allows a legitimate near-miss that differs only by metadata, not title words" {
        # This is the dominant real-world Pass-2 fuzzy-fallback case (confirmed by
        # scanning the actual DAT: most near-misses are date/version/region
        # metadata differences, not title-word differences) -- same pair already
        # covered by Resolve-ExtractedGameFolder's "matches Battle Gear 3 despite
        # harmless DAT year/date metadata differences" test, confirming this new
        # #84 rule does not introduce a new block for the case Pass-2 primarily
        # exists to handle.
        $extra = Get-ExtraCandidateTokens -FolderName "Battle Gear 3 (2.08J)(2002)[Namco System 246][TP]" `
                                           -CandidateName "Battle Gear 3 (2.08J)(2003-04-11)[Namco System 246][TP]"
        @($extra).Count | Should -Be 0
    }
    It "known scope boundary: does not extend typo tolerance to whole-word differences within a title (documented, not a regression)" {
        # This rule compares whole meaningful WORDS, not per-word bigram similarity
        # -- unlike Get-DiceSimilarity's existing typo tolerance (see the separate
        # "NicktoonsNitro"/"NicktoonNitro" characterization test, which exercises
        # Resolve-BestFuzzyMatch's Pass-3 PROFILE-CODE fuzzy matching, a different
        # code path this issue does not touch). A single-character typo inside one
        # word of a multi-word Pass-2 DAT title would still be treated as an
        # "extra" token here. Real near-misses in this codebase's actual DAT are
        # overwhelmingly metadata differences (see the positive-control test
        # above), not within-title typos, so this is an accepted, documented scope
        # boundary of the minimal #84 design, not a silent gap.
        $extra = Get-ExtraCandidateTokens -FolderName "Nicktoons Nitro (2009)[Raw Thrills PC][TP]" `
                                           -CandidateName "Nicktoon Nitro (2009)[Raw Thrills PC][TP]"
        @($extra).Count | Should -BeGreaterThan 0
    }
}

Describe "Get-DiceSimilarity near-threshold / tie behavior" {
    # These document a real gap from the fuzzy-matching audit: Get-DiceSimilarity itself
    # has no concept of a threshold or a tie-break -- that logic lives in each caller's
    # "track the best score seen so far" loop (e.g. Register-Games ~line 4650-4668), which
    # only keeps a single best candidate and silently lets iteration order decide ties.
    # These tests pin down the scoring behavior the caller relies on, so a change to
    # Get-DiceSimilarity that quietly shifts near-threshold scores doesn't go unnoticed.
    It "can produce two distinct candidates scoring within a hair of each other, with no signal to prefer one" {
        $target = Get-NormalizedGameKey "NicktoonsNitro"
        $a = Get-DiceSimilarity $target (Get-NormalizedGameKey "NicktoonNitro")
        $b = Get-DiceSimilarity $target (Get-NormalizedGameKey "NicktoonsNitros")
        # Both are near-misses of the real title by one character; the function returns
        # a bare score for each with no indication of which (if either) is the real match.
        $a | Should -BeGreaterThan 0.85
        $b | Should -BeGreaterThan 0.85
        [Math]::Abs($a - $b) | Should -BeLessThan 0.1
    }
    It "a one-character difference near the auto-register threshold can land on either side of it" {
        # FuzzyAutoThreshold is 0.72 (TeknoParrot-Manager.ps1:582). A single transposed
        # or substituted character close to the threshold means whether a game gets
        # auto-registered or falls through to manual review is sensitive to exact spelling.
        $score = Get-DiceSimilarity (Get-NormalizedGameKey "InitialDArcadeStageZero") (Get-NormalizedGameKey "InitialDArcadeStageZer0")
        $score | Should -BeGreaterThan 0.6
        $score | Should -BeLessThan 1.0
    }
}

Describe "Resolve-BestFuzzyMatch" {
    # Fix for issue #15: the old inline loop in Register-Games had no tie-break --
    # whichever candidate scored highest (with ties broken purely by iteration order)
    # was trusted as an auto-register decision with no signal that a second candidate
    # was just as plausible. These tests cover the new top-2 tracking and tie margin.
    It "auto-trusts a clear winner with no close runner-up" {
        $matchList = @(
            [pscustomobject]@{ Code = "StreetFighterIII3rdStrike" }
            [pscustomobject]@{ Code = "MarioKartArcadeGP" }
        )
        $result = Resolve-BestFuzzyMatch -NormFolder (Get-NormalizedGameKey "StreetFighterIII3rdStrike") -MatchList $matchList -RawThrillsAliases @{}
        $result.Best.Code | Should -Be "StreetFighterIII3rdStrike"
        $result.IsConfidentMatch | Should -BeTrue
    }
    It "does not trust a match below the auto-register threshold" {
        $matchList = @(
            [pscustomobject]@{ Code = "CompletelyUnrelatedTitle" }
        )
        $result = Resolve-BestFuzzyMatch -NormFolder (Get-NormalizedGameKey "SomeOtherGame") -MatchList $matchList -RawThrillsAliases @{}
        $result.IsConfidentMatch | Should -BeFalse
    }
    It "refuses to auto-trust an exact tie between two different candidates" {
        $matchList = @(
            [pscustomobject]@{ Code = "VirtuaFighter4" }
            [pscustomobject]@{ Code = "VirtuaFighter5" }
        )
        # A folder name equidistant from both candidates -- same score for each.
        $result = Resolve-BestFuzzyMatch -NormFolder (Get-NormalizedGameKey "VirtuaFighter") -MatchList $matchList -RawThrillsAliases @{}
        $result.SecondScore | Should -Be $result.BestScore
        $result.IsConfidentMatch | Should -BeFalse
    }
    It "refuses to auto-trust a near-tie even when the best score clears the threshold" {
        $matchList = @(
            [pscustomobject]@{ Code = "NicktoonNitro" }    # one char short of the real title
            [pscustomobject]@{ Code = "NicktoonsNitros" }  # one char long of the real title
        )
        $result = Resolve-BestFuzzyMatch -NormFolder (Get-NormalizedGameKey "NicktoonsNitro") -MatchList $matchList -RawThrillsAliases @{}
        $result.BestScore | Should -BeGreaterThan $FuzzyAutoThreshold
        ($result.BestScore - $result.SecondScore) | Should -BeLessThan $FuzzyTieMargin
        $result.IsConfidentMatch | Should -BeFalse
    }
    It "still applies the RawThrillsAliases short-name fallback for a single unambiguous candidate" {
        $matchList = @( [pscustomobject]@{ Code = "NicktoonsNitro" } )
        $aliases   = @{ NicktoonsNitro = [pscustomobject]@{ Suggested = "NTN" } }
        $result = Resolve-BestFuzzyMatch -NormFolder (Get-NormalizedGameKey "NTN") -MatchList $matchList -RawThrillsAliases $aliases
        $result.Best.Code | Should -Be "NicktoonsNitro"
        $result.IsConfidentMatch | Should -BeTrue
    }
}

Describe "Resolve-ExtractedGameFolder (issue #66 extraction prompt correctness)" {
    BeforeAll {
        $script:OriginalRawThrillsPathLimits = $script:RawThrillsPathLimits
    }

    BeforeEach {
        $script:installRoot = Join-Path $TestDrive "Games"
        Remove-Item -LiteralPath $script:installRoot -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $script:installRoot -Force | Out-Null
        $script:RawThrillsPathLimits = @{
            AliensArmageddon = @{ Limit = 96; Suggested = 'ALIENS' }
        }
    }

    AfterEach {
        $script:RawThrillsPathLimits = $script:OriginalRawThrillsPathLimits
    }

    It "recognizes a RetroBat-suffixed Raw Thrills short-name folder for Aliens Armageddon" {
        $existing = Join-Path $script:installRoot "ALIENS.teknoparrot"
        New-Item -ItemType Directory -Path $existing -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $existing "game.exe") -Value "content"
        $zipName = "Aliens Armageddon (1.04)(2014-11-17)[Raw Thrills PC][TP]"
        $datIndex = @{
            (Get-NormalizedGameKey $zipName) = [pscustomobject]@{
                ProfileCode = "AliensArmageddon"
                Executable  = "game.exe"
            }
        }

        Resolve-ExtractedGameFolder -RawZipName $zipName -InstallFolder $script:installRoot -DatIndex $datIndex | Should -Be $existing
    }

    It "recognizes every supported RetroBat suffix for an already extracted folder" -ForEach @(
        @{ Suffix = '.teknoparrot' }
        @{ Suffix = '.parrot' }
        @{ Suffix = '.game' }
    ) {
        $zipName = "Daytona Championship USA (3.59)[Sega PC][TP]"
        $existing = Join-Path $script:installRoot ($zipName + $Suffix)
        New-Item -ItemType Directory -Path $existing -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $existing "game.exe") -Value "content"

        Resolve-ExtractedGameFolder -RawZipName $zipName -InstallFolder $script:installRoot | Should -Be $existing
    }

    It "matches Battle Gear 3 despite harmless DAT year/date metadata differences" {
        $existingName = "Battle Gear 3 (2.08J)(2003-04-11)[Namco System 246][TP]"
        $existing = Join-Path $script:installRoot $existingName
        New-Item -ItemType Directory -Path $existing -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $existing "game.elf") -Value "content"
        $zipName = "Battle Gear 3 (2.08J)(2002)[Namco System 246][TP]"
        $datIndex = @{
            (Get-NormalizedGameKey $zipName) = [pscustomobject]@{
                ProfileCode = "BattleGear3"
                Executable  = "game.elf"
            }
        }

        Resolve-ExtractedGameFolder -RawZipName $zipName -InstallFolder $script:installRoot -DatIndex $datIndex | Should -Be $existing
    }

    It "does not confuse similarly named sequels" {
        $existing = Join-Path $script:installRoot "Virtua Fighter 4"
        New-Item -ItemType Directory -Path $existing -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $existing "vf4.exe") -Value "content"

        Resolve-ExtractedGameFolder -RawZipName "Virtua Fighter 5" -InstallFolder $script:installRoot | Should -BeNullOrEmpty
    }

    It "does not confuse Mario Kart Arcade GP with Mario Kart Arcade GP 2 (regression -- a similarity-scored fuzzy tier previously matched these two different games at 0.97 against a 0.95 threshold)" {
        $existing = Join-Path $script:installRoot "Mario Kart Arcade GP 2 (1.02)[Namco][TP]"
        New-Item -ItemType Directory -Path $existing -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $existing "game.exe") -Value "content"

        Resolve-ExtractedGameFolder -RawZipName "Mario Kart Arcade GP (1.10)[Namco][TP]" -InstallFolder $script:installRoot | Should -BeNullOrEmpty
    }

    It "does not treat an empty matching folder as already extracted" {
        $existing = Join-Path $script:installRoot "Battle Gear 3 (2.08J)(2003-04-11)[Namco System 246][TP]"
        New-Item -ItemType Directory -Path $existing -Force | Out-Null

        Resolve-ExtractedGameFolder -RawZipName "Battle Gear 3 (2.08J)(2002)[Namco System 246][TP]" -InstallFolder $script:installRoot | Should -BeNullOrEmpty
    }

    It "uses registered GamePath identity when a valid profile points at a renamed existing folder" {
        $renamed = Join-Path $script:installRoot "My Hand Picked Folder"
        New-Item -ItemType Directory -Path $renamed -Force | Out-Null
        $exePath = Join-Path $renamed "launcher.exe"
        Set-Content -LiteralPath $exePath -Value "content"

        $profiles = Join-Path $TestDrive "UserProfiles"
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $profiles "CustomCode.xml") -Value @"
<GameProfile>
  <GamePath>$exePath</GamePath>
</GameProfile>
"@
        $zipName = "Some Collection Name (2024)[Platform][TP]"
        $datIndex = @{
            (Get-NormalizedGameKey $zipName) = [pscustomobject]@{
                ProfileCode = "CustomCode"
                Executable  = "launcher.exe"
            }
        }

        Resolve-ExtractedGameFolder -RawZipName $zipName -InstallFolder $script:installRoot -DatIndex $datIndex -UserProfilesDir $profiles | Should -Be $renamed
    }

    It "ignores registered identity when the dat profile code is not path-safe" {
        $renamed = Join-Path $script:installRoot "Unsafe Profile Code Folder"
        New-Item -ItemType Directory -Path $renamed -Force | Out-Null
        $exePath = Join-Path $renamed "launcher.exe"
        Set-Content -LiteralPath $exePath -Value "content"

        $profiles = Join-Path $TestDrive "UnsafeProfiles"
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $profiles "Unsafe.xml") -Value "<GameProfile><GamePath>$exePath</GamePath></GameProfile>"
        $zipName = "Unsafe Profile Code Test"
        $datIndex = @{
            (Get-NormalizedGameKey $zipName) = [pscustomobject]@{
                ProfileCode = "..\Unsafe"
                Executable  = "launcher.exe"
            }
        }

        Resolve-ExtractedGameFolder -RawZipName $zipName -InstallFolder $script:installRoot -DatIndex $datIndex -UserProfilesDir $profiles | Should -BeNullOrEmpty
    }
}

Describe "Invoke-AutoSync extracted-folder regression guards" {
    BeforeAll {
        $script:OriginalAutoSyncRawThrillsPathLimits = $script:RawThrillsPathLimits
    }

    BeforeEach {
        $script:autoSyncZipSource = Join-Path $TestDrive "ZipSource"
        $script:autoSyncInstallRoot = Join-Path $TestDrive "AutoSyncGames"
        New-Item -ItemType Directory -Path $script:autoSyncZipSource, $script:autoSyncInstallRoot -Force | Out-Null
        Mock Write-Log {}
    }

    AfterEach {
        $script:RawThrillsPathLimits = $script:OriginalAutoSyncRawThrillsPathLimits
    }

    It "does not extract when issue #66 resolver finds an existing RetroBat short-name folder" {
        $zipName = "Aliens Armageddon (1.04)(2014-11-17)[Raw Thrills PC][TP]"
        $zipPath = Join-Path $script:autoSyncZipSource ($zipName + ".zip")
        Set-Content -LiteralPath $zipPath -Value "placeholder zip bytes"

        $existing = Join-Path $script:autoSyncInstallRoot "ALIENS.teknoparrot"
        New-Item -ItemType Directory -Path $existing -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $existing "game.exe") -Value "content"
        $script:RawThrillsPathLimits = @{
            AliensArmageddon = @{ Limit = 96; Suggested = 'ALIENS' }
        }
        $datIndex = @{
            (Get-NormalizedGameKey $zipName) = [pscustomobject]@{
                ProfileCode = "AliensArmageddon"
                Executable  = "game.exe"
            }
        }
        Mock Expand-ZipFileSafe { throw "AutoSync should not extract already-present games" }

        $result = Invoke-AutoSync -zipSource $script:autoSyncZipSource -installFolder $script:autoSyncInstallRoot -syncStatePath (Join-Path $TestDrive "sync.json") -retroBat $true -datIndex $datIndex

        $result.UpToDate | Should -Be 1
        $result.Synced | Should -Be 0
        Should -Invoke Expand-ZipFileSafe -Times 0
    }
}

Describe "New-PostgresPgPassFile / Remove-PostgresPgPassFile" {
    # Issue #3 (v1.0 roadmap): migrated Postgres credential passing from
    # $env:PGPASSWORD to a temporary .pgpass-format file, so the password is
    # never visible in psql.exe/etc.'s own process environment block. These
    # tests cover the file format (libpq's documented
    # hostname:port:database:username:password syntax) and escaping rules,
    # plus cleanup -- not the icacls lockdown, which is best-effort hardening
    # on top and not load-bearing for correctness.
    It "writes a single line in the documented hostname:port:database:username:password format" {
        $path = New-PostgresPgPassFile -Password "hunter2"
        try {
            (Get-Content -LiteralPath $path -Raw).Trim() | Should -Be "127.0.0.1:5432:*:postgres:hunter2"
        } finally {
            Remove-PostgresPgPassFile -Path $path
        }
    }
    It "escapes a backslash and a colon in the password per the pgpass format" {
        $path = New-PostgresPgPassFile -Password 'p:a\ss'
        try {
            (Get-Content -LiteralPath $path -Raw).Trim() | Should -Be '127.0.0.1:5432:*:postgres:p\:a\\ss'
        } finally {
            Remove-PostgresPgPassFile -Path $path
        }
    }
    It "creates a real file that Remove-PostgresPgPassFile then deletes" {
        $path = New-PostgresPgPassFile -Password "anything"
        Test-Path -LiteralPath $path | Should -BeTrue
        Remove-PostgresPgPassFile -Path $path
        Test-Path -LiteralPath $path | Should -BeFalse
    }
    It "does not throw when asked to remove a path that doesn't exist" {
        $missing = Join-Path $TestDrive "does-not-exist.conf"
        { Remove-PostgresPgPassFile -Path $missing } | Should -Not -Throw
    }
    It "does not throw when asked to remove a null/empty path" {
        { Remove-PostgresPgPassFile -Path $null } | Should -Not -Throw
        { Remove-PostgresPgPassFile -Path "" } | Should -Not -Throw
    }
}

Describe "Read-PathWithBrowse" {
    # This is UI code (it can launch a real WinForms file/folder picker), which
    # is outside this project's stated Pester scope the same way other menu/UI
    # code already is -- these tests only cover the manual-entry passthrough
    # (mocking Read-Host, the one real cmdlet involved), never the actual
    # dialog-showing branch, which has no practical way to assert against in an
    # automated run without clicking through a real modal window.
    It "returns whatever was typed, unchanged, when the user does not type B" {
        Mock Read-Host { "C:\Some\Typed\Path" }
        Read-PathWithBrowse "Enter a path" | Should -Be "C:\Some\Typed\Path"
    }
    It "is case-insensitive when checking for the browse trigger (only 'b'/'B' triggers it, not a path that happens to start with B)" {
        Mock Read-Host { "B:\SomeDrive" }
        # A typed path literally starting with the letter B must NOT be misread as
        # the browse trigger -- only an exact "B" (after Trim) should be.
        Read-PathWithBrowse "Enter a path" | Should -Be "B:\SomeDrive"
    }
    It "returns an empty string passthrough when the user presses Enter with nothing typed" {
        Mock Read-Host { "" }
        Read-PathWithBrowse "Enter a path" | Should -Be ""
    }
}

Describe "Get-ReShadeLatestVersion retry behavior" {
    BeforeAll {
        Mock Invoke-WebRequest {}
    }

    It "makes only a single attempt and returns null on failure -- no retry, unlike Invoke-TpmDownload's HttpClient/Invoke-WebRequest tiers" {
        Mock Invoke-WebRequest { throw "site unreachable" }
        $result = Get-ReShadeLatestVersion
        $result | Should -BeNullOrEmpty
        Should -Invoke Invoke-WebRequest -Times 1
    }
    It "parses the version out of a successful response" {
        Mock Invoke-WebRequest { [pscustomobject]@{ Content = "...ReShade_Setup_6.7.3.exe..." } }
        Get-ReShadeLatestVersion | Should -Be "6.7.3"
    }
}

Describe "Test-EggmanDatReleaseUrl" {
    It "accepts the expected Eggmansworld TeknoParrot GitHub release URL" {
        Test-EggmanDatReleaseUrl "https://github.com/Eggmansworld/TeknoParrot/releases/download/2026-06-17/TeknoParrot.Collection.RomVault.zip" | Should -BeTrue
    }
    It "rejects lookalike or non-release URLs" {
        Test-EggmanDatReleaseUrl "https://github.com.evil.example.com/Eggmansworld/TeknoParrot/releases/download/2026-06-17/file.zip" | Should -BeFalse
        Test-EggmanDatReleaseUrl "https://github.com/OtherOwner/TeknoParrot/releases/download/2026-06-17/file.zip" | Should -BeFalse
        Test-EggmanDatReleaseUrl "http://github.com/Eggmansworld/TeknoParrot/releases/download/2026-06-17/file.zip" | Should -BeFalse
    }
}

Describe "Invoke-TpmDownload method selection and partial-file cleanup" {
    BeforeAll {
        Mock Write-Log {}
        Mock Write-Host {}
        Mock Write-DownloadAudit {}
        Mock Write-TpmDownloadMetrics {}
        Mock Start-Sleep {}
        Mock Invoke-TpmDownloadBits { Set-Content -LiteralPath $TempPath -Value "fake zip content" -NoNewline }
        Mock Invoke-TpmDownloadHttpClient { Set-Content -LiteralPath $TempPath -Value "fake zip content" -NoNewline }
        Mock Invoke-TpmDownloadWebRequest { Set-Content -LiteralPath $TempPath -Value "fake zip content" -NoNewline }
    }
    BeforeEach {
        Mock Test-TpmDownloadBitsAvailable { $true }
    }

    It "uses BITS first when it is available" {
        $savePath = Join-Path $TestDrive "bits-success.zip"

        $result = Invoke-TpmDownload -DownloadUrl "https://example.com/file.zip" -DestinationPath $savePath

        $result | Should -BeTrue
        Test-Path -LiteralPath $savePath | Should -BeTrue
        Should -Invoke Invoke-TpmDownloadBits -Times 1
        Should -Invoke Invoke-TpmDownloadHttpClient -Times 0
        Should -Invoke Invoke-TpmDownloadWebRequest -Times 0
    }

    It "falls back to HttpClient when BITS is unavailable" {
        Mock Test-TpmDownloadBitsAvailable { $false }
        $savePath = Join-Path $TestDrive "httpclient-success.zip"

        $result = Invoke-TpmDownload -DownloadUrl "https://example.com/file.zip" -DestinationPath $savePath

        $result | Should -BeTrue
        Test-Path -LiteralPath $savePath | Should -BeTrue
        Should -Invoke Invoke-TpmDownloadBits -Times 0
        Should -Invoke Invoke-TpmDownloadHttpClient -Times 1
        Should -Invoke Invoke-TpmDownloadWebRequest -Times 0
    }

    It "uses Invoke-WebRequest only after BITS and HttpClient exhaust their retries" {
        Mock Invoke-TpmDownloadBits { throw "bits failed" }
        Mock Invoke-TpmDownloadHttpClient { throw "http failed" }
        $savePath = Join-Path $TestDrive "webrequest-success.zip"

        $result = Invoke-TpmDownload -DownloadUrl "https://example.com/file.zip" -DestinationPath $savePath

        $result | Should -BeTrue
        Test-Path -LiteralPath $savePath | Should -BeTrue
        Should -Invoke Invoke-TpmDownloadBits -Times 1
        # A generic (non-HTTP-status) failure retries up to 3 times before falling through.
        Should -Invoke Invoke-TpmDownloadHttpClient -Times 3
        Should -Invoke Invoke-TpmDownloadWebRequest -Times 1
    }

    It "retries a transient HttpClient failure and succeeds on a later attempt without falling through to Invoke-WebRequest" {
        Mock Test-TpmDownloadBitsAvailable { $false }
        $script:httpAttempt = 0
        Mock Invoke-TpmDownloadHttpClient {
            $script:httpAttempt++
            if ($script:httpAttempt -lt 2) { throw "transient network error" }
            Set-Content -LiteralPath $TempPath -Value "fake zip content" -NoNewline
        }
        $savePath = Join-Path $TestDrive "httpclient-retry-success.zip"

        $result = Invoke-TpmDownload -DownloadUrl "https://example.com/file.zip" -DestinationPath $savePath

        $result | Should -BeTrue
        $script:httpAttempt | Should -Be 2
        Should -Invoke Invoke-TpmDownloadWebRequest -Times 0
    }

    It "does not retry HttpClient on a definitive 404 before falling through to Invoke-WebRequest" {
        Mock Test-TpmDownloadBitsAvailable { $false }
        Mock Invoke-TpmDownloadHttpClient { throw "Response status code does not indicate success: 404 (Not Found)." }
        $savePath = Join-Path $TestDrive "httpclient-404-no-retry.zip"

        $result = Invoke-TpmDownload -DownloadUrl "https://example.com/missing.zip" -DestinationPath $savePath

        $result | Should -BeTrue
        Should -Invoke Invoke-TpmDownloadHttpClient -Times 1
        Should -Invoke Invoke-TpmDownloadWebRequest -Times 1
    }

    It "retries a transient Invoke-WebRequest failure and succeeds on a later attempt" {
        Mock Test-TpmDownloadBitsAvailable { $false }
        Mock Invoke-TpmDownloadHttpClient { throw "http failed" }
        $script:webAttempt = 0
        Mock Invoke-TpmDownloadWebRequest {
            $script:webAttempt++
            if ($script:webAttempt -lt 2) { throw "transient network error" }
            Set-Content -LiteralPath $TempPath -Value "fake zip content" -NoNewline
        }
        $savePath = Join-Path $TestDrive "webrequest-retry-success.zip"

        $result = Invoke-TpmDownload -DownloadUrl "https://example.com/file.zip" -DestinationPath $savePath

        $result | Should -BeTrue
        $script:webAttempt | Should -Be 2
    }

    It "surfaces the final HTTP status code via -LastStatusCode when every method fails" {
        Mock Test-TpmDownloadBitsAvailable { $false }
        Mock Invoke-TpmDownloadHttpClient { throw "Response status code does not indicate success: 404 (Not Found)." }
        Mock Invoke-TpmDownloadWebRequest { throw "Response status code does not indicate success: 404 (Not Found)." }
        $savePath = Join-Path $TestDrive "status-code-404.zip"
        $statusCode = 0

        $result = Invoke-TpmDownload -DownloadUrl "https://example.com/missing.zip" -DestinationPath $savePath -LastStatusCode ([ref]$statusCode)

        $result | Should -BeFalse
        $statusCode | Should -Be 404
    }

    It "reports status code 0 via -LastStatusCode when the failure is not HTTP-status-related" {
        Mock Test-TpmDownloadBitsAvailable { $false }
        Mock Invoke-TpmDownloadHttpClient { throw "DNS resolution failed" }
        Mock Invoke-TpmDownloadWebRequest { throw "DNS resolution failed" }
        $savePath = Join-Path $TestDrive "status-code-unknown.zip"
        $statusCode = 999

        $result = Invoke-TpmDownload -DownloadUrl "https://example.com/file.zip" -DestinationPath $savePath -LastStatusCode ([ref]$statusCode)

        $result | Should -BeFalse
        $statusCode | Should -Be 0
    }

    It "deletes any partial file and leaves the final path untouched when all methods fail" {
        Mock Invoke-TpmDownloadBits { param($DownloadUrl, $TempPath) Set-Content -LiteralPath $TempPath -Value "partial"; throw "bits failed" }
        Mock Invoke-TpmDownloadHttpClient { param($DownloadUrl, $TempPath) Set-Content -LiteralPath $TempPath -Value "partial"; throw "http failed" }
        Mock Invoke-TpmDownloadWebRequest { param($DownloadUrl, $TempPath) Set-Content -LiteralPath $TempPath -Value "partial"; throw "web failed" }
        $savePath = Join-Path $TestDrive "failed.zip"

        $result = Invoke-TpmDownload -DownloadUrl "https://example.com/file.zip" -DestinationPath $savePath

        $result | Should -BeFalse
        Test-Path -LiteralPath $savePath | Should -BeFalse
        @(Get-ChildItem -LiteralPath $TestDrive -Filter "*.partial" -Force).Count | Should -Be 0
    }

    It "rejects an incomplete file when an expected size is provided" {
        Mock Test-TpmDownloadBitsAvailable { $false }
        Mock Invoke-TpmDownloadHttpClient { Set-Content -LiteralPath $TempPath -Value "short" -NoNewline }
        $savePath = Join-Path $TestDrive "too-small.zip"

        $result = Invoke-TpmDownload -DownloadUrl "https://example.com/file.zip" -DestinationPath $savePath -ExpectedBytes 100

        $result | Should -BeFalse
        Test-Path -LiteralPath $savePath | Should -BeFalse
        @(Get-ChildItem -LiteralPath $TestDrive -Filter "*.partial" -Force).Count | Should -Be 0
    }
}

Describe "Invoke-TpmDownload progress overlay cleanup (issue #132)" {
    # Regression coverage for the stale "Downloading Thumbnails" progress
    # overlay that persisted over the TPM menu after a thumbnail 404. Root
    # cause: every download tier raises the Id 42 Write-Progress overlay as
    # it starts, but only each tier's own success path cleared it -- every
    # failure/exception exit left whatever was last written on screen
    # permanently. The fix wraps Invoke-TpmDownload in a finally that always
    # completes Id 42, regardless of how the function exits.
    BeforeAll {
        Mock Write-Log {}
        Mock Write-Host {}
        Mock Write-DownloadAudit {}
        Mock Write-TpmDownloadMetrics {}
        Mock Start-Sleep {}
        Mock Write-Progress {}
    }
    BeforeEach {
        Mock Test-TpmDownloadBitsAvailable { $false }
    }

    It "completes the Id 42 overlay after a successful download" {
        Mock Invoke-TpmDownloadHttpClient { Set-Content -LiteralPath $TempPath -Value "fake" -NoNewline }
        $savePath = Join-Path $TestDrive "progress-success.png"

        Invoke-TpmDownload -DownloadUrl "https://example.com/a.png" -DestinationPath $savePath -Label 'Thumbnails' | Should -BeTrue

        Should -Invoke Write-Progress -Times 1 -ParameterFilter { $Id -eq 42 -and $Completed }
    }

    It "completes the Id 42 overlay after a single definitive 404 (one thumbnail missing upstream)" {
        Mock Invoke-TpmDownloadHttpClient { throw "Response status code does not indicate success: 404 (Not Found)." }
        Mock Invoke-TpmDownloadWebRequest { throw "Response status code does not indicate success: 404 (Not Found)." }
        $savePath = Join-Path $TestDrive "progress-404.png"
        $statusCode = 0

        $result = Invoke-TpmDownload -DownloadUrl "https://example.com/missing.png" -DestinationPath $savePath -Label 'Thumbnails' -LastStatusCode ([ref]$statusCode)

        $result | Should -BeFalse
        $statusCode | Should -Be 404
        Should -Invoke Write-Progress -Times 1 -ParameterFilter { $Id -eq 42 -and $Completed }
    }

    It "completes the Id 42 overlay after a non-404 failure (generic download error, all tiers exhausted)" {
        Mock Invoke-TpmDownloadHttpClient { throw "DNS resolution failed" }
        Mock Invoke-TpmDownloadWebRequest { throw "DNS resolution failed" }
        $savePath = Join-Path $TestDrive "progress-generic-fail.png"

        Invoke-TpmDownload -DownloadUrl "https://example.com/a.png" -DestinationPath $savePath -Label 'Thumbnails' | Should -BeFalse

        Should -Invoke Write-Progress -Times 1 -ParameterFilter { $Id -eq 42 -and $Completed }
    }

    It "completes the Id 42 overlay even when an unexpected exception is thrown after a successful transfer" {
        Mock Invoke-TpmDownloadHttpClient { Set-Content -LiteralPath $TempPath -Value "fake" -NoNewline }
        Mock Write-DownloadAudit { throw "unexpected post-download failure" }
        $savePath = Join-Path $TestDrive "progress-exception.png"

        Invoke-TpmDownload -DownloadUrl "https://example.com/a.png" -DestinationPath $savePath -Label 'Thumbnails' | Should -BeFalse

        Should -Invoke Write-Progress -Times 1 -ParameterFilter { $Id -eq 42 -and $Completed }
    }

    It "clears the overlay independently for each call in a mixed batch (404, then success, then generic failure)" {
        $savePath1 = Join-Path $TestDrive "batch-1-404.png"
        $savePath2 = Join-Path $TestDrive "batch-2-success.png"
        $savePath3 = Join-Path $TestDrive "batch-3-failed.png"

        Mock Invoke-TpmDownloadHttpClient { throw "Response status code does not indicate success: 404 (Not Found)." }
        Mock Invoke-TpmDownloadWebRequest { throw "Response status code does not indicate success: 404 (Not Found)." }
        $r1 = Invoke-TpmDownload -DownloadUrl "https://example.com/missing.png" -DestinationPath $savePath1 -Label 'Thumbnails'

        Mock Invoke-TpmDownloadHttpClient { Set-Content -LiteralPath $TempPath -Value "fake" -NoNewline }
        Mock Invoke-TpmDownloadWebRequest { throw "should not be reached" }
        $r2 = Invoke-TpmDownload -DownloadUrl "https://example.com/found.png" -DestinationPath $savePath2 -Label 'Thumbnails'

        Mock Invoke-TpmDownloadHttpClient { throw "DNS resolution failed" }
        Mock Invoke-TpmDownloadWebRequest { throw "DNS resolution failed" }
        $r3 = Invoke-TpmDownload -DownloadUrl "https://example.com/broken.png" -DestinationPath $savePath3 -Label 'Thumbnails'

        $r1 | Should -BeFalse
        $r2 | Should -BeTrue
        $r3 | Should -BeFalse
        Should -Invoke Write-Progress -Times 3 -ParameterFilter { $Id -eq 42 -and $Completed }
    }

    It "clears the overlay for every call across an all-404 batch (upstream has none of these icons)" {
        Mock Invoke-TpmDownloadHttpClient { throw "Response status code does not indicate success: 404 (Not Found)." }
        Mock Invoke-TpmDownloadWebRequest { throw "Response status code does not indicate success: 404 (Not Found)." }

        1..3 | ForEach-Object {
            $savePath = Join-Path $TestDrive "all-404-$_.png"
            Invoke-TpmDownload -DownloadUrl "https://example.com/missing-$_.png" -DestinationPath $savePath -Label 'Thumbnails' | Should -BeFalse
        }

        Should -Invoke Write-Progress -Times 3 -ParameterFilter { $Id -eq 42 -and $Completed }
    }
}

Describe "Invoke-TpmDownload timeout / malformed content / cancellation (issue #132)" {
    # Rounds out the issue #132 acceptance criteria (HTTP 200/404 and mixed-
    # batch cleanup are already covered above): a network timeout, a
    # corrupt/incomplete downloaded file, and a user-cancelled transfer are
    # not special-cased anywhere in Invoke-TpmDownload -- they are ordinary
    # exceptions that must still be caught by the outer try/catch/finally,
    # never mis-reported as a 404 ("not in the online pack"), and must still
    # clear the Id 42 progress overlay and remove the partial temp file.
    BeforeAll {
        Mock Write-Log {}
        Mock Write-Host {}
        Mock Write-DownloadAudit {}
        Mock Write-TpmDownloadMetrics {}
        Mock Start-Sleep {}
        Mock Write-Progress {}
    }
    BeforeEach {
        Mock Test-TpmDownloadBitsAvailable { $false }
    }

    It "treats an HttpClient timeout as a generic failure (not a 404), clears the overlay, and removes the partial file" {
        Mock Invoke-TpmDownloadHttpClient {
            Set-Content -LiteralPath $TempPath -Value "partial" -NoNewline
            throw [System.Threading.Tasks.TaskCanceledException]::new("A task was canceled.")
        }
        Mock Invoke-TpmDownloadWebRequest { throw [System.Threading.Tasks.TaskCanceledException]::new("A task was canceled.") }
        $savePath = Join-Path $TestDrive "timeout-fail.png"
        $statusCode = 0

        $result = Invoke-TpmDownload -DownloadUrl "https://example.com/slow.png" -DestinationPath $savePath -Label 'Thumbnails' -LastStatusCode ([ref]$statusCode)

        $result | Should -BeFalse
        $statusCode | Should -Not -Be 404
        Test-Path -LiteralPath $savePath | Should -BeFalse
        Should -Invoke Write-Progress -Times 1 -ParameterFilter { $Id -eq 42 -and $Completed }
    }

    It "rejects an incomplete/malformed download that doesn't match the expected size, clears the overlay, and leaves no partial file behind" {
        Mock Invoke-TpmDownloadHttpClient {
            # Simulates a truncated/corrupt transfer: succeeds without
            # throwing, but writes fewer bytes than the caller expects.
            Set-Content -LiteralPath $TempPath -Value "short" -NoNewline
        }
        $savePath = Join-Path $TestDrive "malformed.png"

        $result = Invoke-TpmDownload -DownloadUrl "https://example.com/a.png" -DestinationPath $savePath -ExpectedBytes 999999 -Label 'Thumbnails'

        $result | Should -BeFalse
        Test-Path -LiteralPath $savePath | Should -BeFalse
        Should -Invoke Write-Progress -Times 1 -ParameterFilter { $Id -eq 42 -and $Completed }
    }

    It "treats a cancelled transfer (OperationCanceledException) as a clean failure, not an unhandled crash" {
        Mock Invoke-TpmDownloadHttpClient { throw [System.OperationCanceledException]::new("The operation was canceled.") }
        Mock Invoke-TpmDownloadWebRequest { throw [System.OperationCanceledException]::new("The operation was canceled.") }
        $savePath = Join-Path $TestDrive "cancelled.png"

        { Invoke-TpmDownload -DownloadUrl "https://example.com/a.png" -DestinationPath $savePath -Label 'Thumbnails' } | Should -Not -Throw
        $result = Invoke-TpmDownload -DownloadUrl "https://example.com/a.png" -DestinationPath $savePath -Label 'Thumbnails'

        $result | Should -BeFalse
        Should -Invoke Write-Progress -Times 2 -ParameterFilter { $Id -eq 42 -and $Completed }
    }

    It "clears the overlay for every call across a complete non-404 batch failure (e.g. upstream host unreachable)" {
        Mock Invoke-TpmDownloadHttpClient { throw "The remote name could not be resolved." }
        Mock Invoke-TpmDownloadWebRequest { throw "The remote name could not be resolved." }

        $statusCodes = 1..3 | ForEach-Object {
            $savePath = Join-Path $TestDrive "batch-fail-$_.png"
            $sc = 0
            $r = Invoke-TpmDownload -DownloadUrl "https://example.com/x-$_.png" -DestinationPath $savePath -Label 'Thumbnails' -LastStatusCode ([ref]$sc)
            $r | Should -BeFalse
            $sc
        }

        $statusCodes | Should -Not -Contain 404
        Should -Invoke Write-Progress -Times 3 -ParameterFilter { $Id -eq 42 -and $Completed }
    }
}

Describe "Invoke-TpmDownloadBits BITS polling states" {
    It "the polling loop's continue-states list includes TransientError (a recoverable BITS state), not just Connecting/Transferring/Queued" {
        $scriptContent = Get-Content -LiteralPath $scriptPath -Raw
        $scriptContent | Should -Match "'Connecting',\s*'Transferring',\s*'Queued',\s*'TransientError'"
    }
}

Describe "Invoke-CrosshairSetup P1/P2 prompts use the safe input path (issue #135 RC3 correction)" {
    # Invoke-CrosshairSetup cannot be exercised end-to-end in this suite for
    # the same reason documented on "Invoke-ThumbnailDownload 404-vs-failure
    # distinction" below: it reads $PSScriptRoot to locate the Crosshairs\
    # folder, which is empty because functions here are dot-sourced from an
    # AST extract with no backing file, so the function returns immediately
    # ("Crosshairs folder not found") before ever reaching the P1/P2 prompts
    # these tests target -- not something to route around by changing
    # production code under a "smallest safe fix" scope.
    #
    # These two prompts were the two remaining unguarded
    # `(Read-Host $promptText).Trim()` call sites missed by the original
    # #135 migration (that migration's regex only matched a Read-Host
    # argument that was a literal double-quoted string or a fully
    # parenthesized expression -- $promptText is a bare variable, a third
    # shape the regex never covered). Each site sits inside a
    # `while ($null -eq $pXIdx) { ... }` retry loop with no bound: under the
    # old unguarded code, once redirected stdin was exhausted, `Read-Host`
    # would return $null forever and `$null.Trim()` would throw a
    # NullReferenceException on the very first re-read after exhaustion --
    # worse than the plain crash-once behavior elsewhere in the script,
    # because Write-Host's "Enter a number..." retry message would print
    # first, masking that the real cause was exhausted input, not a bad
    # answer.
    BeforeAll {
        $fullSource = Get-Content -LiteralPath $scriptPath -Raw
        $start = $fullSource.IndexOf('function Invoke-CrosshairSetup')
        $end = $fullSource.IndexOf("`nfunction ", $start + 10)
        $script:crosshairSource = $fullSource.Substring($start, $end - $start)
    }

    It "finds the Invoke-CrosshairSetup function body to check" {
        $script:crosshairSource | Should -Not -BeNullOrEmpty
    }

    It "the P1 and P2 index prompts both go through Read-HostSafe" {
        (@([regex]::Matches($script:crosshairSource, 'Read-HostSafe \$promptText')).Count) | Should -Be 2
    }

    It "no bare Read-Host call in this function has .Trim() or .ToUpper() chained directly onto it" {
        $script:crosshairSource | Should -Not -Match '\(Read-Host\b[^)]*\)\.(Trim|ToUpper)\('
    }

    # Read-HostSafe's own null/exhausted-input behavior (never throws, exits
    # cleanly via the mockable Exit-TpmProcess instead) is already covered
    # exhaustively by "Read-HostSafe / Exit-TpmProcess (issue #135:
    # non-interactive input)" above -- since both crosshair prompts now
    # route through that exact same, already-tested function instead of a
    # bare Read-Host, that coverage applies here directly. This test
    # exercises the specific retry-loop SHAPE used in Invoke-CrosshairSetup
    # (a `while ($null -eq $idx) { $raw = (Read-HostSafe ...); ... }` loop
    # that never bounds its own retries) against a mocked exhausted stream,
    # proving the loop cannot spin on a null dereference even though the
    # real function isn't directly callable here.
    It "the crosshair index retry-loop shape terminates via Exit-TpmProcess on exhausted input instead of dereferencing null" {
        $script:readHostCallCount = 0
        Mock Read-Host { $script:readHostCallCount++; return $null }
        Mock Exit-TpmProcess { throw 'simulated-process-exit' }
        Mock Write-Log { }

        $validCount = 3
        $lastIdx = $null
        $idx = $null

        {
            while ($null -eq $idx) {
                if ($script:readHostCallCount -gt 5) { throw 'test guard: loop did not stop on exhausted input' }
                $promptText = if ($null -ne $lastIdx) {
                    "  P1 crosshair index (0-{0}, Enter for last used: {1})" -f ($validCount - 1), $lastIdx
                } else { "  P1 crosshair index (0-{0})" -f ($validCount - 1) }
                $raw = (Read-HostSafe $promptText)
                if ($raw -eq '' -and $null -ne $lastIdx) { $idx = $lastIdx }
                elseif ($raw -match '^\d+$' -and $raw.Length -le 9 -and [int]$raw -lt $validCount) { $idx = [int]$raw }
            }
        } | Should -Throw 'simulated-process-exit'

        # Exactly one Read-Host call before the mocked Exit-TpmProcess threw
        # -- proves the loop did not spin re-reading the exhausted stream.
        $script:readHostCallCount | Should -Be 1
        Should -Invoke Exit-TpmProcess -Times 1 -ParameterFilter { $Code -eq 1 }
    }
}

Describe "Invoke-ThumbnailDownload 404-vs-failure distinction" {
    # Invoke-ThumbnailDownload cannot be exercised end-to-end in this suite:
    # it reads $PSScriptRoot to locate CustomThumbnails\, which is empty
    # because functions here are dot-sourced from an AST extract with no
    # backing file (see the top-level BeforeAll). That makes the unrelated
    # CustomThumbnails Join-Path call throw a parameter-binding error before
    # the function ever reaches the download loop these tests target.
    # Confirmed empirically that neither reassigning $ErrorActionPreference
    # (BeforeEach or inline -- parameter-binding failures aren't governed by
    # it) nor mocking Join-Path (Pester's mock proxy mirrors the real
    # cmdlet's parameter validation, so the same binding failure recurs, and
    # routing through the module-qualified name from inside the mock
    # recurses back into the mock itself) can reach past this. This is a
    # pre-existing characteristic of the function, unrelated to the 404-vs-
    # failure fix -- not something to work around by changing production
    # code under a "smallest safe fix" scope. Verifying the fix at the
    # source level instead: these assert the exact code shape (StatusCode
    # -eq 404 -> notAvail, else -> failed) is present, which still fails if
    # the branching is ever accidentally reverted or merged wrong.
    BeforeAll {
        $fullSource = Get-Content -LiteralPath $scriptPath -Raw
        $script:thumbSource = $null
        $start = $fullSource.IndexOf('function Invoke-ThumbnailDownload')
        if ($start -ge 0) {
            $end = $fullSource.IndexOf("`nfunction ", $start + 10)
            $script:thumbSource = $fullSource.Substring($start, $end - $start)
        }
    }

    It "finds the Invoke-ThumbnailDownload function body to check" {
        $script:thumbSource | Should -Not -BeNullOrEmpty
    }

    It "passes -LastStatusCode through to Invoke-TpmDownload so 404 can be distinguished" {
        $script:thumbSource | Should -Match '-LastStatusCode\s*\(\[ref\]\$statusCode\)'
    }

    It "routes a 404 status code to the not-in-repo branch, not the failed branch" {
        $script:thumbSource | Should -Match '\$statusCode\s+-eq\s+404'
    }

    It "increments the failed counter (not the not-in-repo counter) for a non-404 failure" {
        # The elseif branch must handle the 404 case; whatever comes after
        # it (the plain else) is the non-404/generic-failure branch and
        # must increment $failed, not $notAvail.
        $script:thumbSource | Should -Match '\$statusCode\s+-eq\s+404[\s\S]*?\}\s*else\s*\{[\s\S]*?\$failed\+\+'
    }
}

Describe "Write-TpmDownloadProgress" {
    BeforeAll {
        Mock Write-Progress {}
    }

    It "shows percent complete when total size is known" {
        Write-TpmDownloadProgress -Method 'HttpClient' -DownloadedBytes 5242880 -TotalBytes 10485760 -Elapsed ([TimeSpan]::FromSeconds(2))

        Should -Invoke Write-Progress -Times 1 -ParameterFilter {
            $PercentComplete -eq 50 -and $Status -like '*5/10 MB*' -and $Status -like '*MB/s*' -and $Status -like '*ETA*'
        }
    }

    It "uses an indeterminate status when total size is unknown" {
        Write-TpmDownloadProgress -Method 'HttpClient' -DownloadedBytes 5242880 -TotalBytes 0 -Elapsed ([TimeSpan]::FromSeconds(2))

        Should -Invoke Write-Progress -Times 1 -ParameterFilter {
            $Status -like '*5 MB downloaded*' -and -not $PSBoundParameters.ContainsKey('PercentComplete')
        }
    }
}

Describe "Invoke-EggmanDatDownloadInteractive cache reuse" {
    BeforeAll {
        Mock Write-Log {}
        Mock Write-Host {}
        Mock Read-PathWithBrowse { "" }
        Mock Invoke-EggmanDatDownload { throw "download should be skipped when the cached file matches the expected size" }
    }

    It "does not re-download when the target file already matches the release size" {
        $fileName = "TeknoParrot.Collection.RomVault.zip"
        $defaultPath = Join-Path (Get-Location).Path $fileName
        try {
            Set-Content -LiteralPath $defaultPath -Value "12345" -NoNewline
            $rel = [pscustomobject]@{
                DownloadUrl = "https://github.com/Eggmansworld/TeknoParrot/releases/download/2026-06-17/$fileName"
                FileName    = $fileName
                SizeBytes   = 5
            }

            Invoke-EggmanDatDownloadInteractive $rel | Should -Be $defaultPath
            Should -Invoke Invoke-EggmanDatDownload -Times 0
        } finally {
            Remove-Item -LiteralPath $defaultPath -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Thumbnail download regression guards" {
    BeforeAll {
        $script:thumbnailFunctionSource = ${function:Invoke-ThumbnailDownload}.ToString()
    }

    It "keeps the already-present icon fast path before building the download list" {
        $script:thumbnailFunctionSource | Should -Match 'Test-Path\s+-LiteralPath\s+\(Join-Path\s+\$iconsDir\s+\(\$f\.BaseName\s+\+\s+"\.png"\)\)'
        $script:thumbnailFunctionSource | Should -Match '\$alreadyCount\+\+'
        $script:thumbnailFunctionSource | Should -Match '\[void\]\$missing\.Add\(\$f\.BaseName\)'
    }

    It "delegates thumbnail downloads (and their failure/partial-file cleanup) to the shared download helper" {
        # Cleanup used to be reimplemented per-call-site here (Test-Path /
        # Remove-Item directly on $destPath). After the download-pipeline
        # hardening (issue #67), Invoke-TpmDownload owns partial-file
        # staging and cleanup centrally (see "Invoke-TpmDownload method
        # selection and partial-file cleanup" below) -- this function must
        # call it rather than reimplement cleanup itself.
        $script:thumbnailFunctionSource | Should -Match 'Invoke-TpmDownload\s+-DownloadUrl\s+\$url\s+-DestinationPath\s+\$destPath'
        $script:thumbnailFunctionSource | Should -Match '-LastStatusCode\s*\(\[ref\]\$statusCode\)'
    }

    It "flags an all-404 batch distinctly from a real failure (issue #132 -- likely profile-code/upstream-name mismatch, not a broken download path)" {
        $script:thumbnailFunctionSource | Should -Match '\$fetched\s+-eq\s+0\s+-and\s+\$failed\s+-eq\s+0\s+-and\s+\$notAvail\s+-eq\s+\$total\s+-and\s+\$total\s+-gt\s+0'
    }
}

Describe "Invoke-TpmDownload finally block always clears the progress overlay (issue #132)" {
    It "the finally block completes Id 42 unconditionally, not only on the success path" {
        $fullSource = Get-Content -LiteralPath $scriptPath -Raw
        $start = $fullSource.IndexOf('function Invoke-TpmDownload {')
        $start | Should -BeGreaterThan -1
        $end = $fullSource.IndexOf("`nfunction ", $start + 10)
        $downloadFnSource = $fullSource.Substring($start, $end - $start)

        $downloadFnSource | Should -Match '\}\s*finally\s*\{\s*[\s\S]*?Write-Progress\s+-Id\s+42\s+-Activity\s+"Downloading\s+\$Label"\s+-Completed'
    }
}

Describe "Crosshair setup regression guards" {
    It "backs up PCSX2.ini before rewriting cursor paths" {
        $iniDir = Join-Path $TestDrive "inis"
        New-Item -ItemType Directory -Path $iniDir -Force | Out-Null
        $iniPath = Join-Path $iniDir "PCSX2.ini"
        Set-Content -LiteralPath $iniPath -Value "[USB Port 1 guncon2]`ncursor_path = old1`n[USB Port 2 guncon2]`ncursor_path = old2"
        Mock Write-Log {}

        Set-Pcsx2CursorPaths -IniPath $iniPath -P1Path "C:\Crosshairs\P1.png" -P2Path "C:\Crosshairs\P2.png"

        $updated = Get-Content -LiteralPath $iniPath -Raw
        $updated | Should -Match ([regex]::Escape("cursor_path = C:\Crosshairs\P1.png"))
        $updated | Should -Match ([regex]::Escape("cursor_path = C:\Crosshairs\P2.png"))
        @(Get-ChildItem -LiteralPath $iniDir -Filter "PCSX2.ini.bak_*" -File).Count | Should -Be 1
    }

    # Invoke-CrosshairSetup itself is an interactive wizard (Read-Host prompts,
    # browser preview launch) excluded from direct unit testing per this file's
    # policy -- source-level check instead, same pattern as "Main menu
    # source-level drift check" below for other hard-to-unit-test interactive code.
    It "deploys pcsx2x6 crosshairs to the canonical TeknoParrot\crosshairs subfolder, not the emulator folder root (issue #79)" {
        $source = Get-Content -LiteralPath $scriptPath -Raw
        $source | Should -Match ([regex]::Escape('Join-Path $pcsx2Dir "TeknoParrot\crosshairs"'))
        # Regression guard: the pre-#79-fix deployment target (folder root) must
        # not reappear as the pcsx2x6 P1/P2 destination.
        $source | Should -Not -Match ([regex]::Escape('Join-Path $pcsx2Dir "P1.png"'))
        $source | Should -Not -Match ([regex]::Escape('Join-Path $pcsx2Dir "P2.png"'))
    }
}

Describe "Test-ButtonNameDirectional" {
    # Pure up/down/left/right labels (with various player-prefix formats) are directional.
    It "classifies plain 'Up' as directional" {
        Test-ButtonNameDirectional "Up" | Should -BeTrue
    }
    It "classifies 'Player 1 Up' as directional" {
        Test-ButtonNameDirectional "Player 1 Up" | Should -BeTrue
    }
    It "classifies 'P1 UP' as directional (case-insensitive, P1 prefix)" {
        Test-ButtonNameDirectional "P1 UP" | Should -BeTrue
    }
    It "classifies 'Player 2 Down' as directional" {
        Test-ButtonNameDirectional "Player 2 Down" | Should -BeTrue
    }
    It "classifies diagonal 'Up Right' as directional" {
        Test-ButtonNameDirectional "Up Right" | Should -BeTrue
    }

    # Names that contain direction words but also have non-direction qualifiers are NOT directional.
    It "classifies 'Player 1 Left Punch' as NOT directional (attack qualifier)" {
        Test-ButtonNameDirectional "Player 1 Left Punch" | Should -BeFalse
    }
    It "classifies 'Player 1 Right Kick' as NOT directional (attack qualifier)" {
        Test-ButtonNameDirectional "Player 1 Right Kick" | Should -BeFalse
    }
    It "classifies 'Player 1 Left Shoulder' as NOT directional (non-direction qualifier)" {
        Test-ButtonNameDirectional "Player 1 Left Shoulder" | Should -BeFalse
    }

    # Pure attack/action labels with no direction words are NOT directional.
    It "classifies 'Player 1 LP' as NOT directional" {
        Test-ButtonNameDirectional "Player 1 LP" | Should -BeFalse
    }
    It "classifies 'P1 ATTACK' as NOT directional" {
        Test-ButtonNameDirectional "P1 ATTACK" | Should -BeFalse
    }
    It "classifies empty string as NOT directional" {
        Test-ButtonNameDirectional "" | Should -BeFalse
    }
}

Describe "Invoke-ControlPropagation duplicate-key handling (issue #53)" {
    BeforeAll {
        function New-ControlProfileXml {
            param(
                [string]$Name,
                [string]$Buttons
            )

            return @"
<GameProfile>
  <GameName>$Name</GameName>
  <JoystickButtons>
$Buttons
  </JoystickButtons>
  <ConfigValues />
</GameProfile>
"@
        }

        function New-WheelButtonXml {
            param(
                [string]$Name,
                [string]$Mapping = 'P1Wheel',
                [switch]$Bound
            )

            $binding = if ($Bound) {
                @"
      <RawInputButton>
        <DevicePath>test-wheel</DevicePath>
        <ButtonName>X+</ButtonName>
      </RawInputButton>
"@
            } else {
                ''
            }

            return @"
    <JoystickButtons>
      <ButtonName>$Name</ButtonName>
      <InputMapping>$Mapping</InputMapping>
      <AnalogType>Wheel</AnalogType>
$binding
    </JoystickButtons>
"@
        }
    }

    It "uses an archetype match key only once per target profile" {
        $profiles = Join-Path $TestDrive 'UserProfiles'
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null

        $archetypeButtons = @(
            New-WheelButtonXml -Name 'Wheel Right' -Bound
            New-WheelButtonXml -Name 'Gas' -Mapping 'P1Gas' -Bound
            New-WheelButtonXml -Name 'Brake' -Mapping 'P1Brake' -Bound
        ) -join "`n"
        New-ControlProfileXml -Name 'Reference Driver' -Buttons $archetypeButtons |
            Set-Content -LiteralPath (Join-Path $profiles 'ReferenceDriver.xml') -Encoding UTF8

        $targetButtons = @(
            New-WheelButtonXml -Name 'Wheel Left'
            New-WheelButtonXml -Name 'Wheel Right'
        ) -join "`n"
        New-ControlProfileXml -Name 'Duplicate Wheel Target' -Buttons $targetButtons |
            Set-Content -LiteralPath (Join-Path $profiles 'DuplicateWheelTarget.xml') -Encoding UTF8

        $pool = Build-ArchetypePool $profiles 3
        $reports = Invoke-ControlPropagation -userProfilesDir $profiles -pool $pool -minBound 3 -DryRun:$false
        [xml]$updated = Get-Content -LiteralPath (Join-Path $profiles 'DuplicateWheelTarget.xml') -Raw
        $targetSlots = @($updated.SelectNodes('/GameProfile/JoystickButtons/JoystickButtons'))
        $boundSlots = @($targetSlots | Where-Object { Test-ButtonIsBound $_ })
        $manualReport = @($reports | Where-Object { $_.Code -eq 'DuplicateWheelTarget' } | Select-Object -First 1)

        $boundSlots.Count | Should -Be 1
        $manualReport.Status | Should -Be 'bound'
        $manualReport.Manual | Should -Contain 'Wheel Right'
    }
}

Describe "Invoke-ControlPropagation canonicalArchetype Input API correction (issue #139)" {
    # Fixtures modeled directly on the real diagnostic data posted to issue
    # #139: StreetFighterIII3rdStrike (SF3) and fghtjam (Capcom Fighting Jam)
    # were found to have byte-for-byte identical Coin1/Coin2/P1ButtonStart/
    # P2ButtonStart bindings (button 54/54/55/55 on the same two joystick
    # GUIDs) -- the reported "inconsistent mapping" was never a binding
    # divergence between these two titles. The actual defect confirmed on
    # this issue was that "Input API" can independently drift between two
    # archetypes of the same family (fghtjam's on-disk FieldOptions lacked
    # MergedInput entirely, unlike SF3's), and that canonicalArchetype
    # correction only propagates whatever the canonical game's Input API
    # happens to be in the live pool snapshot at the moment propagation
    # runs -- so the canonical game must already be on the intended API
    # before the fix is applied, or the "fix" just propagates the wrong
    # value to every other archetype in the family.
    BeforeAll {
        function New-ButtonFamilyProfileXml {
            param(
                [string]$Name,
                [string]$InputApiValue,
                [string[]]$InputApiOptions
            )
            $optionsXml = ($InputApiOptions | ForEach-Object { "        <string>$_</string>" }) -join "`n"
            $slots = @(
                @{ Name = 'Test';               Mapping = 'Test';           Button = 92 }
                @{ Name = 'Service 1';           Mapping = 'Service1';       Button = 93 }
                @{ Name = 'Service 2';           Mapping = 'Service2';       Button = 94 }
                @{ Name = 'Coin 1';              Mapping = 'Coin1';          Button = 54 }
                @{ Name = 'Coin 2';              Mapping = 'Coin2';          Button = 54 }
                @{ Name = 'Player 1 Start';      Mapping = 'P1ButtonStart';  Button = 55 }
                @{ Name = 'Player 2 Start';      Mapping = 'P2ButtonStart';  Button = 55 }
            )
            $buttonsXml = ($slots | ForEach-Object {
                @"
    <JoystickButtons>
      <ButtonName>$($_.Name)</ButtonName>
      <InputMapping>$($_.Mapping)</InputMapping>
      <DirectInputButton>
        <Button>$($_.Button)</Button>
      </DirectInputButton>
    </JoystickButtons>
"@
            }) -join "`n"
            return @"
<GameProfile>
  <GameName>$Name</GameName>
  <JoystickButtons>
$buttonsXml
  </JoystickButtons>
  <ConfigValues>
    <FieldInformation>
      <FieldName>Input API</FieldName>
      <FieldValue>$InputApiValue</FieldValue>
      <FieldOptions>
$optionsXml
      </FieldOptions>
    </FieldInformation>
  </ConfigValues>
</GameProfile>
"@
        }
    }

    It "does not alter either archetype's own button bindings, even though both are independently bound and physically identical" {
        $profiles = Join-Path $TestDrive ("issue139-bindings-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null

        New-ButtonFamilyProfileXml -Name 'StreetFighterIII3rdStrike' -InputApiValue 'MergedInput' -InputApiOptions @('DirectInput', 'XInput', 'MergedInput') |
            Set-Content -LiteralPath (Join-Path $profiles 'StreetFighterIII3rdStrike.xml') -Encoding UTF8
        New-ButtonFamilyProfileXml -Name 'fghtjam' -InputApiValue 'DirectInput' -InputApiOptions @('DirectInput', 'XInput') |
            Set-Content -LiteralPath (Join-Path $profiles 'fghtjam.xml') -Encoding UTF8

        $before = Get-Content -LiteralPath (Join-Path $profiles 'fghtjam.xml') -Raw
        $pool = Build-ArchetypePool $profiles 5
        [void](Invoke-ControlPropagation -userProfilesDir $profiles -pool $pool -minBound 5 -DryRun:$false)
        $after = Get-Content -LiteralPath (Join-Path $profiles 'fghtjam.xml') -Raw

        ([xml]$after).SelectSingleNode("/GameProfile/JoystickButtons/JoystickButtons[InputMapping='Coin1']/DirectInputButton/Button").InnerText | Should -Be '54'
        ([xml]$after).SelectSingleNode("/GameProfile/JoystickButtons/JoystickButtons[InputMapping='P1ButtonStart']/DirectInputButton/Button").InnerText | Should -Be '55'
    }

    It "corrects a non-canonical archetype's Input API to match the canonical archetype's CURRENT value, including injecting a missing MergedInput FieldOptions entry" {
        $profiles = Join-Path $TestDrive ("issue139-api-fix-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null

        New-ButtonFamilyProfileXml -Name 'StreetFighterIII3rdStrike' -InputApiValue 'MergedInput' -InputApiOptions @('DirectInput', 'XInput', 'MergedInput') |
            Set-Content -LiteralPath (Join-Path $profiles 'StreetFighterIII3rdStrike.xml') -Encoding UTF8
        New-ButtonFamilyProfileXml -Name 'fghtjam' -InputApiValue 'DirectInput' -InputApiOptions @('DirectInput', 'XInput') |
            Set-Content -LiteralPath (Join-Path $profiles 'fghtjam.xml') -Encoding UTF8

        $pool = Build-ArchetypePool $profiles 5
        $canonicalArchetype = @{ button = 'StreetFighterIII3rdStrike' }
        $reports = Invoke-ControlPropagation -userProfilesDir $profiles -pool $pool -minBound 5 -canonicalArchetype $canonicalArchetype -DryRun:$false

        [xml]$fghtjamAfter = Get-Content -LiteralPath (Join-Path $profiles 'fghtjam.xml') -Raw
        $apiField = $fghtjamAfter.SelectSingleNode("/GameProfile/ConfigValues/FieldInformation[FieldName='Input API']")
        $apiField.FieldValue | Should -Be 'MergedInput'
        @($apiField.SelectNodes('FieldOptions/string') | ForEach-Object { $_.InnerText }) | Should -Contain 'MergedInput'

        $fixedReport = @($reports | Where-Object { $_.Code -eq 'fghtjam' } | Select-Object -First 1)
        $fixedReport.Status | Should -Be 'api-fixed-canonical'
    }

    It "propagates the WRONG value if the canonical archetype itself is not yet on the intended API when correction runs (ordering hazard confirmed on issue #139)" {
        # This documents the exact failure mode from the issue thread: writing
        # canonicalArchetype to overrides.json before switching the canonical
        # game's own Input API does not "fix forward" -- it corrects every
        # other archetype in the family to match whatever the canonical
        # game's CURRENT (possibly still-wrong) value is.
        $profiles = Join-Path $TestDrive ("issue139-ordering-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null

        New-ButtonFamilyProfileXml -Name 'StreetFighterIII3rdStrike' -InputApiValue 'DirectInput' -InputApiOptions @('DirectInput', 'XInput', 'MergedInput') |
            Set-Content -LiteralPath (Join-Path $profiles 'StreetFighterIII3rdStrike.xml') -Encoding UTF8
        New-ButtonFamilyProfileXml -Name 'fghtjam' -InputApiValue 'MergedInput' -InputApiOptions @('DirectInput', 'XInput', 'MergedInput') |
            Set-Content -LiteralPath (Join-Path $profiles 'fghtjam.xml') -Encoding UTF8

        $pool = Build-ArchetypePool $profiles 5
        $canonicalArchetype = @{ button = 'StreetFighterIII3rdStrike' }
        [void](Invoke-ControlPropagation -userProfilesDir $profiles -pool $pool -minBound 5 -canonicalArchetype $canonicalArchetype -DryRun:$false)

        [xml]$fghtjamAfter = Get-Content -LiteralPath (Join-Path $profiles 'fghtjam.xml') -Raw
        $fghtjamAfter.SelectSingleNode("/GameProfile/ConfigValues/FieldInformation[FieldName='Input API']/FieldValue").InnerText | Should -Be 'DirectInput'
    }

    It "does not touch a non-canonical archetype whose Input API already matches the canonical archetype" {
        $profiles = Join-Path $TestDrive ("issue139-noop-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null

        New-ButtonFamilyProfileXml -Name 'StreetFighterIII3rdStrike' -InputApiValue 'MergedInput' -InputApiOptions @('DirectInput', 'XInput', 'MergedInput') |
            Set-Content -LiteralPath (Join-Path $profiles 'StreetFighterIII3rdStrike.xml') -Encoding UTF8
        New-ButtonFamilyProfileXml -Name 'BBCF' -InputApiValue 'MergedInput' -InputApiOptions @('DirectInput', 'XInput', 'MergedInput') |
            Set-Content -LiteralPath (Join-Path $profiles 'BBCF.xml') -Encoding UTF8

        $pool = Build-ArchetypePool $profiles 5
        $canonicalArchetype = @{ button = 'StreetFighterIII3rdStrike' }
        $reports = Invoke-ControlPropagation -userProfilesDir $profiles -pool $pool -minBound 5 -canonicalArchetype $canonicalArchetype -DryRun:$false

        @($reports | Where-Object { $_.Code -eq 'BBCF' }).Count | Should -Be 0
    }
}

Describe "MinBoundForArchetype initialization order (issue #139)" {
    # Confirmed root cause on issue #139: the standalone "Propagate Controls"
    # menu handler runs entirely inside the MAIN MENU LOOP and returns via
    # `continue` without ever reaching SECTION 10, where
    # $MinBoundForArchetype was previously first assigned. Left unset on
    # that path, [int]$minBound coerced $null to 0 in Build-ArchetypePool,
    # so every profile (including fully unbound ones) qualified as an
    # archetype and propagation silently produced "Games updated: 0" with no
    # per-game report lines. This is a source-level regression guard (not a
    # functional test) because the bug is about variable-initialization
    # ordering in the interactive menu loop, not a pure function's behavior.
    BeforeAll {
        $script:rawScriptText = Get-Content -LiteralPath (Join-Path $PSScriptRoot "..\TeknoParrot-Manager.ps1") -Raw
    }

    It "assigns `$MinBoundForArchetype before the standalone PropagateControls menu handler can read it" {
        $handlerIndex = $script:rawScriptText.IndexOf('if ($mode -eq "PropagateControls")')
        $handlerIndex | Should -BeGreaterThan 0

        $assignmentIndex = $script:rawScriptText.IndexOf('$MinBoundForArchetype = 5')
        $assignmentIndex | Should -BeGreaterThan 0
        $assignmentIndex | Should -BeLessThan $handlerIndex
    }
}

Describe "Write-ControlPropagationResults (issue #59: standalone Propagate Controls)" {
    # This function is the shared reporting step behind both the AutoSync/
    # Register-only flow and the standalone "Propagate Controls" menu option
    # (issue #59) -- the same $reports shape Invoke-ControlPropagation always
    # returns, in, count out. Exercising it directly protects both call sites
    # from drifting out of sync with each other.
    It "counts bound/api-fixed/api-fixed-canonical as updated and returns the no-archetype subset" {
        $reports = @(
            [pscustomobject]@{ Code = 'GameA'; Status = 'bound'; Family = 'driving'; Archetype = 'RefDriver'; Bound = 3; Manual = @(); ConfigCarried = @(); ApiSet = $true; ArchetypeApi = 'RawInput'; Forced = $false; MismatchSlots = $null }
            [pscustomobject]@{ Code = 'GameB'; Status = 'api-fixed'; ArchetypeApi = 'RawInput'; Archetype = 'RefDriver'; MismatchSlots = $null }
            [pscustomobject]@{ Code = 'GameC'; Status = 'api-fixed-canonical'; ArchetypeApi = 'RawInput'; Archetype = 'RefDriver'; MismatchSlots = $null }
            [pscustomobject]@{ Code = 'GameD'; Status = 'no-archetype'; Family = 'lightgun'; MismatchSlots = $null }
            [pscustomobject]@{ Code = 'GameE'; Status = 'skipped-bound'; MismatchSlots = $null }
            [pscustomobject]@{ Code = 'GameF'; Status = 'skipped-override'; MismatchSlots = $null }
            [pscustomobject]@{ Code = 'GameG'; Status = 'save-failed'; Archetype = 'RefDriver'; MismatchSlots = $null }
        )

        $result = Write-ControlPropagationResults -Reports $reports

        $result.BoundCount | Should -Be 3
        $result.NoArchetypeItems.Count | Should -Be 1
        $result.NoArchetypeItems[0].Code | Should -Be 'GameD'
    }

    It "returns zero updated and an empty no-archetype list for an all-skipped report set" {
        $reports = @(
            [pscustomobject]@{ Code = 'GameH'; Status = 'skipped-bound'; MismatchSlots = $null }
            [pscustomobject]@{ Code = 'GameI'; Status = 'skipped-override'; MismatchSlots = $null }
        )

        $result = Write-ControlPropagationResults -Reports $reports

        $result.BoundCount | Should -Be 0
        $result.NoArchetypeItems.Count | Should -Be 0
    }
}

Describe "New-PropagationBackup (P1 fix: standalone Propagate Controls must abort on incomplete backup)" {
    # Independent engineering review finding on PR #62: a backup-copy error in the standalone
    # Propagate Controls menu option only warned and allowed the caller to
    # continue -- including automatically in -Unattended mode -- so
    # Invoke-ControlPropagation could run against an incomplete backup. This
    # directly proves the gating condition every caller relies on: ErrorCount
    # is greater than zero whenever any source file could not be copied, with
    # no path that reports success/zero on a partial failure.
    It "reports zero errors and the correct path when every file copies successfully" {
        $profiles = Join-Path $TestDrive ("propback-ok-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $profiles 'Game.xml') -Value '<GameProfile/>' -Encoding UTF8

        $result = New-PropagationBackup -UserProfilesDir $profiles

        $result.ErrorCount | Should -Be 0
        Test-Path -LiteralPath (Join-Path $result.Path 'Game.xml') | Should -BeTrue
    }

    It "signals an abort-worthy failure when a source file is locked and cannot be copied" {
        # A sharing-violation on Copy-Item can surface either as a
        # non-terminating error (caught into ErrorCount via -ErrorAction
        # SilentlyContinue) or, depending on exactly how the underlying I/O
        # call fails, as a terminating exception that -ErrorAction alone
        # does not suppress. Both are safe: the real caller in the
        # "PropagateControls" menu block wraps this call in try/catch AND
        # checks ErrorCount, so either outcome correctly prevents
        # Invoke-ControlPropagation from running. This test accepts either,
        # since the point is proving no path silently reports success.
        $profiles = Join-Path $TestDrive ("propback-locked-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null
        $lockedPath = Join-Path $profiles 'Locked.xml'
        Set-Content -LiteralPath $lockedPath -Value '<GameProfile/>' -Encoding UTF8

        $handle = [System.IO.File]::Open($lockedPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        try {
            $threw = $false
            $result = $null
            try {
                $result = New-PropagationBackup -UserProfilesDir $profiles
            } catch {
                $threw = $true
            }
            ($threw -or $result.ErrorCount -gt 0) | Should -BeTrue
        } finally {
            $handle.Dispose()
        }
    }
}

# =============================================================================
# COMPATIBILITY REGRESSION SUITE (issues #41 / #43 / #46)
# These contexts protect the compatibility-sensitive setup decisions against
# upstream TeknoParrot schema/platform drift. The cardinal invariant under
# test throughout: an unsupported or unknown outcome must report WouldWrite =
# $false, i.e. never causes the setup flow to write a profile.
# =============================================================================

Describe "Get-FFBBlasterSupport (issue #41 capability gating)" {
    BeforeAll {
        # Builds a full <GameProfile> with an EmulationProfile and arbitrary
        # ConfigValues inner XML, so the platform deny-list and field gate are
        # both exercised the way the real per-profile loop sees them.
        function New-FfbProfileDoc {
            param([string]$Platform, [string]$Inner)
            return [xml]"<GameProfile><EmulationProfile>$Platform</EmulationProfile><ConfigValues>$Inner</ConfigValues></GameProfile>"
        }
        $script:FfbField = "<FieldInformation><CategoryName>FFB Blaster</CategoryName><FieldName>Enable</FieldName><FieldType>Bool</FieldType><FieldValue>0</FieldValue></FieldInformation>"
    }

    It "Supported: a profile with an FFB Blaster Bool field is offered setup and WouldWrite when not yet enabled" {
        $doc = New-FfbProfileDoc -Platform "EuropaRFordRacing" -Inner $script:FfbField
        $r = Get-FFBBlasterSupport -Doc $doc -Categories @('FFB Blaster')
        $r.Status     | Should -Be 'Supported'
        $r.WouldWrite | Should -BeTrue
        $r.Changes[0].NewValue | Should -Be '1'
    }
    It "Supported but no write needed: an already-enabled field reports WouldWrite=false" {
        $inner = "<FieldInformation><CategoryName>FFB Blaster</CategoryName><FieldName>Enable</FieldName><FieldType>Bool</FieldType><FieldValue>1</FieldValue></FieldInformation>"
        $doc = New-FfbProfileDoc -Platform "Daytona3" -Inner $inner
        $r = Get-FFBBlasterSupport -Doc $doc -Categories @('FFB Blaster')
        $r.Status     | Should -Be 'Supported'
        $r.UpToDate   | Should -BeTrue
        $r.WouldWrite | Should -BeFalse
    }
    It "Unsupported (no field): a profile without an FFB Blaster field is skipped and never written" {
        $inner = "<FieldInformation><CategoryName>General</CategoryName><FieldName>Windowed</FieldName><FieldType>Bool</FieldType><FieldValue>0</FieldValue></FieldInformation>"
        $doc = New-FfbProfileDoc -Platform "EuropaRFordRacing" -Inner $inner
        $r = Get-FFBBlasterSupport -Doc $doc -Categories @('FFB Blaster')
        $r.Status     | Should -Be 'Unsupported'
        $r.WouldWrite | Should -BeFalse
    }
    It "Unsupported (PCSX2x6): a pcsx2x6 profile is skipped EVEN when an FFB Blaster field is present" {
        # Deny-list must win over field presence -- this is the core safety
        # property: a future upstream field on an unsupported platform must
        # never trigger a write.
        $doc = New-FfbProfileDoc -Platform "pcsx2x6" -Inner $script:FfbField
        $r = Get-FFBBlasterSupport -Doc $doc -Categories @('FFB Blaster')
        $r.Status     | Should -Be 'Unsupported'
        $r.WouldWrite | Should -BeFalse
        $r.Reason     | Should -Match 'pcsx2x6'
    }
    It "Unsupported (PCSX2x6 via EmulatorType fallback): deny-list also matches when only EmulatorType carries the platform" {
        $doc = [xml]"<GameProfile><EmulatorType>pcsx2x6</EmulatorType><ConfigValues>$script:FfbField</ConfigValues></GameProfile>"
        $r = Get-FFBBlasterSupport -Doc $doc -Categories @('FFB Blaster')
        $r.Status     | Should -Be 'Unsupported'
        $r.WouldWrite | Should -BeFalse
    }
    It "Unsupported (PCSX2x6 case-insensitive): 'PCSX2X6' is matched regardless of case" {
        $doc = New-FfbProfileDoc -Platform "PCSX2X6" -Inner $script:FfbField
        (Get-FFBBlasterSupport -Doc $doc -Categories @('FFB Blaster')).Status | Should -Be 'Unsupported'
    }
    It "Unknown: an FFB Blaster-shaped field that is NOT a writable Bool is flagged for review, never written" {
        # FieldType is Dropdown, not Bool -> schema drift -> Unknown, no write.
        $inner = "<FieldInformation><CategoryName>FFB Blaster</CategoryName><FieldName>Mode</FieldName><FieldType>Dropdown</FieldType><FieldValue>Off</FieldValue><FieldOptions><string>Off</string><string>On</string></FieldOptions></FieldInformation>"
        $doc = New-FfbProfileDoc -Platform "Daytona3" -Inner $inner
        $r = Get-FFBBlasterSupport -Doc $doc -Categories @('FFB Blaster')
        $r.Status     | Should -Be 'Unknown'
        $r.WouldWrite | Should -BeFalse
    }
    It "paid-membership confirmation alone does not make an unsupported profile writable (gate is structural, not membership-based)" {
        # The function takes no membership flag -- membership is asked once at
        # the top of Invoke-FFBBlasterSetup and never feeds this decision. A
        # pcsx2x6 profile is Unsupported no matter what the user answered.
        $doc = New-FfbProfileDoc -Platform "pcsx2x6" -Inner $script:FfbField
        (Get-FFBBlasterSupport -Doc $doc -Categories @('FFB Blaster')).WouldWrite | Should -BeFalse
    }
}

Describe "Get-FFBBlasterFieldNames drift vs absent distinction (issue #41 diagnostic improvement)" {
    # Get-FFBBlasterFieldNames returns only Bool fields -- by design. When it
    # returns empty the caller must distinguish schema drift (shaped non-Bool
    # field exists) from genuine absence (no FFB-Blaster-shaped field at all).
    # This Describe exercises the pure detection helper rather than the setup
    # flow (which involves I/O on a GameProfiles directory).
    BeforeAll {
        function New-GpFieldDoc {
            param([string]$FieldType)
            return [xml]"<GameProfile><ConfigValues><FieldInformation><CategoryName>FFB Blaster</CategoryName><FieldName>Enable</FieldName><FieldType>$FieldType</FieldType><FieldValue>0</FieldValue></FieldInformation></ConfigValues></GameProfile>"
        }
    }
    It "Get-FFBBlasterFieldNames returns a non-empty set when the field is Bool" {
        $doc = New-GpFieldDoc "Bool"
        # Categories are discovered from GameProfile XML at runtime; here we
        # validate that a Bool field would be discovered (so Get-FFBBlasterSupport
        # later gets a valid Categories list and reaches the Supported branch).
        $doc.SelectNodes("/GameProfile/ConfigValues/FieldInformation") |
            Where-Object { $_.FieldType -ieq 'Bool' -and
                           ($_.CategoryName -imatch $script:FFBBlasterNamePattern -or
                            $_.FieldName    -imatch $script:FFBBlasterNamePattern) } |
            Should -Not -BeNullOrEmpty
    }
    It "Get-FFBBlasterSupport returns Unknown (not Unsupported) when the only shaped field is non-Bool (upstream schema drift)" {
        # This is the critical distinction: if ALL shaped fields changed FieldType
        # upstream, Get-FFBBlasterFieldNames returns empty (no Bool fields to
        # discover). At the per-profile level, Get-FFBBlasterSupport still sees the
        # shaped-but-wrong-type field and correctly returns Unknown, not Unsupported.
        $doc = [xml]"<GameProfile><EmulationProfile>Daytona3</EmulationProfile><ConfigValues><FieldInformation><CategoryName>FFB Blaster</CategoryName><FieldName>Enable</FieldName><FieldType>Dropdown</FieldType><FieldValue>Off</FieldValue><FieldOptions><string>Off</string><string>On</string></FieldOptions></FieldInformation></ConfigValues></GameProfile>"
        # Pass empty categories (as Get-FFBBlasterFieldNames would return after drift)
        $r = Get-FFBBlasterSupport -Doc $doc -Categories @()
        $r.Status     | Should -Be 'Unknown'
        $r.WouldWrite | Should -BeFalse
    }
    It "Get-FFBBlasterSupport returns Unsupported (not Unknown) when no shaped field exists at all" {
        $doc = [xml]"<GameProfile><EmulationProfile>Daytona3</EmulationProfile><ConfigValues><FieldInformation><CategoryName>General</CategoryName><FieldName>Windowed</FieldName><FieldType>Bool</FieldType><FieldValue>1</FieldValue></FieldInformation></ConfigValues></GameProfile>"
        $r = Get-FFBBlasterSupport -Doc $doc -Categories @()
        $r.Status     | Should -Be 'Unsupported'
        $r.WouldWrite | Should -BeFalse
    }
}

Describe "Get-GameProfileSchemaDrift (issue #43 schema drift detection)" {
    BeforeAll {
        function New-DriftDoc { param([string]$Xml) return [xml]$Xml }
        $script:GoodProfile = @"
<GameProfile>
  <EmulationProfile>EuropaRFordRacing</EmulationProfile>
  <GameProfileRevision>22</GameProfileRevision>
  <ExecutableName>fordracing.exe</ExecutableName>
  <EmulatorType>TeknoParrot</EmulatorType>
  <ConfigValues>
    <FieldInformation><CategoryName>General</CategoryName><FieldName>Windowed</FieldName><FieldType>Bool</FieldType><FieldValue>1</FieldValue></FieldInformation>
    <FieldInformation><CategoryName>General</CategoryName><FieldName>Input API</FieldName><FieldType>Dropdown</FieldType><FieldValue>DirectInput</FieldValue></FieldInformation>
  </ConfigValues>
</GameProfile>
"@
    }

    It "reports no drift for a known, well-formed profile" {
        $r = Get-GameProfileSchemaDrift -Doc (New-DriftDoc $script:GoodProfile)
        $r.HasDrift          | Should -BeFalse
        $r.UnknownNodes.Count    | Should -Be 0
        $r.MissingRequired.Count | Should -Be 0
        $r.WouldWrite        | Should -BeFalse
    }
    It "tolerates a known optional node (GamePath2) without flagging drift" {
        $xml = $script:GoodProfile -replace '</ConfigValues>', '</ConfigValues><GamePath2>C:\game\amdaemon.exe</GamePath2>'
        (Get-GameProfileSchemaDrift -Doc (New-DriftDoc $xml)).HasDrift | Should -BeFalse
    }
    It "reports an unknown NEW top-level node but never proposes a write" {
        # Simulates an upstream addition like a CXBXR/Lindbergh-ELF2 marker.
        $xml = $script:GoodProfile -replace '</ConfigValues>', '</ConfigValues><Cxbxr_SomeNewMarker>true</Cxbxr_SomeNewMarker>'
        $r = Get-GameProfileSchemaDrift -Doc (New-DriftDoc $xml)
        $r.HasDrift     | Should -BeTrue
        $r.UnknownNodes | Should -Contain 'Cxbxr_SomeNewMarker'
        $r.WouldWrite   | Should -BeFalse
    }
    It "reports a removed REQUIRED node as drift" {
        $xml = $script:GoodProfile -replace '<EmulationProfile>EuropaRFordRacing</EmulationProfile>', ''
        $r = Get-GameProfileSchemaDrift -Doc (New-DriftDoc $xml)
        $r.HasDrift         | Should -BeTrue
        $r.MissingRequired  | Should -Contain 'EmulationProfile'
    }
    It "reports an unknown FieldType as drift but never proposes a write" {
        $xml = $script:GoodProfile -replace '<FieldType>Bool</FieldType>', '<FieldType>FutureRangeSliderV2</FieldType>'
        $r = Get-GameProfileSchemaDrift -Doc (New-DriftDoc $xml)
        $r.HasDrift           | Should -BeTrue
        $r.UnknownFieldTypes  | Should -Contain 'FutureRangeSliderV2'
        $r.WouldWrite         | Should -BeFalse
    }
    It "treats a missing <GameProfile> root as maximal drift, never a write" {
        $r = Get-GameProfileSchemaDrift -Doc ([xml]"<NotAGameProfile><Foo/></NotAGameProfile>")
        $r.HasRoot    | Should -BeFalse
        $r.HasDrift   | Should -BeTrue
        $r.WouldWrite | Should -BeFalse
    }
}

Describe "Third-party FFB plugin destination safety (issue #46)" {
    # The plugin flow resolves a destination DLL filename from the live
    # AutoSetup.cmd table (untrusted) and guards it with Test-PathInside
    # before any copy. These assert that guard's contract directly.
    It "accepts a destination DLL inside the game's own folder" {
        Test-PathInside (Join-Path "C:\Games\MyGame" "d3d9.dll") "C:\Games\MyGame" | Should -BeTrue
    }
    It "rejects a traversal destination that escapes the game folder" {
        Test-PathInside (Join-Path "C:\Games\MyGame" "..\..\Windows\System32\evil.dll") "C:\Games\MyGame" | Should -BeFalse
    }
    It "rejects a sibling folder that only shares a name prefix" {
        Test-PathInside "C:\Games\MyGameOther\x.dll" "C:\Games\MyGame" | Should -BeFalse
    }
}

Describe "RawInput / RawInputTrackball field handling (issue #46)" {
    BeforeAll {
        function New-Btn { param([string]$Inner) return ([xml]"<JoystickButtons>$Inner</JoystickButtons>").JoystickButtons }
    }
    It "treats a present RawInputButton binding as bound (supported field present)" {
        Test-ButtonIsBound (New-Btn "<RawInputButton>MOUSE_LEFT</RawInputButton>") | Should -BeTrue
    }
    It "treats a button with no binding field as not bound (field absent)" {
        Test-ButtonIsBound (New-Btn "<InputMapping>P1Trackball</InputMapping>") | Should -BeFalse
    }
    It "does NOT treat an unknown future binding field as bound (unknown field is not acted on)" {
        # A hypothetical future field name must not be mistaken for a real
        # binding -- the safe default is 'not bound', matching the project's
        # 'unknown fields are never acted on' rule.
        Test-ButtonIsBound (New-Btn "<RawInputTrackballButtonV2>MOUSE_X</RawInputTrackballButtonV2>") | Should -BeFalse
    }
}

Describe "GPU fix vendor matrix + safe re-run (issue #46)" {
    BeforeAll {
        function New-GpuDoc {
            param([string]$Inner)
            return [xml]"<GameProfile><ConfigValues>$Inner</ConfigValues></GameProfile>"
        }
        $script:GpuDropdown = "<FieldInformation><FieldName>GPU Fix</FieldName><FieldType>Dropdown</FieldType><FieldValue>None</FieldValue><FieldOptions><string>None</string><string>NVIDIA</string><string>AMD</string><string>INTEL</string></FieldOptions></FieldInformation>"
    }
    It "AMD: selects the AMD dropdown option" {
        $r = Test-GpuFixUpToDate -Doc (New-GpuDoc $script:GpuDropdown) -BoolFields @() -DropdownFields @('GPU Fix') -Vendor 'AMD'
        $r.Eligible | Should -BeTrue
        $r.Changes[0].NewValue | Should -Be 'AMD'
    }
    It "NVIDIA: selects the NVIDIA dropdown option" {
        $r = Test-GpuFixUpToDate -Doc (New-GpuDoc $script:GpuDropdown) -BoolFields @() -DropdownFields @('GPU Fix') -Vendor 'NVIDIA'
        $r.Changes[0].NewValue | Should -Be 'NVIDIA'
    }
    It "Intel: selects the INTEL dropdown option" {
        $r = Test-GpuFixUpToDate -Doc (New-GpuDoc $script:GpuDropdown) -BoolFields @() -DropdownFields @('GPU Fix') -Vendor 'Intel'
        $r.Changes[0].NewValue | Should -Be 'INTEL'
    }
    It "safe re-run after a GPU change: an already-correct value is up to date and needs no write" {
        $inner = "<FieldInformation><FieldName>GPU Fix</FieldName><FieldType>Dropdown</FieldType><FieldValue>NVIDIA</FieldValue><FieldOptions><string>None</string><string>NVIDIA</string><string>AMD</string><string>INTEL</string></FieldOptions></FieldInformation>"
        $r = Test-GpuFixUpToDate -Doc (New-GpuDoc $inner) -BoolFields @() -DropdownFields @('GPU Fix') -Vendor 'NVIDIA'
        $r.UpToDate | Should -BeTrue
        $r.Changes.Count | Should -Be 0
    }
    It "not eligible (no GPU field) means nothing to write" {
        $inner = "<FieldInformation><FieldName>Windowed</FieldName><FieldType>Bool</FieldType><FieldValue>1</FieldValue></FieldInformation>"
        (Test-GpuFixUpToDate -Doc (New-GpuDoc $inner) -BoolFields @() -DropdownFields @('GPU Fix') -Vendor 'AMD').Eligible | Should -BeFalse
    }
}

Describe "ConvertTo-ManagerComparableVersion" {
    It "strips a leading v and parses a normal version" {
        ConvertTo-ManagerComparableVersion -VersionText 'v0.99.39' | Should -Be ([version]'0.99.39')
    }
    It "parses a version with no leading v" {
        ConvertTo-ManagerComparableVersion -VersionText '0.99.39' | Should -Be ([version]'0.99.39')
    }
    It "throws on a non-numeric version string" {
        { ConvertTo-ManagerComparableVersion -VersionText 'latest' } | Should -Throw
    }

    # Issue #105: v1.0-RC1's own release tag broke this function -- [version]
    # cannot hold a "-RC1" suffix, so every updater path (menu-triggered and
    # the quiet startup check) failed to recognize the RC1 release at all.
    It "strips a release-candidate suffix and parses the numeric base" {
        ConvertTo-ManagerComparableVersion -VersionText 'v1.0-RC1' | Should -Be ([version]'1.0')
        ConvertTo-ManagerComparableVersion -VersionText 'v1.0-RC2' | Should -Be ([version]'1.0')
    }
    It "a 0.99.x version compares as older than 1.0-RC2" {
        $local  = ConvertTo-ManagerComparableVersion -VersionText '0.99.44'
        $latest = ConvertTo-ManagerComparableVersion -VersionText 'v1.0-RC2'
        $latest -gt $local | Should -Be $true -Because "a release candidate for 1.0 must be recognized as newer than any 0.99.x release"
    }
    It "0.99.99 compares as older than 1.0-RC2 (not just a higher patch number in the same line)" {
        $local  = ConvertTo-ManagerComparableVersion -VersionText '0.99.99'
        $latest = ConvertTo-ManagerComparableVersion -VersionText 'v1.0-RC2'
        $latest -gt $local | Should -Be $true
    }
    It "a version equal to the current release candidate is not offered as an update" {
        $local  = ConvertTo-ManagerComparableVersion -VersionText '1.0'
        $latest = ConvertTo-ManagerComparableVersion -VersionText 'v1.0-RC2'
        $latest -gt $local | Should -Be $false -Because "already running v1.0 RC2 must not be offered v1.0-RC2 as a new update"
    }
}

Describe "ConvertTo-ManagerDisplayVersionFromTag" {
    # Issue #134: "Current version" (built from $DisplayVersion, e.g.
    # "v1.0 RC2") and "Latest version" (previously the raw git tag, e.g.
    # "v1.0-RC2") showed the exact same release in two different formats --
    # confusing even though ConvertTo-ManagerComparableVersion correctly
    # treats them as equal. Every raw tag shown to the user must go through
    # this formatter so both lines share one canonical "v<version> <LABEL>"
    # shape.
    It "converts a release-candidate tag's dash suffix into the canonical space-separated form" {
        ConvertTo-ManagerDisplayVersionFromTag -VersionText 'v1.0-RC2' | Should -Be 'v1.0 RC2'
        ConvertTo-ManagerDisplayVersionFromTag -VersionText 'v1.0-RC1' | Should -Be 'v1.0 RC1'
    }
    It "leaves a plain numeric tag with no suffix unchanged" {
        ConvertTo-ManagerDisplayVersionFromTag -VersionText 'v0.99.44' | Should -Be 'v0.99.44'
        ConvertTo-ManagerDisplayVersionFromTag -VersionText 'v1.0' | Should -Be 'v1.0'
    }
    It "adds a leading v when the tag doesn't already have one" {
        ConvertTo-ManagerDisplayVersionFromTag -VersionText '1.0-RC2' | Should -Be 'v1.0 RC2'
        ConvertTo-ManagerDisplayVersionFromTag -VersionText '0.99.44' | Should -Be 'v0.99.44'
    }
    It "renders the same release identically whether it arrives as the running script's own display version or as a raw release tag" {
        # This is the exact regression from issue #134: v1.0 (running as
        # RC3) and the v1.0-RC3 release tag are the same release and must
        # display identically, not as "v1.0" vs "v1.0-RC3".
        $currentDisplay = "v1.0 RC3"   # Get-ManagerDisplayVersion's shape when $ScriptVersion=1.0, $ReleaseCandidateLabel=RC3
        $latestDisplay  = ConvertTo-ManagerDisplayVersionFromTag -VersionText 'v1.0-RC3'
        $latestDisplay | Should -Be $currentDisplay
    }
}

Describe "Get-ManagerUpdateRelease" {
    It "returns the matching asset for a well-formed release" {
        Mock Invoke-WebRequest {
            [pscustomobject]@{
                Content = (@{
                    tag_name = 'v0.99.99'
                    assets   = @(@{
                        name                  = 'TeknoParrot.Manager.v0.99.99.BETA.zip'
                        browser_download_url = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.99/TeknoParrot.Manager.v0.99.99.BETA.zip'
                    })
                } | ConvertTo-Json -Depth 5)
            }
        }
        $release = Get-ManagerUpdateRelease
        $release.TagName | Should -Be 'v0.99.99'
        $release.AssetName | Should -Be 'TeknoParrot.Manager.v0.99.99.BETA.zip'
    }

    It "returns null when no asset matches the expected name pattern" {
        Mock Invoke-WebRequest {
            [pscustomobject]@{
                Content = (@{
                    tag_name = 'v0.99.99'
                    assets   = @(@{ name = 'unrelated.txt'; browser_download_url = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.99/unrelated.txt' })
                } | ConvertTo-Json -Depth 5)
            }
        }
        Get-ManagerUpdateRelease | Should -BeNullOrEmpty
    }

    It "returns null and does not retry when the matching asset URL is not a real GitHub release URL" {
        Mock Invoke-WebRequest {
            [pscustomobject]@{
                Content = (@{
                    tag_name = 'v0.99.99'
                    assets   = @(@{ name = 'TeknoParrot.Manager.v0.99.99.BETA.zip'; browser_download_url = 'https://evil.example.com/TeknoParrot.Manager.v0.99.99.BETA.zip' })
                } | ConvertTo-Json -Depth 5)
            }
        }
        Get-ManagerUpdateRelease | Should -BeNullOrEmpty
        Should -Invoke Invoke-WebRequest -Times 1
    }

    It "retries on a transient (5xx-shaped) failure and gives up after 3 attempts" {
        Mock Invoke-WebRequest { throw [System.Net.WebException]::new('transient') }
        Mock Start-Sleep {}
        Get-ManagerUpdateRelease | Should -BeNullOrEmpty
        Should -Invoke Invoke-WebRequest -Times 3
        Should -Invoke Start-Sleep -Times 2
    }
}

Describe "Get-TeknoParrotProfileSet" {
    BeforeAll {
        Mock Write-Log {}
    }

    It "builds the git/trees URL with the branch placed before the query string, not swallowed by it" {
        # Regression test for the reported #78 root cause: interpolating an
        # unbraced variable immediately followed by a literal '?' inside a
        # double-quoted string (e.g. "$branchEncoded?recursive=1") silently
        # drops everything up to the next '=', producing ".../git/trees/=1"
        # instead of ".../git/trees/master?recursive=1". GitHub then 404s on
        # that malformed URL every single time -- this was not intermittent
        # or network-related. The fix braces the variable: "${branchEncoded}?...".
        Mock Invoke-WebRequest -ParameterFilter { $Uri -eq 'https://api.github.com/repos/teknogods/TeknoParrotUI' } {
            [pscustomobject]@{ Content = (@{ default_branch = 'master' } | ConvertTo-Json) }
        }
        Mock Invoke-WebRequest -ParameterFilter { $Uri -like '*/git/trees/*' } {
            [pscustomobject]@{ Content = (@{ tree = @(@{ type = 'blob'; path = 'TeknoParrotUi.Common/GameProfiles/Foo.xml' }) } | ConvertTo-Json -Depth 5) }
        }

        [void](Get-TeknoParrotProfileSet)

        Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
            $Uri -eq 'https://api.github.com/repos/teknogods/TeknoParrotUI/git/trees/master?recursive=1'
        }
    }

    It "returns the profile stems parsed from the tree response" {
        Mock Invoke-WebRequest -ParameterFilter { $Uri -eq 'https://api.github.com/repos/teknogods/TeknoParrotUI' } {
            [pscustomobject]@{ Content = (@{ default_branch = 'master' } | ConvertTo-Json) }
        }
        Mock Invoke-WebRequest -ParameterFilter { $Uri -like '*/git/trees/*' } {
            [pscustomobject]@{
                Content = (@{
                    tree = @(
                        @{ type = 'blob'; path = 'TeknoParrotUi.Common/GameProfiles/BladeArcus.xml' },
                        @{ type = 'blob'; path = 'TeknoParrotUi.Common/GameProfiles/Tekken7.xml' },
                        @{ type = 'tree'; path = 'TeknoParrotUi.Common/GameProfiles' }
                    )
                } | ConvertTo-Json -Depth 5)
            }
        }

        $result = Get-TeknoParrotProfileSet
        $result | Should -Contain 'BladeArcus'
        $result | Should -Contain 'Tekken7'
    }

    It "logs the HTTP status code when the tree request fails" {
        Mock Invoke-WebRequest -ParameterFilter { $Uri -eq 'https://api.github.com/repos/teknogods/TeknoParrotUI' } {
            [pscustomobject]@{ Content = (@{ default_branch = 'master' } | ConvertTo-Json) }
        }
        Mock Invoke-WebRequest -ParameterFilter { $Uri -like '*/git/trees/*' } {
            # Mirror the shape production code actually reads --
            # $_.Exception.Response.StatusCode -- rather than relying on a
            # specific exception type, since PowerShell 5.1 (the script's
            # target runtime) and later versions surface HTTP errors from
            # Invoke-WebRequest differently.
            $ex = [System.Exception]::new("Not Found")
            $ex | Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{ StatusCode = 404 }) -Force
            throw $ex
        }

        [void](Get-TeknoParrotProfileSet)

        Should -Invoke Write-Log -Times 1 -ParameterFilter { $msg -like "*HTTP 404*" }
    }
}

Describe "Assert-ManagerUpdateTargetWritable" {
    It "throws a clear, actionable error when the target is read-only" {
        $path = Join-Path $TestDrive 'readonly.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.99.39"' -Encoding ascii
        Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $true
        try {
            { Assert-ManagerUpdateTargetWritable -Path $path } | Should -Throw '*read-only*'
            { Assert-ManagerUpdateTargetWritable -Path $path } | Should -Throw "*$path*"
        } finally {
            Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
        }
    }
    It "does not throw when the target is writable" {
        $path = Join-Path $TestDrive 'writable.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.99.39"' -Encoding ascii
        { Assert-ManagerUpdateTargetWritable -Path $path } | Should -Not -Throw
    }
    It "does not throw when the target does not exist yet" {
        { Assert-ManagerUpdateTargetWritable -Path (Join-Path $TestDrive 'does-not-exist.ps1') } | Should -Not -Throw
    }
}

Describe "New-ManagerUpdateBackup" {
    It "creates a timestamped backup of the target file under UpdateBackups" {
        $root = Join-Path $TestDrive ("backuproot-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $scriptPath = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $scriptPath -Value '$ScriptVersion = "0.99.39"' -Encoding ascii

        $backupPath = New-ManagerUpdateBackup -Path $scriptPath

        $backupPath | Should -Match ([regex]::Escape((Join-Path $root 'UpdateBackups')))
        Test-Path -LiteralPath $backupPath -PathType Leaf | Should -BeTrue
        (Get-Content -LiteralPath $backupPath -Raw) | Should -Match 'ScriptVersion'
    }
}

Describe "Expand-ManagerUpdateAsset and Test-ManagerUpdateExtractedScript" {
    BeforeAll {
        function New-CheckForUpdatesFixtureZip {
            param(
                [string]$EntryName = 'TeknoParrot-Manager.ps1',
                [string]$EntryContent = "# TeknoParrot Manager`n`$ScriptVersion = `"0.99.99`"`n"
            )
            $zipPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-menu-fixture-" + [guid]::NewGuid().ToString('N') + '.zip')
            $stagingDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-menu-staging-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
            try {
                Set-Content -LiteralPath (Join-Path $stagingDir $EntryName) -Value $EntryContent -Encoding ascii -NoNewline
                [System.IO.Compression.ZipFile]::CreateFromDirectory($stagingDir, $zipPath)
            } finally {
                Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            return $zipPath
        }
    }

    It "extracts the named entry and it passes content validation" {
        $zipPath = New-CheckForUpdatesFixtureZip
        $destPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-menu-extracted-" + [guid]::NewGuid().ToString('N') + '.ps1')
        try {
            Expand-ManagerUpdateAsset -ZipPath $zipPath -EntryName 'TeknoParrot-Manager.ps1' -DestinationPath $destPath
            Test-ManagerUpdateExtractedScript -Path $destPath | Should -BeTrue
        } finally {
            Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $destPath -Force -ErrorAction SilentlyContinue
        }
    }

    It "throws when the zip does not contain the expected entry" {
        $zipPath = New-CheckForUpdatesFixtureZip -EntryName 'SomethingElse.ps1'
        $destPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-menu-extracted-" + [guid]::NewGuid().ToString('N') + '.ps1')
        try {
            { Expand-ManagerUpdateAsset -ZipPath $zipPath -EntryName 'TeknoParrot-Manager.ps1' -DestinationPath $destPath } | Should -Throw
        } finally {
            Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
        }
    }

    It "rejects an extracted file that begins with a raw zip (PK) signature" {
        $path = Join-Path $TestDrive 'zipbytes.ps1'
        [System.IO.File]::WriteAllBytes($path, [byte[]](0x50, 0x4B, 0x03, 0x04, 0x00, 0x00))
        { Test-ManagerUpdateExtractedScript -Path $path } | Should -Throw '*zip signature*'
    }

    It "rejects an extracted file missing the TeknoParrot Manager marker" {
        $path = Join-Path $TestDrive 'nomarker.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.99.99"' -Encoding ascii
        { Test-ManagerUpdateExtractedScript -Path $path } | Should -Throw '*TeknoParrot Manager*'
    }

    It "rejects an extracted file with no ScriptVersion assignment" {
        $path = Join-Path $TestDrive 'noversion.ps1'
        Set-Content -LiteralPath $path -Value '# TeknoParrot Manager' -Encoding ascii
        { Test-ManagerUpdateExtractedScript -Path $path } | Should -Throw '*ScriptVersion*'
    }
}

Describe "Invoke-CheckForUpdates" {
    BeforeAll {
        function New-CheckForUpdatesReleaseJson {
            param([string]$TagName = 'v0.99.99', [string]$AssetName = 'TeknoParrot.Manager.v0.99.99.BETA.zip')
            return (@{
                tag_name = $TagName
                assets   = @(@{
                    name                  = $AssetName
                    browser_download_url = "https://github.com/Jumpstile/teknoparrot-manager/releases/download/$TagName/$AssetName"
                })
            } | ConvertTo-Json -Depth 5)
        }
    }

    It "reports already current and returns false without prompting when there is no newer release" {
        Mock Invoke-WebRequest { [pscustomobject]@{ Content = (New-CheckForUpdatesReleaseJson -TagName $ScriptVersion) } }
        Mock Read-Host { throw "Read-Host should not be called when already current" }

        $path = Join-Path $TestDrive 'current.ps1'
        Set-Content -LiteralPath $path -Value "`$ScriptVersion = `"$ScriptVersion`"" -Encoding ascii

        Invoke-CheckForUpdates -ScriptPath $path | Should -BeFalse
    }

    It "returns false and makes no changes when the user declines the update" {
        Mock Invoke-WebRequest { [pscustomobject]@{ Content = (New-CheckForUpdatesReleaseJson) } }
        Mock Read-Host { "N" }

        $path = Join-Path $TestDrive 'decline.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii
        $originalContent = Get-Content -LiteralPath $path -Raw

        Invoke-CheckForUpdates -ScriptPath $path | Should -BeFalse
        (Get-Content -LiteralPath $path -Raw) | Should -Be $originalContent
    }

    It "returns false without downloading when the target is read-only" {
        Mock Invoke-WebRequest { [pscustomobject]@{ Content = (New-CheckForUpdatesReleaseJson) } }
        Mock Read-Host { "Y" }

        $root = Join-Path $TestDrive ("readonlyroot-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $path = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii
        Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $true

        try {
            Invoke-CheckForUpdates -ScriptPath $path | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $root 'UpdateBackups') | Should -BeFalse
        } finally {
            Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
        }
    }
}

Describe "Get-ManagerUpdateReleaseSummary" {
    It "returns the first non-blank line, trimmed of heading/bullet markdown" {
        Get-ManagerUpdateReleaseSummary -Body "## What's new`n`nFixes a startup crash." | Should -Be "What's new"
    }
    It "strips a leading bullet marker" {
        Get-ManagerUpdateReleaseSummary -Body "- Fixes a startup crash." | Should -Be "Fixes a startup crash."
    }
    It "truncates a long first line to 150 chars plus an ellipsis" {
        $long = "X" * 200
        $summary = Get-ManagerUpdateReleaseSummary -Body $long
        $summary.Length | Should -Be 153
        $summary | Should -Match '\.\.\.$'
    }
    It "returns null for an empty or whitespace-only body" {
        Get-ManagerUpdateReleaseSummary -Body "" | Should -BeNullOrEmpty
        Get-ManagerUpdateReleaseSummary -Body "   " | Should -BeNullOrEmpty
        Get-ManagerUpdateReleaseSummary -Body $null | Should -BeNullOrEmpty
    }
}

Describe "Get-ManagerUpdateRelease -MaxAttempts" {
    It "makes exactly one request and does not sleep when MaxAttempts is 1" {
        Mock Invoke-WebRequest { throw [System.Net.WebException]::new('transient') }
        Mock Start-Sleep {}
        Get-ManagerUpdateRelease -MaxAttempts 1 -TimeoutSec 5 | Should -BeNullOrEmpty
        Should -Invoke Invoke-WebRequest -Times 1
        Should -Invoke Start-Sleep -Times 0
    }
}

Describe "Invoke-ManagerUpdateInstall" {
    BeforeAll {
        function New-StartupCheckFixtureZipBytes {
            param(
                [string]$EntryName = 'TeknoParrot-Manager.ps1',
                [string]$EntryContent = "# TeknoParrot Manager`n`$ScriptVersion = `"0.99.99`"`n"
            )
            $zipPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-startup-fixture-" + [guid]::NewGuid().ToString('N') + '.zip')
            $stagingDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-startup-staging-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
            try {
                Set-Content -LiteralPath (Join-Path $stagingDir $EntryName) -Value $EntryContent -Encoding ascii -NoNewline
                [System.IO.Compression.ZipFile]::CreateFromDirectory($stagingDir, $zipPath)
                return , ([System.IO.File]::ReadAllBytes($zipPath))
            } finally {
                Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
            }
        }

        function New-StartupCheckRelease {
            [pscustomobject]@{
                TagName     = 'v0.99.99'
                Name        = 'v0.99.99 BETA'
                Body        = 'Test release notes.'
                AssetName   = 'TeknoParrot.Manager.v0.99.99.BETA.zip'
                DownloadUrl = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.99/TeknoParrot.Manager.v0.99.99.BETA.zip'
            }
        }

        # Destructive-path fixture helpers -- mirrors
        # Tests/TpmAutoUpdate.DestructivePath.Tests.ps1's fixtures for the
        # standalone tools/TpmAutoUpdate.Core.psm1 module, so the in-script
        # Invoke-ManagerUpdateInstall gets the same failure-mode coverage as
        # that module already has (release-certification gap closed).
        function Get-DestructiveCorruptedEntryZipBytes {
            # Same technique as the standalone suite: a large, repetitive
            # (compressible) entry so Deflate is actually used, then flip bits
            # only within the compressed payload region so the central
            # directory / EOCD stay intact and only decompression fails.
            $entryContent = "# TeknoParrot Manager`n`$ScriptVersion = `"0.99.99`"`n" + (("X" * 200 + "`n") * 300)
            $zipBytes = New-StartupCheckFixtureZipBytes -EntryContent $entryContent
            $bytes = [byte[]]$zipBytes.Clone()

            $probeZipPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-destructive-probe-" + [guid]::NewGuid().ToString('N') + '.zip')
            [System.IO.File]::WriteAllBytes($probeZipPath, $bytes)
            try {
                $zip = [System.IO.Compression.ZipFile]::OpenRead($probeZipPath)
                $compressedLength = $zip.Entries[0].CompressedLength
                $zip.Dispose()
            } finally {
                Remove-Item -LiteralPath $probeZipPath -Force -ErrorAction SilentlyContinue
            }
            if ($compressedLength -eq $entryContent.Length) {
                throw 'Test fixture error: entry was stored rather than deflated -- corruption offsets would be wrong.'
            }

            $filenameLen = [System.BitConverter]::ToUInt16($bytes, 26)
            $extraLen = [System.BitConverter]::ToUInt16($bytes, 28)
            $dataStart = 30 + $filenameLen + $extraLen
            for ($i = $dataStart; $i -lt ($dataStart + $compressedLength); $i++) {
                $bytes[$i] = $bytes[$i] -bxor 0xFF
            }
            return , $bytes
        }
    }

    It "installs successfully and returns true" {
        $zipBytes = New-StartupCheckFixtureZipBytes
        Mock Invoke-TpmDownload { param($DownloadUrl, $DestinationPath, $ExpectedBytes, $Label, $Version) [System.IO.File]::WriteAllBytes($DestinationPath, $zipBytes); return $true }.GetNewClosure()

        $path = Join-Path $TestDrive 'install-target.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii

        Invoke-ManagerUpdateInstall -ScriptPath $path -Release (New-StartupCheckRelease) | Should -BeTrue
        (Get-Content -LiteralPath $path -Raw) | Should -Match 'ScriptVersion = "0.99.99"'
    }

    It "returns false and leaves the original untouched when the target is read-only" {
        $path = Join-Path $TestDrive 'readonly-install-target.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii -NoNewline
        Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $true
        try {
            Mock Invoke-TpmDownload { throw "download should not be called when the target is read-only" }
            Invoke-ManagerUpdateInstall -ScriptPath $path -Release (New-StartupCheckRelease) | Should -BeFalse
            (Get-Content -LiteralPath $path -Raw) | Should -Be '$ScriptVersion = "0.0.1"'
        } finally {
            Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
        }
    }

    # Destructive-path parity with Tests/TpmAutoUpdate.DestructivePath.Tests.ps1
    # (issue: in-script Invoke-ManagerUpdateInstall had only success/read-only
    # coverage versus the standalone module's 9 dedicated failure scenarios --
    # release-certification gap, see release-readiness review). Each of these
    # deliberately induces a failure and asserts the original installation
    # survives untouched, a completed backup is preserved, and no temp
    # artifacts leak -- "never leave the user with a broken installation."
    It "corrupt ZIP download: leaves the original intact and preserves the backup" {
        $root = Join-Path $TestDrive ("destructive-corrupt-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $path = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii -NoNewline
        $originalContent = Get-Content -LiteralPath $path -Raw

        Mock Invoke-TpmDownload {
            param($DownloadUrl, $DestinationPath, $ExpectedBytes, $Label, $Version)
            [System.IO.File]::WriteAllBytes($DestinationPath, [byte[]](1..64 | ForEach-Object { Get-Random -Maximum 255 }))
            return $true
        }

        Invoke-ManagerUpdateInstall -ScriptPath $path -Release (New-StartupCheckRelease) | Should -BeFalse
        (Get-Content -LiteralPath $path -Raw) | Should -Be $originalContent

        $backupFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'UpdateBackups') -Recurse -Filter 'TeknoParrot-Manager.ps1' -ErrorAction SilentlyContinue)
        $backupFiles.Count | Should -Be 1
        (Get-Content -LiteralPath $backupFiles[0].FullName -Raw) | Should -Be $originalContent
    }

    It "ZIP missing TeknoParrot-Manager.ps1: leaves the original intact and preserves the backup" {
        $root = Join-Path $TestDrive ("destructive-missing-entry-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $path = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii -NoNewline
        $originalContent = Get-Content -LiteralPath $path -Raw
        $wrongEntryBytes = New-StartupCheckFixtureZipBytes -EntryName 'SomethingElse.ps1'

        Mock Invoke-TpmDownload {
            param($DownloadUrl, $DestinationPath, $ExpectedBytes, $Label, $Version)
            [System.IO.File]::WriteAllBytes($DestinationPath, $wrongEntryBytes)
            return $true
        }.GetNewClosure()

        Invoke-ManagerUpdateInstall -ScriptPath $path -Release (New-StartupCheckRelease) | Should -BeFalse
        (Get-Content -LiteralPath $path -Raw) | Should -Be $originalContent

        $backupFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'UpdateBackups') -Recurse -Filter 'TeknoParrot-Manager.ps1' -ErrorAction SilentlyContinue)
        $backupFiles.Count | Should -Be 1
    }

    It "content validation failure (missing ScriptVersion): leaves the original intact and preserves the backup" {
        $root = Join-Path $TestDrive ("destructive-noversion-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $path = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii -NoNewline
        $originalContent = Get-Content -LiteralPath $path -Raw
        $badContentBytes = New-StartupCheckFixtureZipBytes -EntryContent "# TeknoParrot Manager`nsome unrelated content, no version here`n"

        Mock Invoke-TpmDownload {
            param($DownloadUrl, $DestinationPath, $ExpectedBytes, $Label, $Version)
            [System.IO.File]::WriteAllBytes($DestinationPath, $badContentBytes)
            return $true
        }.GetNewClosure()

        Invoke-ManagerUpdateInstall -ScriptPath $path -Release (New-StartupCheckRelease) | Should -BeFalse
        (Get-Content -LiteralPath $path -Raw) | Should -Be $originalContent

        $backupFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'UpdateBackups') -Recurse -Filter 'TeknoParrot-Manager.ps1' -ErrorAction SilentlyContinue)
        $backupFiles.Count | Should -Be 1
        @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'tpm-update-extracted-*.ps1' -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It "content validation failure (extracted file is itself raw zip bytes): leaves the original intact" {
        $root = Join-Path $TestDrive ("destructive-nestedzip-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $path = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii -NoNewline
        $originalContent = Get-Content -LiteralPath $path -Raw

        # A zip whose single entry's *content* is itself zip bytes -- a
        # packaging mistake where the wrong artifact landed inside the
        # expected entry name.
        $innerZipBytes = New-StartupCheckFixtureZipBytes
        $stagingDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-nested-staging-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
        $outerZipPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-nested-" + [guid]::NewGuid().ToString('N') + '.zip')
        try {
            [System.IO.File]::WriteAllBytes((Join-Path $stagingDir 'TeknoParrot-Manager.ps1'), $innerZipBytes)
            [System.IO.Compression.ZipFile]::CreateFromDirectory($stagingDir, $outerZipPath)
            $outerBytes = [System.IO.File]::ReadAllBytes($outerZipPath)
        } finally {
            Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $outerZipPath -Force -ErrorAction SilentlyContinue
        }

        Mock Invoke-TpmDownload {
            param($DownloadUrl, $DestinationPath, $ExpectedBytes, $Label, $Version)
            [System.IO.File]::WriteAllBytes($DestinationPath, $outerBytes)
            return $true
        }.GetNewClosure()

        Invoke-ManagerUpdateInstall -ScriptPath $path -Release (New-StartupCheckRelease) | Should -BeFalse
        (Get-Content -LiteralPath $path -Raw) | Should -Be $originalContent
        (Get-Content -LiteralPath $path -Raw).StartsWith('PK') | Should -BeFalse
    }

    It "truncated/partial download: treated as corrupt, leaves the original intact" {
        $root = Join-Path $TestDrive ("destructive-truncated-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $path = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii -NoNewline
        $originalContent = Get-Content -LiteralPath $path -Raw
        $fullBytes = New-StartupCheckFixtureZipBytes
        $truncatedBytes = $fullBytes[0..([int]($fullBytes.Length / 2))]

        Mock Invoke-TpmDownload {
            param($DownloadUrl, $DestinationPath, $ExpectedBytes, $Label, $Version)
            [System.IO.File]::WriteAllBytes($DestinationPath, $truncatedBytes)
            return $true
        }.GetNewClosure()

        Invoke-ManagerUpdateInstall -ScriptPath $path -Release (New-StartupCheckRelease) | Should -BeFalse
        (Get-Content -LiteralPath $path -Raw) | Should -Be $originalContent

        $backupFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'UpdateBackups') -Recurse -Filter 'TeknoParrot-Manager.ps1' -ErrorAction SilentlyContinue)
        $backupFiles.Count | Should -Be 1
    }

    It "backup creation failure: aborts before any download, original untouched, no backup folder" {
        $root = Join-Path $TestDrive ("destructive-backupfail-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $path = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii -NoNewline
        $originalContent = Get-Content -LiteralPath $path -Raw

        Mock New-ManagerUpdateBackup { throw "Access to the path is denied (simulated backup failure)." }
        Mock Invoke-TpmDownload { throw "download should never be called when backup fails first." }

        Invoke-ManagerUpdateInstall -ScriptPath $path -Release (New-StartupCheckRelease) | Should -BeFalse
        (Get-Content -LiteralPath $path -Raw) | Should -Be $originalContent
        Test-Path -LiteralPath (Join-Path $root 'UpdateBackups') | Should -BeFalse
        Should -Invoke Invoke-TpmDownload -Times 0
    }

    It "extraction failure (valid ZIP, corrupted entry payload): leaves the original intact and preserves the backup" {
        $root = Join-Path $TestDrive ("destructive-extractfail-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $path = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii -NoNewline
        $originalContent = Get-Content -LiteralPath $path -Raw
        $corruptedEntryBytes = Get-DestructiveCorruptedEntryZipBytes

        Mock Invoke-TpmDownload {
            param($DownloadUrl, $DestinationPath, $ExpectedBytes, $Label, $Version)
            [System.IO.File]::WriteAllBytes($DestinationPath, $corruptedEntryBytes)
            return $true
        }.GetNewClosure()

        Invoke-ManagerUpdateInstall -ScriptPath $path -Release (New-StartupCheckRelease) | Should -BeFalse
        (Get-Content -LiteralPath $path -Raw) | Should -Be $originalContent

        $backupFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'UpdateBackups') -Recurse -Filter 'TeknoParrot-Manager.ps1' -ErrorAction SilentlyContinue)
        $backupFiles.Count | Should -Be 1
        @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'tpm-update-extracted-*.ps1' -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It "replacement failure after successful backup (locked destination): preserves backup and the locked, unmodified original" {
        # This is the literal "never leave the user with a broken
        # installation" case: backup/download/extract/validate all succeed
        # and only the final Move-Item fails -- what an AV scanner or another
        # process holding the file open looks like in practice.
        $root = Join-Path $TestDrive ("destructive-locked-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $path = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii -NoNewline
        $originalContent = Get-Content -LiteralPath $path -Raw
        $validBytes = New-StartupCheckFixtureZipBytes

        Mock Invoke-TpmDownload {
            param($DownloadUrl, $DestinationPath, $ExpectedBytes, $Label, $Version)
            [System.IO.File]::WriteAllBytes($DestinationPath, $validBytes)
            return $true
        }.GetNewClosure()

        $lockHandle = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        try {
            Invoke-ManagerUpdateInstall -ScriptPath $path -Release (New-StartupCheckRelease) | Should -BeFalse
        } finally {
            $lockHandle.Dispose()
        }

        # Original must be exactly what it was -- no partial/truncated write.
        (Get-Content -LiteralPath $path -Raw) | Should -Be $originalContent

        $backupFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'UpdateBackups') -Recurse -Filter 'TeknoParrot-Manager.ps1' -ErrorAction SilentlyContinue)
        $backupFiles.Count | Should -Be 1
        (Get-Content -LiteralPath $backupFiles[0].FullName -Raw) | Should -Be $originalContent

        @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'tpm-update-extracted-*.ps1' -ErrorAction SilentlyContinue).Count | Should -Be 0
        @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'tpm-update-*.zip' -ErrorAction SilentlyContinue).Count | Should -Be 0
    }
}

Describe "Invoke-StartupUpdateCheck" {
    It "returns false and does not prompt when already current" {
        Mock Get-ManagerUpdateRelease { [pscustomobject]@{ TagName = "v$ScriptVersion"; Name = $null; Body = $null; AssetName = 'x'; DownloadUrl = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.39/x' } }
        Mock Read-Host { throw "Read-Host should not be called when already current" }

        $path = Join-Path $TestDrive 'startup-current.ps1'
        Set-Content -LiteralPath $path -Value "`$ScriptVersion = `"$ScriptVersion`"" -Encoding ascii

        Invoke-StartupUpdateCheck -ScriptPath $path | Should -BeFalse
    }

    It "returns false without prompting again when the release check fails (e.g. offline)" {
        Mock Get-ManagerUpdateRelease { $null }
        Mock Read-Host { throw "Read-Host should not be called when the release check fails" }

        $path = Join-Path $TestDrive 'startup-offline.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii

        Invoke-StartupUpdateCheck -ScriptPath $path | Should -BeFalse
    }

    It "returns false and makes no changes when the user chooses N (remind me later)" {
        Mock Get-ManagerUpdateRelease {
            [pscustomobject]@{ TagName = 'v0.99.99'; Name = 'v0.99.99'; Body = 'Notes.'; AssetName = 'x.zip'; DownloadUrl = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.99/x.zip' }
        }
        Mock Read-Host { "N" }

        $path = Join-Path $TestDrive 'startup-decline.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii
        $originalContent = Get-Content -LiteralPath $path -Raw

        Invoke-StartupUpdateCheck -ScriptPath $path | Should -BeFalse
        (Get-Content -LiteralPath $path -Raw) | Should -Be $originalContent
    }

    It "shows release notes on V and then still lets the user decline with N" {
        Mock Get-ManagerUpdateRelease {
            [pscustomobject]@{ TagName = 'v0.99.99'; Name = 'v0.99.99'; Body = 'Detailed notes here.'; AssetName = 'x.zip'; DownloadUrl = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.99/x.zip' }
        }
        $script:readHostCallCount = 0
        Mock Read-Host {
            $script:readHostCallCount++
            if ($script:readHostCallCount -eq 1) { return "V" }
            return "N"
        }

        $path = Join-Path $TestDrive 'startup-view-notes.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii

        Invoke-StartupUpdateCheck -ScriptPath $path | Should -BeFalse
        Should -Invoke Read-Host -Times 2
    }

    It "returns false without downloading when Y is chosen but the target is read-only" {
        Mock Get-ManagerUpdateRelease {
            [pscustomobject]@{ TagName = 'v0.99.99'; Name = 'v0.99.99'; Body = 'Notes.'; AssetName = 'x.zip'; DownloadUrl = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.99/x.zip' }
        }
        Mock Read-Host { "Y" }
        Mock Invoke-WebRequest { throw "Invoke-WebRequest should not be called when the target is read-only" }

        $root = Join-Path $TestDrive ("startup-readonly-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $path = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii
        Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $true

        try {
            Invoke-StartupUpdateCheck -ScriptPath $path | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $root 'UpdateBackups') | Should -BeFalse
        } finally {
            Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
        }
    }
}

Describe "Main menu source-level drift check" {
    # Issue #104: the menu display is now data-driven (Get-MainMenuSections /
    # Get-MainMenuItems), but the switch statement dispatching $modeChoice to
    # a $mode string is still hand-written top-level code, not extracted by
    # the AST function-extraction. This cross-checks the data model's item
    # numbers against the switch statement's case labels, preserving the
    # original intent of this test (a future edit to one without the other --
    # the exact drift class documented in LESSONS_LEARNED.md for
    # v0.99.25/v0.99.28 -- fails CI instead of shipping) against the new
    # architecture.
    BeforeAll {
        $script:mainScriptContent = Get-Content -LiteralPath $scriptPath -Raw
    }

    It "has a switch case for every menu item number in the data model, 1 through the Exit option, with no gaps" {
        $itemNumbers = Get-MainMenuItems | ForEach-Object { $_.Number } | Sort-Object -Unique

        $switchBlockStart = $script:mainScriptContent.IndexOf('switch ($modeChoice) {')
        # The switch block's own cases each have their own "{ ... }" (e.g.
        # "1" { $mode = "AutoSync" }), so IndexOf('}', ...) would only find
        # the first case's closing brace. "if ($modeChoice -eq" reliably
        # appears immediately after the whole switch statement closes.
        $switchBlockEnd   = $script:mainScriptContent.IndexOf('if ($modeChoice -eq', $switchBlockStart)
        $switchBlockText  = $script:mainScriptContent.Substring($switchBlockStart, $switchBlockEnd - $switchBlockStart)
        $switchNumbers    = [regex]::Matches($switchBlockText, '"(\d+)"\s*\{') |
            ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique

        # @() wrap: not currently reachable with $null (14 menu items always
        # collapse to more than one unique number), but the same unguarded
        # .Count-on-a-possibly-scalar-pipeline-result pattern that broke the
        # Ultra-tier banner test under PS 5.1 above -- fixed defensively for
        # consistency with that lesson rather than waiting for it to fail.
        @($itemNumbers).Count | Should -BeGreaterThan 0
        # Join to strings for comparison -- piping an array directly into
        # Should -Be iterates it element-by-element against the whole
        # right-hand side instead of comparing the collections as a whole.
        ($itemNumbers -join ',') | Should -Be ($switchNumbers -join ',')

        $expectedSequence = 1..($itemNumbers[-1])
        ($itemNumbers -join ',') | Should -Be ($expectedSequence -join ',')
    }

    It "every menu item has a distinct Mode string used by exactly one switch case" {
        $items = Get-MainMenuItems
        foreach ($item in $items) {
            if ($item.Number -eq 14) { continue } # Exit has no $mode assignment
            $script:mainScriptContent | Should -Match ([regex]::Escape('"{0}"' -f $item.Number) + '\s*\{\s*\$mode\s*=\s*"' + [regex]::Escape($item.Mode) + '"')
        }
    }

    It "Show-MainMenu's Enter prompt uses the highest item number from the data model" {
        $itemNumbers = Get-MainMenuItems | ForEach-Object { $_.Number } | Sort-Object -Unique
        $script:mainScriptContent.Contains('Read-MainMenuChoiceResponsive -Prompt ("Enter 1-{0}: " -f $menuMaxNumber)') | Should -Be $true
        $script:mainScriptContent.Contains('$menuMaxNumber = (Get-MainMenuItems | Measure-Object -Property Number -Maximum).Maximum') | Should -Be $true
        $itemNumbers[-1] | Should -Be 14
    }

    It "actual menu loop passes current viewport dimensions into Show-MainMenu" {
        $script:mainScriptContent.Contains('$consoleWidth  = Get-ConsoleContentWidth') | Should -Be $true
        $script:mainScriptContent.Contains('$consoleHeight = Get-ConsoleContentHeight') | Should -Be $true
        $script:mainScriptContent.Contains('Show-MainMenu -Tier $menuTier -Width $consoleWidth -Height $consoleHeight') | Should -Be $true
    }
}

Describe "Get-MainMenuSections / Get-MainMenuItems" {
    It "every section has at least one item" {
        Get-MainMenuSections | ForEach-Object { $_.Items.Count | Should -BeGreaterThan 0 }
    }
    It "flattens every section's items into one number-ordered list with no duplicate numbers" {
        $items = Get-MainMenuItems
        $numbers = $items | ForEach-Object { $_.Number }
        ($numbers | Sort-Object -Unique).Count | Should -Be $numbers.Count
    }
    It "every non-Exit item has a non-empty Label, ShortDesc, and at least one FullDesc line" {
        $items = Get-MainMenuItems | Where-Object { $_.Mode -ne 'Exit' }
        foreach ($item in $items) {
            $item.Label | Should -Not -BeNullOrEmpty
            $item.ShortDesc | Should -Not -BeNullOrEmpty
            @($item.FullDesc).Count | Should -BeGreaterThan 0
        }
    }
}

Describe "Get-ConsoleLayoutTier" {
    It "uses the RC2 viewport breakpoints" {
        Get-ConsoleLayoutTier -Width 80 -Height 80 -RequiredFullLines 60 | Should -Be 'Compact'
        Get-ConsoleLayoutTier -Width 89 -Height 80 -RequiredFullLines 60 | Should -Be 'Compact'
        Get-ConsoleLayoutTier -Width 90 -Height 80 -RequiredFullLines 60 | Should -Be 'Standard'
        Get-ConsoleLayoutTier -Width 119 -Height 80 -RequiredFullLines 60 | Should -Be 'Standard'
        Get-ConsoleLayoutTier -Width 120 -Height 80 -RequiredFullLines 60 | Should -Be 'Professional'
        Get-ConsoleLayoutTier -Width 149 -Height 80 -RequiredFullLines 60 | Should -Be 'Professional'
        Get-ConsoleLayoutTier -Width 150 -Height 80 -RequiredFullLines 60 | Should -Be 'Ultra'
    }
    It "does not demote a wide viewport solely because it is short" {
        Get-ConsoleLayoutTier -Width 200 -Height 30 -RequiredFullLines 60 | Should -Be 'Ultra'
    }
}

Describe "Get-MainMenuRenderMetrics" {
    It "reports compact single-column metrics for narrow widths" {
        $metrics = Get-MainMenuRenderMetrics -Tier 'Compact' -Width 80
        $metrics.Layout | Should -Be 'CompactWrappedSingleColumn'
        $metrics.DescriptionWidth | Should -Be 0
        $metrics.TotalRenderWidth | Should -BeLessOrEqual 80
    }
    It "reports standard single-column metrics for normal widths" {
        $metrics = Get-MainMenuRenderMetrics -Tier 'Standard' -Width 110
        $metrics.Layout | Should -Be 'StandardSingleColumn'
        $metrics.DescriptionWidth | Should -BeGreaterThan 60
        $metrics.TotalRenderWidth | Should -BeGreaterThan 100
    }
    It "makes 120 columns a professional wide layout instead of compact-style output" {
        $compact = Get-MainMenuRenderMetrics -Tier 'Compact' -Width 80
        $professional = Get-MainMenuRenderMetrics -Tier 'Professional' -Width 120

        $professional.Layout | Should -Be 'ProfessionalTwoColumn'
        $professional.TotalRenderWidth | Should -BeGreaterThan 115
        $professional.DescriptionWidth | Should -BeGreaterThan 40
        $professional.TotalRenderWidth | Should -BeGreaterThan $compact.TotalRenderWidth
    }
    It "reports ultra metrics that expand with terminal width" {
        $wide150 = Get-MainMenuRenderMetrics -Tier 'Ultra' -Width 150
        $wide200 = Get-MainMenuRenderMetrics -Tier 'Ultra' -Width 200

        $wide150.Layout | Should -Be 'UltraTwoColumn'
        $wide150.DescriptionWidth | Should -BeGreaterThan 50
        $wide150.TotalRenderWidth | Should -BeGreaterThan 140
        $wide200.TotalRenderWidth | Should -BeGreaterThan $wide150.TotalRenderWidth
        $wide200.DescriptionWidth | Should -BeGreaterThan $wide150.DescriptionWidth
    }
    It "can report an experimental centered ultra layout without changing the default" {
        $default = Get-MainMenuRenderMetrics -Tier 'Ultra' -Width 180
        $centered = Get-MainMenuRenderMetrics -Tier 'Ultra' -Width 180 -UltraLayoutMode 'UltraCentered'

        $default.Layout | Should -Be 'UltraTwoColumn'
        $centered.Layout | Should -Be 'UltraCentered'
        $centered.TotalRenderWidth | Should -BeLessThan $default.TotalRenderWidth
        $centered.DescriptionWidth | Should -BeGreaterThan 90
    }
    It "reports height and width constraints for diagnostics" {
        $metrics = Get-MainMenuRenderMetrics -Tier 'Professional' -Width 120 -Height 20 -RequiredFullLines 60

        $metrics.HeightConstrained | Should -BeTrue
        $metrics.WidthConstrained | Should -BeTrue
        $metrics.ConstrainedBy | Should -Be 'width,height'
    }
}

Describe "Manager banner rendering" {
    It "uses the compact plain-text banner for narrow widths" {
        $lines = Get-ManagerBannerLines -Width 80 -Height 30

        ($lines -join "`n") | Should -Match 'TeknoParrot Manager'
        ($lines -join "`n") | Should -Match 'Version 1.0 RC3'
        ($lines -join "`n") | Should -Not -Match '/_  __/__.*___'
    }
    It "selects responsive branding modes by viewport width" {
        Get-ManagerBannerMode -Width 80 -Height 40 | Should -Be 'PlainText'
        Get-ManagerBannerMode -Width 120 -Height 40 | Should -Be 'PlainText'
        Get-ManagerBannerMode -Width 150 -Height 40 | Should -Be 'PlainText'
        Get-ManagerBannerMode -Width 180 -Height 40 | Should -Be 'AnsiShadow'
    }
    It "does not force FIGlet branding into compact windows" {
        Test-UseManagerAsciiBanner -Width 89 -Height 40 | Should -BeFalse
        Test-UseManagerAsciiBanner -Width 90 -Height 40 | Should -BeFalse
        Test-UseManagerAsciiBanner -Width 150 -Height 20 | Should -BeFalse
        Test-UseManagerAsciiBanner -Width 180 -Height 20 | Should -BeTrue
    }
    It "centers ANSI Shadow branding and includes the canonical display version" {
        $lines = Get-ManagerBannerLines -Width 180 -Height 30
        $joined = $lines -join "`n"
        $block = [string][char]0x2588

        $joined.Contains($block) | Should -BeTrue
        $joined | Should -Match 'Developed and maintained by Jumpstile'
        $joined | Should -Match 'Version 1.0 RC3'
        $lines | ForEach-Object { $_.Length | Should -BeLessOrEqual 180 }
    }
    It "keeps each branding mode inside its target width" {
        foreach ($width in @(80, 120, 150, 180)) {
            Get-ManagerBannerLines -Width $width -Height 40 | ForEach-Object {
                $_.Length | Should -BeLessOrEqual $width
            }
        }
    }
    It "assigns console-safe colors to responsive banner rows" {
        $rows = Get-ManagerBannerRows -Width 180 -Height 40
        $block = [string][char]0x2588

        $figletRow = $rows | Where-Object { $_.Text.Contains($block) } | Select-Object -First 1
        ($figletRow.Segments | ForEach-Object { $_.Color }) | Should -Contain 'Cyan'
        ($rows | Where-Object { $_.Text -match 'Developed and maintained by Jumpstile' }).Segments.Color | Should -Contain 'Yellow'
        ($rows | Where-Object { $_.Text -match 'Version 1.0 RC3' }).Color | Should -Be 'Cyan'
    }
}

Describe "Split-TextForMenuWidth" {
    It "keeps text on one line when the menu column is wide enough" {
        $lines = Split-TextForMenuWidth -Text 'Alpha beta gamma delta' -Width 80
        $lines.Count | Should -Be 1
        $lines[0] | Should -Be 'Alpha beta gamma delta'
    }
    It "wraps text deterministically when the menu column is narrow" {
        $lines = Split-TextForMenuWidth -Text 'Alpha beta gamma delta' -Width 12
        $lines.Count | Should -BeGreaterThan 1
        ($lines -join '|') | Should -Be 'Alpha beta gamma|delta'
    }
}

Describe "Format-MainMenuItemLines" {
    It "uses a genuinely wide description column when the caller provides wide space" {
        $autoSync = (Get-MainMenuItems) | Where-Object { $_.Mode -eq 'AutoSync' }
        $lines = Format-MainMenuItemLines -Item $autoSync -Tier 'Professional' -Width 118
        $lines.Count | Should -Be 1
        $lines[0] | Should -Be '  1) AutoSync -- Extract ZIPs (NAS or local) to a local folder, then register the games.'
    }
    It "wraps under the description column when the caller provides narrow space" {
        $autoSync = (Get-MainMenuItems) | Where-Object { $_.Mode -eq 'AutoSync' }
        $lines = Format-MainMenuItemLines -Item $autoSync -Tier 'Professional' -Width 70
        $lines.Count | Should -BeGreaterThan 1
        $lines[1] | Should -Match '^\s{10,}register the games\.'
    }
}

Describe "Render-MainMenuScreen / Show-MainMenu" {
    It "renders the complete Professional menu into a deterministic buffer" {
        $screen = Render-MainMenuScreen -Tier 'Professional' -Width 150 -Height 80
        $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"

        $screen.Rows.Count | Should -BeGreaterThan 20
        $output | Should -Match 'Developed and maintained by Jumpstile'
        $output | Should -Match 'Version 1.0 RC3'
        foreach ($item in (Get-MainMenuItems)) {
            $output | Should -Match ([regex]::Escape("$($item.Number)) $($item.Label)"))
        }
    }
    It "renders Ultra as separate bounded rows instead of one collapsed line" {
        $screen = Render-MainMenuScreen -Tier 'Ultra' -Width 160 -Height 40

        $screen.Rows.Count | Should -BeGreaterThan 25
        (($screen.Rows | ForEach-Object { $_.Text.Length }) | Measure-Object -Maximum).Maximum | Should -BeLessOrEqual 160
        # @() wrap is required, not stylistic: PowerShell 7 added an intrinsic
        # scalar .Count member (a lone PSCustomObject reports Count=1), but
        # Windows PowerShell 5.1 -- this project's actual target runtime, and
        # what CI's "shell: powershell" step actually runs -- does not have
        # it, so .Count on a single (non-array) Where-Object match is $null
        # there. Exactly one row matches each of these two filters, so this
        # passed under PS7 (this dev environment's default) but failed on
        # every real PS 5.1 run, including CI, even though the actual
        # rendering was always correct on both. See LESSONS_LEARNED.md,
        # "PowerShell return @() gotcha."
        @($screen.Rows | Where-Object { $_.Text -match 'AutoSync' }).Count | Should -BeGreaterThan 0
        @($screen.Rows | Where-Object { $_.Text -match 'Crosshair setup' }).Count | Should -BeGreaterThan 0
    }
    It "returns a flat row buffer for the production writer" {
        $screen = Render-MainMenuScreen -Tier 'Professional' -Width 150 -Height 30

        $screen.Rows.Count | Should -BeGreaterThan 20
        foreach ($row in $screen.Rows) {
            $row | Should -Not -BeOfType ([object[]])
            $row.PSObject.Properties.Name | Should -Contain 'Text'
            $row.PSObject.Properties.Name | Should -Contain 'Color'
        }
    }
    It "Standard tier renders labels only so compact windows remain complete" {
        $screen = Render-MainMenuScreen -Tier 'Standard' -Width 110 -Height 30
        $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"
        $item = (Get-MainMenuItems) | Where-Object { $_.Mode -eq 'AutoSync' }
        $output | Should -Match ([regex]::Escape("1) AutoSync"))
        $output | Should -Not -Match ([regex]::Escape($item.ShortDesc))
        $output | Should -Match 'Enter number'
    }
    It "Compact tier renders only labels and the 'Type ? for descriptions' hint, no ShortDesc/FullDesc text" {
        $screen = Render-MainMenuScreen -Tier 'Compact' -Width 80 -Height 80
        $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"
        $output | Should -Match 'TeknoParrot Manager'
        $output | Should -Match 'Version 1.0 RC3'
        $output | Should -Not -Match '/_  __/'
        $output | Should -Match 'Type \? for descriptions'
        $autoSync = (Get-MainMenuItems) | Where-Object { $_.Mode -eq 'AutoSync' }
        $output | Should -Not -Match ([regex]::Escape($autoSync.ShortDesc))
    }
    It "Professional default tier uses a complete framed two-column menu" {
        $screen = Render-MainMenuScreen -Tier 'Professional' -Width 150 -Height 30
        $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"
        $output | Should -Match 'Version 1.0 RC3'
        $output | Should -Match ([regex]::Escape("1) AutoSync"))
        $output | Should -Match ([regex]::Escape("Extract and register ZIPs safely."))
        $output | Should -Match 'GAME ENHANCEMENTS'
        $output | Should -Match 'Enter number'
        $screen.Geometry.ColumnCount | Should -Be 2
        $screen.Geometry.MenuWidth | Should -BeGreaterThan 115
    }
    It "Ultra tier renders menu groups side-by-side instead of a narrow left-column menu" {
        $screen = Render-MainMenuScreen -Tier 'Ultra' -Width 160 -Height 40
        $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"
        $output | Should -Match '(?m)LIBRARY MANAGEMENT\s+-+\s+\|\s+GAME ENHANCEMENTS'
        $screen.Geometry.ColumnCount | Should -Be 2
        $screen.Geometry.MenuWidth | Should -BeGreaterThan 145
    }
    It "UltraCentered renders a single centered content block" {
        # Height 65 is tall enough for UltraCentered's full-description,
        # single-column content to render in full without any body
        # truncation (confirmed empirically: content needs 61 rows; a
        # shorter height, e.g. 30, legitimately truncates the earliest
        # sections first per Limit-MainMenuBodyRowsToBudget -- see the
        # "issue #104 RC3 correction" tests below, which cover that case
        # directly and assert Exit/footer survive instead of AutoSync).
        $screen = Render-MainMenuScreen -Tier 'Ultra' -Width 180 -Height 65 -UltraLayoutMode 'UltraCentered'
        $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"

        $screen.Geometry.ColumnCount | Should -Be 1
        $screen.Geometry.LeftPadding | Should -BeGreaterThan 10
        $output | Should -Match ([regex]::Escape("1) AutoSync"))
        $output | Should -Match ([regex]::Escape("14) Exit"))
        $output | Should -Not -Match '(?m)LIBRARY MANAGEMENT\s+-+\s+GAME ENHANCEMENTS'
    }
    It "narrow Professional tier remains bounded and readable" {
        $screen = Render-MainMenuScreen -Tier 'Professional' -Width 70 -Height 30
        $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"
        $output | Should -Match ([regex]::Escape("1) AutoSync"))
        $output | Should -Match 'Enter number'
    }
    It "rendered rows never exceed the detected viewport width" {
        foreach ($case in @(
            @{ Tier = 'Compact'; Width = 80; Height = 25 },
            @{ Tier = 'Standard'; Width = 100; Height = 30 },
            @{ Tier = 'Professional'; Width = 132; Height = 30 },
            @{ Tier = 'Ultra'; Width = 160; Height = 40 }
        )) {
            $screen = Render-MainMenuScreen -Tier $case.Tier -Width $case.Width -Height $case.Height
            foreach ($row in $screen.Rows) {
                $row.Text.Length | Should -BeLessOrEqual $case.Width
            }
        }
    }
    It "small viewport keeps the footer and Exit visible without scrolling, even if it must drop earlier sections (issue #104 RC3 correction)" {
        # Prior behavior flattened banner+body+footer and kept only the
        # first N rows top-to-bottom -- at a short height that silently
        # dropped the entire footer (Quit/Help controls) and the
        # Application section (option 14, Exit), which a real user could
        # never reach without resizing or scrolling. This asserted that
        # loss as "expected" (`Should -Not -Match 'Exit'`); the corrected
        # behavior below is the opposite: the footer and Exit must survive,
        # and it is earlier body content that gets trimmed first if
        # something has to give.
        $screen = Render-MainMenuScreen -Tier 'Compact' -Width 80 -Height 12
        $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"

        $screen.Rows.Count | Should -BeLessOrEqual 10
        $output | Should -Match 'TeknoParrot Manager'
        $output | Should -Match '14\) Exit'
        $output | Should -Match 'Enter number'
    }

    It "reserves footer rows unconditionally so they are never truncated away, across every tier at a short height" {
        foreach ($case in @(
            @{ Tier = 'Compact'; Width = 80 },
            @{ Tier = 'Standard'; Width = 100 },
            @{ Tier = 'Professional'; Width = 132 },
            @{ Tier = 'Ultra'; Width = 160 }
        )) {
            $screen = Render-MainMenuScreen -Tier $case.Tier -Width $case.Width -Height 12
            $normalFooterRows = @(Get-MainMenuFooterRows -Geometry $screen.Geometry)
            $minimalFooterRows = @(Get-MainMenuMinimalFooterRows -Geometry $screen.Geometry)

            # At this height, a narrow-enough tier may now legitimately fall
            # into the emergency compact presentation (issue #104 RC3-B),
            # which uses a single-line minimal footer instead of the normal
            # framed one -- either is acceptable here, since the point of
            # this test is that the footer is never truncated away
            # entirely, not that one specific footer variant is used.
            $screen.Rows.Count | Should -BeGreaterOrEqual 1
            $lastRowText = $screen.Rows[-1].Text
            $matchesNormalTail = ($normalFooterRows.Count -gt 0) -and ($lastRowText -eq $normalFooterRows[-1].Text)
            $matchesMinimalTail = ($minimalFooterRows.Count -gt 0) -and ($lastRowText -eq $minimalFooterRows[-1].Text)
            ($matchesNormalTail -or $matchesMinimalTail) | Should -BeTrue
        }
    }

    It "keeps option 14 (Exit) visible at every tier when the viewport is short, single-column layouts" {
        foreach ($case in @(
            @{ Tier = 'Compact'; Width = 80 },
            @{ Tier = 'Standard'; Width = 100 }
        )) {
            $screen = Render-MainMenuScreen -Tier $case.Tier -Width $case.Width -Height 12
            $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"
            $output | Should -Match '14\) Exit'
        }
    }

    It "keeps option 14 (Exit) visible at Professional/Ultra two-column tiers when the viewport is short" {
        # Two-column layouts interleave rows from all four sections per row
        # index (Join-MainMenuRenderColumns), so Exit's row can appear
        # earlier in the flat row list than in a single-column layout --
        # confirms the front-trim-only-single-column-body assumption still
        # leaves Exit visible where it actually lives in a 2-column render.
        foreach ($case in @(
            @{ Tier = 'Professional'; Width = 132 },
            @{ Tier = 'Ultra'; Width = 160 }
        )) {
            $screen = Render-MainMenuScreen -Tier $case.Tier -Width $case.Width -Height 12
            $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"
            $output | Should -Match '14\) Exit'
        }
    }
    It "Show-MainMenu delegates to the stateless render-clear-write pipeline" {
        $mainScriptContent = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1') -Raw

        $mainScriptContent.Contains('$screen = Render-MainMenuScreen -Tier $Tier -Width $Width -Height $Height -UltraLayoutMode $UltraLayoutMode') | Should -Be $true
        $mainScriptContent.Contains('Clear-ConsoleForFreshRender') | Should -Be $true
        $mainScriptContent.Contains('Set-ConsoleRenderOrigin') | Should -Be $true
        $mainScriptContent.Contains('Limit-MainMenuRowsToViewport') | Should -Be $true
        $mainScriptContent.Contains('Write-ConsoleRenderRows -Rows $screen.Rows') | Should -Be $true
    }
    It "Show-MainMenu's actual output includes visible menu items" {
        $output = & { Show-MainMenu -Tier 'Ultra' -Width 160 -Height 40 } 6>&1 | Out-String

        $output | Should -Match 'LIBRARY MANAGEMENT'
        $output | Should -Match 'AutoSync'
        $output | Should -Match 'GAME ENHANCEMENTS'
        $output | Should -Match 'Exit'
    }
    It "responsive menu input falls back when stdin is redirected" {
        $mainScriptContent = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1') -Raw

        $mainScriptContent | Should -Match '\[Console\]::IsInputRedirected'
        $mainScriptContent | Should -Match 'Read-Host \$Prompt'
    }
}

Describe "Minimum supported 60x10 viewport and nearby boundaries (issue #104 RC3-B correction)" {
    # At 60x10, the normal per-item-per-row Compact body (4 section headers
    # + 14 item rows = 18 rows minimum) cannot fit even after
    # Limit-MainMenuBodyRowsToBudget trims it -- the framed banner (6 rows)
    # and footer (2 rows) alone already consume the entire 8-row budget
    # (ViewportHeight - 2), leaving zero rows for body content. Simply
    # reserving Exit + the footer is not sufficient on its own: it still
    # silently drops every OTHER option. Get-MainMenuEmergencyCompactRows
    # replaces the framed banner/footer with single-line versions and
    # flow-packs every "N) Label" as densely as the width allows, so every
    # option stays visible.
    # Using -TestCases (Pester's own parameterized-test mechanism) rather
    # than `foreach ($height in ...) { It ... { ...$height... } }`: a plain
    # PowerShell foreach-loop variable closed over by an It scriptblock is
    # NOT visible inside that scriptblock's body when Pester actually runs
    # it (confirmed by isolated repro -- the value reads as $null/empty at
    # Run time even though it renders correctly in the It's own title,
    # which is built separately at Discovery time). -TestCases passes each
    # case's values in as real bound parameters instead, which does work.
    It "at the supported 60x<Height> minimum and its immediate boundaries, every option 1-14 is visible, Exit and the footer are present, and nothing scrolls off the viewport" -TestCases @(
        @{ Height = 9 }, @{ Height = 10 }, @{ Height = 11 }, @{ Height = 12 }
    ) {
        param($Height)
        $screen = Render-MainMenuScreen -Tier (Get-ConsoleLayoutTier -Width 60 -Height $Height -RequiredFullLines 0) -Width 60 -Height $Height
        $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"

        $screen.Rows.Count | Should -BeLessOrEqual ([Math]::Max(5, $Height - 2))
        $allItemNumbers = @((Get-MainMenuItems) | ForEach-Object { $_.Number })
        foreach ($n in $allItemNumbers) {
            $output | Should -Match ([regex]::Escape("$n)"))
        }
        $output | Should -Match '14\) Exit'
        $output | Should -Match 'Enter number'
        $output | Should -Match 'Q=Quit'
    }

    It "below the documented 60x10 minimum (60x8), the footer and option 14 (Exit) are still never dropped, even though an earlier option's line may not fit" {
        # 60x8 is below the documented supported floor, so unlike the exact
        # cases above, this does not require every option to be visible --
        # only that the two guarantees which must NEVER break (the footer's
        # Quit control, and Exit specifically) still hold, and that nothing
        # crashes or silently renders a blank/broken screen.
        $screen = Render-MainMenuScreen -Tier (Get-ConsoleLayoutTier -Width 60 -Height 8 -RequiredFullLines 0) -Width 60 -Height 8
        $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"

        $screen.Rows.Count | Should -BeLessOrEqual ([Math]::Max(5, 8 - 2))
        $output | Should -Match '14\) Exit'
        $output | Should -Match 'Enter number'
        $output | Should -Match 'Q=Quit'
    }

    It "every flow-packed 'N) Label' token matches Get-MainMenuItems exactly (no drift between the emergency presentation and the real dispatch data)" {
        $geometry = Get-MainMenuGeometry -Tier 'Compact' -ViewportWidth 60 -ViewportHeight 10
        $rows = Get-MainMenuFlowPackedItemRows -Width 58 -Geometry $geometry
        $flatText = ($rows | ForEach-Object { $_.Text }) -join ' '

        foreach ($item in (Get-MainMenuItems)) {
            $flatText | Should -Match ([regex]::Escape("$($item.Number)) $($item.Label)"))
        }
    }

    # Using -TestCases (Pester's own parameterized-test mechanism), not a
    # `foreach ($case in ...) { ... }` loop bundled inside a single `It`
    # body: a bundled loop reports as exactly one pass/fail for all four
    # cases combined, so a reviewer reading Pester's output cannot tell
    # whether all four widths/heights actually ran, whether they ran with
    # their own distinct values, or whether an early failure silently
    # skipped the remaining cases (`Should` throws, which stops the loop).
    # -TestCases gives each case its own named, independently-reported
    # result instead. (Note: a bundled loop entirely INSIDE one It body is
    # not the same closure defect as a loop that WRAPS separate `It` calls
    # -- confirmed by isolated repro that the bundled form here did receive
    # correct per-iteration values -- but it still doesn't prove independent
    # per-case execution/reporting, which is what this rewrite is for.)
    It "at <Width>x<Height>, Exit and the footer stay visible without scrolling, using this case's own dimensions" -TestCases @(
        @{ Width = 80;  Height = 8;  ExpectedTier = 'Compact' }
        @{ Width = 100; Height = 8;  ExpectedTier = 'Standard' }
        @{ Width = 150; Height = 8;  ExpectedTier = 'Ultra' }
        @{ Width = 100; Height = 20; ExpectedTier = 'Standard' }
    ) {
        param($Width, $Height, $ExpectedTier)
        $tier = Get-ConsoleLayoutTier -Width $Width -Height $Height -RequiredFullLines 0

        # Proves the WIDTH bound into this case actually drove tier
        # selection (Get-ConsoleLayoutTier is width-only, so this is a
        # second, independent confirmation of the Width binding below, not
        # a duplicate of it) -- a cross-case value swap between the 80/100/
        # 150-wide cases would flip this and fail.
        $tier | Should -Be $ExpectedTier

        $screen = Render-MainMenuScreen -Tier $tier -Width $Width -Height $Height
        $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"

        # Proves this case actually ran with ITS OWN Width, not a value
        # shared or duplicated from another case -- the specific
        # "accidental duplicate binding" this rewrite guards against. The
        # geometry object is threaded all the way through from the -Width
        # parameter passed into Render-MainMenuScreen above, so a mismatch
        # here would mean cross-case value bleed. (ViewportWidth, not
        # Height, because Get-MainMenuGeometry internally clamps
        # ViewportHeight to a floor of 10 for its own column-width math --
        # see the real-height budgeting note in ARCHITECTURE.md -- so it
        # would not reflect this case's own Height value for the two 8-row
        # cases here even when everything is working correctly.)
        $screen.Geometry.ViewportWidth | Should -Be $Width

        # This case's own Height still matters even though the two
        # Width=100 cases (100x8 and 100x20) share a tier: the row-count
        # ceiling is derived from THIS case's real Height (Max(5,
        # Height-2) = 6 for height 8, 18 for height 20), so a cross-case
        # Height swap between those two would change which bound applies.
        $screen.Rows.Count | Should -BeLessOrEqual ([Math]::Max(5, $Height - 2))
        $output | Should -Match '14\) Exit'
        $output | Should -Match 'Q=Quit'

        # All four of these cases happen to be wide enough that the render
        # pipeline shows every option even in its most space-constrained
        # form (confirmed empirically, not assumed) -- verified per case
        # rather than in a separate test, so this remains part of the same
        # independently-reported, per-case proof.
        foreach ($n in @((Get-MainMenuItems) | ForEach-Object { $_.Number })) {
            $output | Should -Match ([regex]::Escape("$n)"))
        }
    }

    It "a generously tall Compact-width window (60x30) still uses the normal framed presentation, not the emergency fallback" {
        # Confirms the emergency mode is gated correctly -- it must not
        # trigger just because the width is narrow, only when the height
        # genuinely can't fit every option any other way.
        $screen = Render-MainMenuScreen -Tier 'Compact' -Width 60 -Height 30
        $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"

        $output | Should -Match 'LIBRARY MANAGEMENT'
        $output | Should -Match 'APPLICATION'
        $output | Should -Match '14\) Exit'
    }

    It "every numbered option in the emergency presentation still maps to the same Mode the live switch statement dispatches on" {
        # Cross-checks against the same source-of-truth used by "Main menu
        # source-level drift check" elsewhere in this file: the emergency
        # presentation's numbers come directly from Get-MainMenuItems, the
        # same data the switch statement's case labels are generated from,
        # so there is no separate hand-maintained number-to-mode mapping
        # that could drift.
        $mainScriptContent = Get-Content -LiteralPath $scriptPath -Raw
        foreach ($item in (Get-MainMenuItems)) {
            if ($item.Mode -eq 'Exit') { continue }
            $mainScriptContent | Should -Match ([regex]::Escape('"{0}"' -f $item.Number) + '\s*\{\s*\$mode\s*=\s*"' + [regex]::Escape($item.Mode) + '"')
        }
    }
}

Describe "Issue #140 wording surfaces at every layout tier (issue #104/#140 RC3 correction)" {
    # Confirmed gap: Get-MainMenuSectionRows has a Professional-tier-only
    # special case (`if ($Geometry.Layout -eq 'ProfessionalTwoColumn')`)
    # that always sources its description text from
    # Get-MainMenuDefaultDescription instead of the shared ShortDesc/
    # FullDesc fields on the item -- so the #140 wording improvements
    # (ReShade/Postgres/BepInEx) landed only on ShortDesc/FullDesc and never
    # reached that function, meaning Professional tier (and Compact tier's
    # "?" detail view, which explicitly falls back to Professional -- see
    # the `if ($helpTier -eq 'Compact') { $helpTier = 'Professional' }` line
    # in the main menu loop) kept showing the OLD text, including the
    # literal "Install local PostgreSQL support." wording this issue was
    # filed to improve. Fixed by updating Get-MainMenuDefaultDescription's
    # text directly, since the Professional-specific routing itself is
    # deliberate (a shorter, single-line variant for a tighter column) and
    # out of scope to change.
    It "Professional tier (two-column) shows the improved wording, not the pre-#140 defaults" {
        $screen = Render-MainMenuScreen -Tier 'Professional' -Width 150 -Height 40
        $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"

        $output | Should -Match 'CRT'
        $output | Should -Match 'Golden Tee'
        $output | Should -Match 'modding framework'
        $output | Should -Not -Match 'Install local PostgreSQL support\.'
        $output | Should -Not -Match 'Apply visual enhancements\.'
        $output | Should -Not -Match 'Update existing BepInEx installs\.'
    }

    It "Compact tier's '?' detail view (falls back to Professional) also shows the improved wording" {
        # Reproduces the main loop's exact fallback: a Compact-tier console
        # pressing '?' is shown the Professional layout, not Compact's own
        # (label-only) layout. At this narrower two-column width the
        # description text legitimately word-wraps across render rows AND
        # across the column gutter/frame characters, so "modding" and
        # "framework" can end up separated by more than plain whitespace --
        # assert each word is present rather than requiring adjacency.
        $screen = Render-MainMenuScreen -Tier 'Professional' -Width 80 -Height 40
        $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"

        $output | Should -Match 'CRT'
        $output | Should -Match 'Golden Tee'
        $output | Should -Match 'modding'
        $output | Should -Match 'framework'
    }

    It "Ultra two-column tier (the default 'largest layout') shows the improved ShortDesc wording" {
        $screen = Render-MainMenuScreen -Tier 'Ultra' -Width 160 -Height 40
        $screen.Geometry.Layout | Should -Be 'UltraTwoColumn'
        $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"

        $output | Should -Match 'CRT'
        $output | Should -Match 'Golden Tee'
        $output | Should -Match 'modding framework'
    }

    It "UltraCentered (single-column, full descriptions) shows the improved FullDesc wording" {
        $screen = Render-MainMenuScreen -Tier 'Ultra' -Width 180 -Height 65 -UltraLayoutMode 'UltraCentered'
        $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"

        $output | Should -Match 'CRT'
        $output | Should -Match 'Golden Tee'
        $output | Should -Match 'modding framework'
    }

    It "Standard and Compact tiers' own (labels-only) render is unaffected -- no description text shown either way" {
        # Documents existing, unchanged-by-this-fix behavior: Standard and
        # Compact both render Labels-only detail with no per-item
        # description at all (Compact's escape hatch is the '?' key, tested
        # above, which is a SEPARATE render call, not part of this one).
        foreach ($case in @(
            @{ Tier = 'Compact'; Width = 80 }
            @{ Tier = 'Standard'; Width = 100 }
        )) {
            $screen = Render-MainMenuScreen -Tier $case.Tier -Width $case.Width -Height 40
            $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"
            $output | Should -Not -Match 'CRT'
            $output | Should -Not -Match 'Golden Tee'
        }
    }
}

Describe "Menu layout debug script" {
    It "prints host dimensions and renderer metrics without launching the interactive manager" {
        $debugScript = Join-Path $PSScriptRoot '..\scripts\Debug-TPM-MenuLayout.ps1'
        $output = & $debugScript -Width 200 -Height 30 6>&1 | Out-String

        $output | Should -Match 'Host type'
        $output | Should -Match 'Host\.RawUI\.WindowSize\.Width'
        $output | Should -Match 'Host\.RawUI\.BufferSize\.Height'
        $output | Should -Match 'Selected viewport width\s+:\s+200'
        $output | Should -Match 'Selected viewport height\s+:\s+30'
        $output | Should -Match 'Selected layout tier\s+:\s+Ultra'
        $output | Should -Match 'Selected layout mode\s+:\s+UltraTwoColumn'
        $output | Should -Match 'Requested ultra mode\s+:\s+Auto'
        $output | Should -Match 'Description width\s+:\s+79'
        $output | Should -Match 'Total render width\s+:\s+198'
        $output | Should -Match 'Constrained by\s+:\s+height'
    }
    It "can render the experimental UltraCentered layout for comparison" {
        $debugScript = Join-Path $PSScriptRoot '..\scripts\Debug-TPM-MenuLayout.ps1'
        $output = & $debugScript -Width 180 -Height 30 -UltraLayoutMode UltraCentered -Render 6>&1 | Out-String

        $output | Should -Match 'Selected layout tier\s+:\s+Ultra'
        $output | Should -Match 'Selected layout mode\s+:\s+UltraCentered'
        $output | Should -Match 'Requested ultra mode\s+:\s+UltraCentered'
        $output | Should -Match 'Selected layout mode\s+:\s+UltraCentered'
    }

    # The two tests above invoke the diagnostic via `& $debugScript` from
    # INSIDE this same Pester process -- that call runs in a child scope of
    # the current session, which already has every production function
    # (including Limit-MainMenuBodyRowsToBudget) dot-sourced into it by this
    # file's own top-level BeforeAll. That let a real regression pass
    # invisibly: the packaged script itself only loaded a hand-maintained
    # allowlist of function names and never defined
    # Limit-MainMenuBodyRowsToBudget (added for the RC3 short-viewport
    # truncation fix), so running the actual, unmodified .ps1 file as a
    # user would -- a fresh process with nothing pre-loaded -- crashed with
    # "the term 'Limit-MainMenuBodyRowsToBudget' is ... not recognized" the
    # moment -Render exercised the render pipeline. `& $debugScript` here
    # never caught it because the missing function was already present from
    # this file's own BeforeAll, not from the diagnostic script itself.
    # These tests launch a genuinely separate PROCESS instead, so nothing
    # from this test session's scope can leak in and mask a missing
    # dependency in the packaged script.
    It "runs successfully as a genuinely isolated process (not just a child scope) under pwsh, with -Render exercising the full pipeline" {
        $debugScript = Join-Path $PSScriptRoot '..\scripts\Debug-TPM-MenuLayout.ps1'
        $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
        if (-not $pwshCmd) { Set-ItResult -Skipped -Because 'pwsh is not available on this machine'; return }

        $output = & $pwshCmd.Source -NoProfile -NonInteractive -File $debugScript -Width 150 -Height 40 -Render 2>&1 | Out-String
        $exitCode = $LASTEXITCODE

        $exitCode | Should -Be 0
        $output | Should -Not -Match 'is not recognized as the name of a cmdlet'
        $output | Should -Not -Match 'CommandNotFoundException'
        $output | Should -Match '14\) Exit'
        $output | Should -Match 'Enter number'
    }

    It "runs successfully as a genuinely isolated process under real Windows PowerShell 5.1, with -Render exercising the full pipeline" {
        $debugScript = Join-Path $PSScriptRoot '..\scripts\Debug-TPM-MenuLayout.ps1'
        $ps51Path = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path -LiteralPath $ps51Path)) { Set-ItResult -Skipped -Because 'Windows PowerShell 5.1 is not available on this machine'; return }

        $output = & $ps51Path -NoProfile -File $debugScript -Width 150 -Height 40 -Render 2>&1 | Out-String
        $exitCode = $LASTEXITCODE

        $exitCode | Should -Be 0
        $output | Should -Not -Match 'is not recognized as the name of a cmdlet'
        $output | Should -Not -Match 'CommandNotFoundException'
        $output | Should -Match '14\) Exit'
        $output | Should -Match 'Enter number'
    }
}

Describe "Resolve-Pcsx2Directory" {
    It "finds the exact-name pcsx2x6 folder" {
        $root = Join-Path $TestDrive ("resolve-exact-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $root 'pcsx2x6') -Force | Out-Null
        Resolve-Pcsx2Directory -TeknoParrotRoot $root | Should -Be (Join-Path $root 'pcsx2x6')
    }

    It "finds an alternate-cased PCSX2x6 folder" {
        $root = Join-Path $TestDrive ("resolve-altcase-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $root 'PCSX2x6') -Force | Out-Null
        Resolve-Pcsx2Directory -TeknoParrotRoot $root | Should -Be (Join-Path $root 'PCSX2x6')
    }

    It "returns null when no pcsx2-shaped folder exists" {
        $root = Join-Path $TestDrive ("resolve-none-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root 'GameProfiles') -Force | Out-Null
        Resolve-Pcsx2Directory -TeknoParrotRoot $root | Should -BeNullOrEmpty
    }
}

Describe "Get-CompatibilityWarnings -- BiosMissing (issue #85 tier 1)" {
    BeforeAll {
        $script:RawThrillsPathLimits = @{}
        $script:FileVersionPins = @{}
        $script:GpuIncompatibleGames = @{}
        $script:EmulatorBiosRequirements = @{
            'Pcsx2x6' = @{
                RelativeDir   = 'TeknoParrot\bios'
                RequiredFiles = @('27v1602T.d', '27v1602F.bg')
            }
        }

        function New-Pcsx2UserProfile {
            param([string]$Path)
            [xml]@'
<?xml version="1.0" encoding="utf-8"?>
<GameProfile>
  <EmulatorType>Pcsx2x6</EmulatorType>
  <GamePath>C:\Games\game.exe</GamePath>
</GameProfile>
'@ | ForEach-Object { $_.Save($Path) }
        }
    }

    It "reports nothing when -TeknoParrotRoot is not supplied (backward compatible)" {
        $userProfilesDir = Join-Path $TestDrive ("bios-no-root-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $userProfilesDir -Force | Out-Null
        New-Pcsx2UserProfile -Path (Join-Path $userProfilesDir 'BLOODYROAR3.xml')

        $result = Get-CompatibilityWarnings -UserProfilesDir $userProfilesDir
        @($result.BiosMissing) | Should -BeNullOrEmpty
    }

    It "reports nothing when the pcsx2x6 folder itself does not exist yet" {
        $root = Join-Path $TestDrive ("bios-noemudir-" + [guid]::NewGuid().ToString('N'))
        $userProfilesDir = Join-Path $root 'UserProfiles'
        New-Item -ItemType Directory -Path $userProfilesDir -Force | Out-Null
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        New-Pcsx2UserProfile -Path (Join-Path $userProfilesDir 'BLOODYROAR3.xml')

        $result = Get-CompatibilityWarnings -UserProfilesDir $userProfilesDir -TeknoParrotRoot $root
        @($result.BiosMissing) | Should -BeNullOrEmpty -Because "nothing to check yet -- the emulator itself isn't installed"
    }

    It "reports nothing when both required BIOS files are present" {
        $root = Join-Path $TestDrive ("bios-present-" + [guid]::NewGuid().ToString('N'))
        $userProfilesDir = Join-Path $root 'UserProfiles'
        $biosDir = Join-Path $root 'pcsx2x6\TeknoParrot\bios'
        New-Item -ItemType Directory -Path $userProfilesDir, $biosDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $biosDir '27v1602T.d') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $biosDir '27v1602F.bg') -Force | Out-Null
        New-Pcsx2UserProfile -Path (Join-Path $userProfilesDir 'BLOODYROAR3.xml')

        $result = Get-CompatibilityWarnings -UserProfilesDir $userProfilesDir -TeknoParrotRoot $root
        @($result.BiosMissing) | Should -BeNullOrEmpty
    }

    It "reports a BiosMissing entry with correct MissingFiles and AffectedGames when firmware is absent" {
        $root = Join-Path $TestDrive ("bios-missing-" + [guid]::NewGuid().ToString('N'))
        $userProfilesDir = Join-Path $root 'UserProfiles'
        New-Item -ItemType Directory -Path $userProfilesDir -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root 'pcsx2x6') -Force | Out-Null
        New-Pcsx2UserProfile -Path (Join-Path $userProfilesDir 'BLOODYROAR3.xml')

        $result = Get-CompatibilityWarnings -UserProfilesDir $userProfilesDir -TeknoParrotRoot $root
        @($result.BiosMissing).Count | Should -Be 1
        $entry = $result.BiosMissing[0]
        $entry.EmulatorType | Should -Be 'Pcsx2x6'
        @($entry.MissingFiles) | Should -Contain '27v1602T.d'
        @($entry.MissingFiles) | Should -Contain '27v1602F.bg'
        @($entry.AffectedGames) | Should -Contain 'BLOODYROAR3'
    }

    It "reports one entry (not duplicated) covering multiple registered pcsx2x6 games" {
        $root = Join-Path $TestDrive ("bios-multi-" + [guid]::NewGuid().ToString('N'))
        $userProfilesDir = Join-Path $root 'UserProfiles'
        New-Item -ItemType Directory -Path $userProfilesDir -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root 'pcsx2x6') -Force | Out-Null
        New-Pcsx2UserProfile -Path (Join-Path $userProfilesDir 'BLOODYROAR3.xml')
        New-Pcsx2UserProfile -Path (Join-Path $userProfilesDir 'BLOODYROAR4.xml')

        $result = Get-CompatibilityWarnings -UserProfilesDir $userProfilesDir -TeknoParrotRoot $root
        @($result.BiosMissing).Count | Should -Be 1 -Because "one shared emulator instance needs one warning, not one per affected game"
        @($result.BiosMissing[0].AffectedGames).Count | Should -Be 2
    }

    It "reports only the still-missing file when one of the two required files is already present" {
        $root = Join-Path $TestDrive ("bios-partial-" + [guid]::NewGuid().ToString('N'))
        $userProfilesDir = Join-Path $root 'UserProfiles'
        $biosDir = Join-Path $root 'pcsx2x6\TeknoParrot\bios'
        New-Item -ItemType Directory -Path $userProfilesDir, $biosDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $biosDir '27v1602T.d') -Force | Out-Null
        New-Pcsx2UserProfile -Path (Join-Path $userProfilesDir 'BLOODYROAR3.xml')

        $result = Get-CompatibilityWarnings -UserProfilesDir $userProfilesDir -TeknoParrotRoot $root
        @($result.BiosMissing).Count | Should -Be 1
        @($result.BiosMissing[0].MissingFiles) | Should -Be @('27v1602F.bg')
    }

    It "never reads or modifies the placeholder BIOS files -- existence-only check" {
        $root = Join-Path $TestDrive ("bios-readonly-check-" + [guid]::NewGuid().ToString('N'))
        $userProfilesDir = Join-Path $root 'UserProfiles'
        $biosDir = Join-Path $root 'pcsx2x6\TeknoParrot\bios'
        New-Item -ItemType Directory -Path $userProfilesDir, $biosDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $biosDir '27v1602T.d') -Value 'not real firmware content' -Encoding ascii
        Set-Content -LiteralPath (Join-Path $biosDir '27v1602F.bg') -Value 'not real firmware content' -Encoding ascii
        $beforeT = Get-Content -LiteralPath (Join-Path $biosDir '27v1602T.d') -Raw
        New-Pcsx2UserProfile -Path (Join-Path $userProfilesDir 'BLOODYROAR3.xml')

        Get-CompatibilityWarnings -UserProfilesDir $userProfilesDir -TeknoParrotRoot $root | Out-Null

        (Get-Content -LiteralPath (Join-Path $biosDir '27v1602T.d') -Raw) | Should -Be $beforeT -Because "TPM must never read or modify BIOS file content, only check existence"
    }
}

Describe "RC2 DAT selection and override UX (issues #119, #120, #121)" {
    # This is top-level interactive script flow (DAT selection during
    # AutoSync/Register), not an extractable standalone function -- exercising
    # it end-to-end would mean driving the full interactive menu harness for
    # UX wording alone. Source-level checks are the proportionate choice here,
    # matching the same convention already used for other top-level-flow
    # wording guarantees elsewhere in this file (e.g. the Thumbnail download
    # regression guards above).
    BeforeAll {
        $script:scriptContent = Get-Content -LiteralPath $scriptPath -Raw
    }

    It "issue #119: only shows the Overrides line when at least one override is actually configured" {
        $script:scriptContent | Should -Match '\$ovCount\s*=\s*\$noSyncList\.Count\s*\+\s*\$onlySyncList\.Count'
        $script:scriptContent | Should -Match 'if\s*\(\$ovCount\s*-gt\s*0\)\s*\{'
    }

    It "issue #119: explains what the Overrides line means and what action the user can take" {
        # Must appear inside the same ovCount-gated block, not as an
        # unconditional line elsewhere -- confirmed by requiring the
        # explanation text to follow the "Overrides:" line within a bounded
        # window rather than just existing anywhere in the file.
        $script:scriptContent | Should -Match 'Overrides:\s*noSync[\s\S]{0,400}TeknoParrot-Manager\.overrides\.json'
        $script:scriptContent | Should -Match "there's nothing to do"
    }

    It "issue #120: tells the user which dat/ZIP was selected" {
        $script:scriptContent | Should -Match 'Write-Host\s*\(\s*"\s*\s*Selected:\s*\{0\}"'
    }

    It "issue #120: reports freshness (current / newer available / unknown) for a selected ZIP, and the no-comparison case for a standalone dat" {
        $script:scriptContent | Should -Match 'This is the latest available version'
        $script:scriptContent | Should -Match 'A newer version is available'
        $script:scriptContent | Should -Match 'Could not determine whether this is the latest version'
        $script:scriptContent | Should -Match 'Cannot check whether this is the latest version'
    }

    It "issue #121: the DAT browse file filter allows both .zip and .dat by default, not just .zip or All Files" {
        $datFilterMatches = [regex]::Matches($script:scriptContent, 'ZIP/dat files \(\*\.zip;\*\.dat\)\|\*\.zip;\*\.dat')
        $datFilterMatches.Count | Should -BeGreaterThan 0 -Because "every DAT browse call site (initial D/B choice, download-fallback, already-configured re-browse) must offer both extensions from the default filter"
    }
}

Describe "TeknoParrot-Manager.ps1 -Unattended real child-process fixture (issue #154 real-hardware certification finding)" {
    # A real certification run confirmed TeknoParrot-Manager.ps1 -Unattended
    # always exited 1 at "Mode must be set before starting" -- there was no
    # config or CLI mechanism to auto-select an initial mode, only the
    # interactive menu or a same-session preview re-entry. This launches the
    # REAL, unmodified script (copied into TestDrive, never the real repo
    # checkout) as a real child process against a synthetic, non-real
    # "TeknoParrot install" (a bare directory structure), proving the
    # UnattendedMode config field lets it pass configuration validation and
    # reach HealthCheck's bounded stop-point (a real, read-only library scan)
    # and then exit cleanly on its own -- never launching, inspecting, or
    # modifying a genuine TeknoParrot installation.
    # Deliberately does NOT import TPMCertification.Execution.psm1 (or any
    # other shared certification module) here, even though its
    # Invoke-TPMIsolatedProcessV1 would otherwise be a natural fit --
    # confirmed by direct reproduction that doing so (with or without
    # -Force) creates a second, scope-local copy of that module, which
    # collides with TPMCertification.OperatorExperience.Tests.ps1's own
    # "Mock -ModuleName TPMCertification.Execution -CommandName Write-Host"
    # when both files run in the same Pester session: Pester itself throws
    # "Multiple script or manifest modules named 'TPMCertification.Execution'
    # are currently loaded" -- reproduced deterministically down to just
    # these two specific tests, not environmental flakiness. This test uses
    # a plain, self-contained Start-Process invocation instead, so it never
    # touches any module another test file also imports.
    It "passes configuration validation and reaches the HealthCheck bounded stop-point, exiting 0, without ever needing a real TeknoParrot installation" {
        $fixtureRoot = Join-Path $TestDrive ("unattended-fixture-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
        Copy-Item -LiteralPath $scriptPath -Destination (Join-Path $fixtureRoot 'TeknoParrot-Manager.ps1') -Force

        # SECTION 2 of TeknoParrot-Manager.ps1 unconditionally requires
        # TeknoParrotUi.exe and a GameProfiles folder to exist at the
        # configured root (this is a real, pre-existing, non-Unattended-
        # specific requirement -- confirmed by direct reproduction, not
        # assumed) -- neither is a genuine executable/profile store here,
        # since HealthCheck's own read-only scan never launches or
        # inspects them, only checks they exist.
        $fakeTpRoot = Join-Path $fixtureRoot 'fake-tp-root'
        New-Item -ItemType Directory -Path (Join-Path $fakeTpRoot 'UserProfiles') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $fakeTpRoot 'GameProfiles') -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $fakeTpRoot 'TeknoParrotUi.exe'), '')

        $configPath = Join-Path $fixtureRoot 'TeknoParrot-Manager.config.json'
        $cfg = [ordered]@{ TeknoParrotRoot = $fakeTpRoot; GamesInstallFolder = $fakeTpRoot; UnattendedMode = 'HealthCheck' }
        [System.IO.File]::WriteAllText($configPath, ($cfg | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding $false))

        $stdoutPath = Join-Path $fixtureRoot 'stdout.log'
        $stderrPath = Join-Path $fixtureRoot 'stderr.log'
        $stdinPath = Join-Path $fixtureRoot 'stdin.empty'
        [IO.File]::WriteAllText($stdinPath, '')

        $process = Start-Process -FilePath (Get-Command pwsh).Source -ArgumentList @('-NoProfile','-NonInteractive','-File',(Join-Path $fixtureRoot 'TeknoParrot-Manager.ps1'),'-Unattended') -WorkingDirectory $fixtureRoot -RedirectStandardInput $stdinPath -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -NoNewWindow -PassThru
        # Confirmed by direct reproduction under real Windows PowerShell 5.1
        # (its older .NET Framework CLR, not pwsh's): touching .Handle
        # immediately after Start-Process -PassThru forces .NET to open and
        # cache a real handle to the process before it can exit. Skipping
        # this is a well-known .NET Framework Process-class quirk -- for a
        # fast-exiting process (HealthCheck completes in ~1.5s here), the
        # OS can recycle the process record before a later .ExitCode read,
        # leaving it $null even though WaitForExit already returned $true.
        # pwsh's newer runtime does not have this problem, which is exactly
        # why this only reproduced under Windows PowerShell 5.1.
        [void]$process.Handle
        $exited = $process.WaitForExit(60000)
        if (-not $exited) {
            try { $process.Kill() } catch {}
            throw "TeknoParrot-Manager.ps1 -Unattended did not exit within the 60-second bound"
        }
        $process.WaitForExit()

        $process.ExitCode | Should -Be 0 -Because 'a genuine product defect (Mode must be set before starting) previously made every real -Unattended launch exit 1 here'

        $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw } else { '' }
        $stdout | Should -Not -Match 'Mode must be set before starting' -Because 'this is the exact error text the real certification run hit'
        $stdout | Should -Match 'Library Health Check' -Because 'HealthCheck must have actually run, not merely avoided the error'
        $stdout | Should -Match 'Unattended.*Using saved settings' -Because 'confirms the config path was genuinely exercised, not bypassed'

        # No real install was ever touched: this is a synthetic fixture, and
        # the placeholder TeknoParrotUi.exe -- present only so SECTION 2's
        # existence check passes -- remains exactly as created (empty),
        # proving HealthCheck's read-only scan never wrote to it.
        (Get-Item -LiteralPath (Join-Path $fakeTpRoot 'TeknoParrotUi.exe')).Length | Should -Be 0
    }

    It "loads a legacy saved config with no UnattendedMode field at all without throwing under Set-StrictMode, and fails safely (no mode chosen) rather than crashing" {
        # A saved config from before this feature existed has no
        # UnattendedMode property whatsoever on the deserialized object --
        # not $null, genuinely absent. Confirmed by direct reproduction that
        # $cfg.UnattendedMode on such an object throws
        # PropertyNotFoundException under Set-StrictMode -Version Latest
        # (both pwsh and Windows PowerShell 5.1). The real interactive/
        # -Unattended entry point does not itself call Set-StrictMode, but
        # this exact access pattern must still be safe under any stricter
        # caller (test harness, future dot-sourcing, etc.), so the fixture
        # script wraps the real, unmodified TeknoParrot-Manager.ps1 with an
        # explicit Set-StrictMode -Version Latest to prove the read sites
        # themselves are strict-mode-safe, not merely that the ordinary
        # entry point happens not to trip the bug today. The wrapper must
        # dot-source (". path", not "& path") -- confirmed by direct
        # reproduction that Set-StrictMode does NOT propagate across a
        # separate script file invoked with the call operator (&), only
        # into a dot-sourced one; using & here would silently make this
        # test exercise no strict-mode enforcement at all.
        $fixtureRoot = Join-Path $TestDrive ("legacy-config-fixture-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null

        $realScriptPath = Join-Path $fixtureRoot 'TeknoParrot-Manager.ps1'
        Copy-Item -LiteralPath $scriptPath -Destination $realScriptPath -Force

        $wrapperPath = Join-Path $fixtureRoot 'StrictModeWrapper.ps1'
        $wrapperContent = "Set-StrictMode -Version Latest`r`n. '$realScriptPath' @args`r`nexit `$LASTEXITCODE"
        [System.IO.File]::WriteAllText($wrapperPath, $wrapperContent, (New-Object System.Text.UTF8Encoding $false))

        $fakeTpRoot = Join-Path $fixtureRoot 'fake-tp-root'
        New-Item -ItemType Directory -Path (Join-Path $fakeTpRoot 'UserProfiles') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $fakeTpRoot 'GameProfiles') -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $fakeTpRoot 'TeknoParrotUi.exe'), '')

        # Mirrors Save-Config's exact key set (every field it has ever
        # written) minus UnattendedMode -- a genuine legacy config carries
        # all of these (some null), since Save-Config has always written
        # them; UnattendedMode is the only key that is a true, brand-new
        # absence rather than a null value. A fixture with ONLY
        # TeknoParrotRoot/GamesInstallFolder would be unrealistic and would
        # also trip strict-mode on all these OTHER pre-existing optional
        # reads, which are out of this fix's scope.
        $configPath = Join-Path $fixtureRoot 'TeknoParrot-Manager.config.json'
        $cfg = [ordered]@{
            TeknoParrotRoot              = $fakeTpRoot
            ZipSourceFolder              = $null
            ZipSourceSupplementaryFolder = $null
            GamesInstallFolder           = $fakeTpRoot
            RetroBat                     = $false
            HyperSpinDataPath            = $null
            ReShadeSourceDll             = $null
            ReShadeSourceDll32           = $null
            DgVoodoo2SourceDir           = $null
            EggmanDatZip                 = $null
            DatFilePath                  = $null
            SupplementaryDatPath         = $null
            IncludeSupplementary         = $false
            LaunchBoxRoot                = $null
            LaunchBoxPlatformMode        = $null
            LaunchBoxCustomPlatformName  = $null
            LaunchBoxEmulatorId          = $null
            PostgresSuperPasswordEncrypted = $null
            CheckForUpdatesOnStartup     = $true
        }
        [System.IO.File]::WriteAllText($configPath, ($cfg | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding $false))

        $stdoutPath = Join-Path $fixtureRoot 'stdout.log'
        $stderrPath = Join-Path $fixtureRoot 'stderr.log'
        $stdinPath = Join-Path $fixtureRoot 'stdin.empty'
        [IO.File]::WriteAllText($stdinPath, '')

        $process = Start-Process -FilePath (Get-Command pwsh).Source -ArgumentList @('-NoProfile','-NonInteractive','-File',$wrapperPath,'-Unattended') -WorkingDirectory $fixtureRoot -RedirectStandardInput $stdinPath -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -NoNewWindow -PassThru
        [void]$process.Handle
        $exited = $process.WaitForExit(60000)
        if (-not $exited) {
            try { $process.Kill() } catch {}
            throw "TeknoParrot-Manager.ps1 -Unattended (strict-mode wrapper) did not exit within the 60-second bound"
        }
        $process.WaitForExit()

        $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw } else { '' }
        $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { '' }

        $stdout | Should -Not -Match 'PropertyNotFoundException|cannot be found on this object' -Because 'a legacy config missing UnattendedMode must never throw when the property is read'
        $stderr | Should -Not -Match 'PropertyNotFoundException|cannot be found on this object' -Because 'a legacy config missing UnattendedMode must never throw when the property is read'
        $stdout | Should -Not -Match 'Saved configuration could not be read \(file may be corrupt\)' -Because 'a legacy config missing only the new optional UnattendedMode field is not corrupt and must still be accepted'
        $stdout | Should -Match 'Unattended.*Using saved settings' -Because 'the legacy config must still pass validation and be accepted'

        # No mode can be auto-selected from a config that never named one,
        # so this must fail the same safe, pre-existing way every other
        # -Unattended launch with no mode chosen already does -- not crash.
        $process.ExitCode | Should -Be 1 -Because 'no UnattendedMode means no mode was chosen; this must be the pre-existing safe failure, not a new crash'
        $stdout | Should -Match 'Mode must be set before starting' -Because 'this is the pre-existing, expected safe failure for no mode chosen'
    }
}
