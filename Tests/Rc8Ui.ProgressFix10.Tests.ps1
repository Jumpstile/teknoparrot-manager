#Requires -Module Pester

# RC8 FIX10: Terra UI review findings on the shared progress renderer.
#   BLOCKER 1  failed or unverified work never closes as success (CursorHide and the audited close sites)
#   MAJOR 1    a nested failure keeps the parent bar open until its owner closes it
#   MAJOR 2    background-aware palette; glyphs only with measured host evidence
#   MAJOR 3    the ETA restarts when the stage (its text) changes
#   MAJOR 4    ordinary output never lands after the live bar; a resize redraws in place
#   MINOR 2    a narrow failed line keeps its state word
# Fake-only: the module's clock and console seams are mocked (an emulated cursor), product functions are AST-extracted
# from TeknoParrot-Manager.ps1 with recording stand-ins, and fixtures live in $TestDrive. Nothing here starts the
# product, touches a real install, or writes to a real console.

BeforeAll {
    $script:fx10ModulePath = [System.IO.Path]::GetFullPath((Join-Path (Join-Path $PSScriptRoot '..\scripts') 'TpmProgress.psm1'))
    # Exactly one loaded TpmProgress for module-scoped mocks: drop any copy an earlier test file loaded from its $TestDrive.
    Get-Module -Name TpmProgress -All | Remove-Module -Force
    Import-Module $script:fx10ModulePath -Force -ErrorAction Stop
    $tokens = $null
    $parseErrors = $null
    $script:fx10Ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path (Join-Path $PSScriptRoot '..') 'TeknoParrot-Manager.ps1'), [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Failed to parse TeknoParrot-Manager.ps1.' }

    function Get-Fx10FunctionText {
        param([string[]]$Name)
        $found = @($script:fx10Ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $Name
        }, $true))
        if ($found.Count -ne $Name.Count) { throw "Expected $($Name -join ', '); found $(@($found | ForEach-Object { $_.Name }) -join ', ')." }
        return (($found | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n")
    }

    # Pester 5 rejects a BeforeEach in the file root ("Each test setup is not supported in root"), which stops every
    # test in this file. Every top-level Describe calls this first in its BeforeEach, so each test gets the same
    # per-test mocks as the former root BeforeEach, before any Describe-specific mock overrides them.
    function Set-Fx10DefaultMocks {
        # These outcome/clock regressions use the explicit full-data column configuration.
        Mock Get-TpmProgressDefaultColumns { @('Spinner', 'Description', 'Bar', 'Percentage', 'Count', 'Elapsed', 'Remaining') } -ModuleName TpmProgress
        Mock Start-TpmProgressRefresh {} -ModuleName TpmProgress
        Mock Get-TpmProgressCursorVisible { $true } -ModuleName TpmProgress
        Mock Set-TpmProgressCursorVisible {} -ModuleName TpmProgress
    }
}

AfterAll {
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
}

Describe 'FIX10 BLOCKER 1: CursorHide never closes a failed or unverified stage as done' {
    BeforeAll {
        function Write-TpmCompactExtractionProgress {
            param([string]$Phase, [string]$Label, [long]$Current, [long]$Total, [datetime]$StartedAt, [int]$Width, [switch]$Complete, [switch]$Substage, [string]$Outcome = 'Final', [switch]$ReturnText, [switch]$Completed, [string]$Unit = 'Items')
            [void]$script:fx10Events.Add([pscustomobject]@{ Label = $Label; Current = $Current; Total = $Total; Complete = [bool]$Complete; Outcome = $Outcome; Completed = [bool]$Completed })
        }
        function Get-TpmRegisteredProfileFilesWithDiscoveryProgress {
            param([string]$UserProfilesDir, [string]$ProgressLabel, [string]$EnumerationErrorAction)
            return @(Get-ChildItem -LiteralPath $UserProfilesDir -Filter '*.xml' -File)
        }
        function Read-Xml {
            param([string]$path)
            $name = [System.IO.Path]::GetFileName($path)
            if (-not $script:fx10Reads.ContainsKey($name)) { $script:fx10Reads[$name] = 0 }
            $script:fx10Reads[$name]++
            if ($script:fx10ReadFailAt.ContainsKey($name) -and $script:fx10Reads[$name] -ge $script:fx10ReadFailAt[$name]) { throw 'fixture read failure' }
            $doc = New-Object System.Xml.XmlDocument
            $doc.Load($path)
            return $doc
        }
        function Save-Xml {
            param($doc, [string]$path)
            if ($script:fx10SaveFail -contains [System.IO.Path]::GetFileNameWithoutExtension($path)) { throw 'fixture save failure' }
            $doc.Save($path)
        }
        function New-TpmVerifiedUserProfilesBackup {
            param([string]$UserProfilesDir, [string]$Label)
            if ($script:fx10OnBackup) { & $script:fx10OnBackup }
            return [pscustomobject]@{ Verified = $true }
        }
        function New-TpmProfileTransactionResult {
            param($WorkflowKey, $OperationKey, $Outcome, $ProductState, $Summary, $Items, $ChangedItems, $CompletedItems, $FailedItems, $UnknownItems, $MutationStarted, $Backup, $FinalPassed, $ReasonCode, $FinalChecks)
            return [pscustomobject]@{ Outcome = $Outcome; ReasonCode = $ReasonCode; CompletedItems = @($CompletedItems) }
        }
        function Write-Log { param([string]$msg) }
        function Write-Host {}
        . ([scriptblock]::Create((Get-Fx10FunctionText -Name @('Invoke-CursorHideSetup', 'ConvertTo-XPathStringLiteral'))))

        function New-Fx10CursorProfiles {
            param([string[]]$Names)
            $dir = Join-Path $TestDrive ('fx10-cursor-' + [guid]::NewGuid().ToString('N'))
            [void][System.IO.Directory]::CreateDirectory($dir)
            foreach ($name in $Names) {
                $xml = '<GameProfile><GunGame>true</GunGame><ConfigValues><FieldInformation><FieldName>HideCursor</FieldName><FieldValue>0</FieldValue></FieldInformation></ConfigValues></GameProfile>'
                [System.IO.File]::WriteAllText((Join-Path $dir ($name + '.xml')), $xml)
            }
            return $dir
        }
        function Get-Fx10Closes {
            param([string]$Label)
            return @($script:fx10Events | Where-Object { $_.Complete -and $_.Label -eq $Label })
        }
    }
    BeforeEach {
        Set-Fx10DefaultMocks
        $script:fx10Events = New-Object System.Collections.Generic.List[object]
        $script:fx10Reads = @{}
        $script:fx10ReadFailAt = @{}
        $script:fx10SaveFail = @()
        $script:fx10OnBackup = $null
    }

    It 'closes revalidation Error, not done at 1/1, when the only profile changed before the write' {
        $dir = New-Fx10CursorProfiles -Names @('A')
        $script:fx10OnBackup = { [System.IO.File]::AppendAllText((Join-Path $dir 'A.xml'), '<!-- changed by another program -->') }.GetNewClosure()
        $result = Invoke-CursorHideSetup -UserProfilesDir $dir
        $result.Outcome | Should -Be 'ACTION_REQUIRED'
        $result.ReasonCode | Should -Be 'PROFILE_CHANGED_BEFORE_WRITE'
        $closes = @(Get-Fx10Closes -Label 'CursorHide profile revalidation')
        $closes.Count | Should -Be 1
        $closes[0].Outcome | Should -Be 'Error'
        $closes[0].Current | Should -Be 0
        @(Get-Fx10Closes -Label 'CursorHide profile update').Count | Should -Be 0
    }

    It 'closes revalidation Error when reading the profile throws, before the exception leaves the function' {
        $dir = New-Fx10CursorProfiles -Names @('A')
        $script:fx10OnBackup = { [System.IO.File]::Delete((Join-Path $dir 'A.xml')) }.GetNewClosure()
        { Invoke-CursorHideSetup -UserProfilesDir $dir } | Should -Throw
        $closes = @(Get-Fx10Closes -Label 'CursorHide profile revalidation')
        $closes.Count | Should -Be 1
        $closes[0].Outcome | Should -Be 'Error'
    }

    It 'counts only verified updates and closes update and final verification Error when one profile fails' {
        $dir = New-Fx10CursorProfiles -Names @('A', 'B')
        $script:fx10SaveFail = @('B')
        $result = Invoke-CursorHideSetup -UserProfilesDir $dir
        $result.Outcome | Should -Be 'PARTIAL_APPLIED'
        $update = @(Get-Fx10Closes -Label 'CursorHide profile update')
        $update.Count | Should -Be 1
        $update[0].Outcome | Should -Be 'Error'
        $update[0].Current | Should -Be 1
        # The last count rendered before the Error close is the verified count, never the attempted count.
        $rendered = @($script:fx10Events | Where-Object { -not $_.Complete -and $_.Label -eq 'CursorHide profile update' })
        $rendered[-1].Current | Should -Be 1
        @($rendered | Where-Object { -not $_.Completed }).Count | Should -Be 0
        $final = @(Get-Fx10Closes -Label 'CursorHide final verification')
        $final[0].Outcome | Should -Be 'Error'
        $final[0].Current | Should -Be 1
    }

    It 'closes final verification Error when the final read-back fails (state unknown)' {
        $dir = New-Fx10CursorProfiles -Names @('A')
        # Reads of A: scan, revalidation, update, update read-back, final verification (5th).
        $script:fx10ReadFailAt = @{ 'A.xml' = 5 }
        $result = Invoke-CursorHideSetup -UserProfilesDir $dir
        $result.Outcome | Should -Be 'ACTION_REQUIRED'
        (Get-Fx10Closes -Label 'CursorHide profile update')[0].Outcome | Should -Be 'Final'
        $final = @(Get-Fx10Closes -Label 'CursorHide final verification')
        $final.Count | Should -Be 1
        $final[0].Outcome | Should -Be 'Error'
        $final[0].Current | Should -Be 0
    }

    It 'closes the scan Error when a profile could not be inspected' {
        $dir = New-Fx10CursorProfiles -Names @('A', 'B')
        $script:fx10ReadFailAt = @{ 'B.xml' = 1 }
        [void](Invoke-CursorHideSetup -UserProfilesDir $dir)
        (Get-Fx10Closes -Label 'CursorHide profile scan')[0].Outcome | Should -Be 'Error'
    }

    It 'closes every stage Final with full counts when every profile is updated and verified' {
        $dir = New-Fx10CursorProfiles -Names @('A', 'B')
        $result = Invoke-CursorHideSetup -UserProfilesDir $dir
        $result.Outcome | Should -Be 'SUCCEEDED'
        foreach ($label in @('CursorHide profile scan', 'CursorHide profile revalidation', 'CursorHide profile update', 'CursorHide final verification')) {
            $close = @(Get-Fx10Closes -Label $label)
            $close.Count | Should -Be 1
            $close[0].Outcome | Should -Be 'Final'
            $close[0].Current | Should -Be 2
        }
    }
}

Describe 'FIX10 BLOCKER 1: audited close sites report failures as Error' {
    BeforeAll {
        function Write-TpmCompactExtractionProgress {
            param([string]$Phase, [string]$Label, [long]$Current, [long]$Total, [datetime]$StartedAt, [int]$Width, [switch]$Complete, [switch]$Substage, [string]$Outcome = 'Final', [switch]$ReturnText, [switch]$Completed, [string]$Unit = 'Items')
            [void]$script:fx10Events.Add([pscustomobject]@{ Label = $Label; Current = $Current; Total = $Total; Complete = [bool]$Complete; Outcome = $Outcome })
        }
        function Write-Log { param([string]$msg) }
        function Read-Xml {
            param([string]$path)
            if ([System.IO.Path]::GetFileName($path) -like 'bad*') { throw 'fixture unreadable profile' }
            $doc = New-Object System.Xml.XmlDocument
            $doc.Load($path)
            return $doc
        }
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        . ([scriptblock]::Create((Get-Fx10FunctionText -Name @('Get-TpmAutoSyncZipInventory', 'ConvertTo-SafeZipEntryRelativePath', 'Get-TpmTransactionField', 'Get-TpmPostgresRequirementScan', 'Test-GameNeedsPostgres', 'Get-TpmGameDatabaseStorage'))))
    }
    BeforeEach { Set-Fx10DefaultMocks; $script:fx10Events = New-Object System.Collections.Generic.List[object] }

    It 'closes the AutoSync ZIP inventory Error when a file/directory collision is found after hashing' {
        $zipPath = Join-Path $TestDrive ('fx10-collision-' + [guid]::NewGuid().ToString('N') + '.zip')
        $zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($entryName in @('a', 'a/b.txt')) {
                $writer = New-Object System.IO.StreamWriter($zip.CreateEntry($entryName).Open())
                try { $writer.Write('x') } finally { $writer.Dispose() }
            }
        } finally { $zip.Dispose() }
        { Get-TpmAutoSyncZipInventory -ZipPath $zipPath } | Should -Throw '*collision*'
        $close = @($script:fx10Events | Where-Object { $_.Complete -and $_.Label -eq 'AutoSync ZIP inventory' })
        $close.Count | Should -Be 1
        $close[0].Outcome | Should -Be 'Error'
    }

    It 'closes the PostgreSQL requirement scan Error when a profile could not be read (recovery blocked)' {
        $dir = Join-Path $TestDrive ('fx10-pg-' + [guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($dir)
        [System.IO.File]::WriteAllText((Join-Path $dir 'good.xml'), '<GameProfile><ConfigValues /></GameProfile>')
        [System.IO.File]::WriteAllText((Join-Path $dir 'bad.xml'), '<GameProfile />')
        $result = Get-TpmPostgresRequirementScan -ProfileFiles @(Get-ChildItem -LiteralPath $dir -Filter '*.xml' -File)
        $result.ScanBlocked | Should -BeTrue
        $close = @($script:fx10Events | Where-Object { $_.Complete -and $_.Label -eq 'PostgreSQL requirement profile scan' })
        $close.Count | Should -Be 1
        $close[0].Outcome | Should -Be 'Error'
    }

    It 'still closes the PostgreSQL requirement scan Final when every profile was read' {
        $dir = Join-Path $TestDrive ('fx10-pg-ok-' + [guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($dir)
        [System.IO.File]::WriteAllText((Join-Path $dir 'good.xml'), '<GameProfile><ConfigValues /></GameProfile>')
        $result = Get-TpmPostgresRequirementScan -ProfileFiles @(Get-ChildItem -LiteralPath $dir -Filter '*.xml' -File)
        $result.ScanBlocked | Should -BeFalse
        @($script:fx10Events | Where-Object { $_.Complete })[0].Outcome | Should -Be 'Final'
    }
}

Describe 'FIX10 MAJOR 1: a nested failure keeps the parent open' {
    BeforeAll {
        function Import-TpmProgressModule {}
        function Write-Log { param([string]$msg) }
        . ([scriptblock]::Create((Get-Fx10FunctionText -Name @('Invoke-TpmProgressGroup', 'Get-TpmProgressCloseState'))))
    }
    BeforeEach {
        Set-Fx10DefaultMocks
        $global:Fx10Now = [datetime]'2026-01-01T00:00:00'
        $global:Fx10Lines = New-Object System.Collections.Generic.List[string]
        $global:Fx10ActiveAfterInner = $null
        $global:Fx10TitleAfterInner = $null
        Mock Get-TpmProgressNow { $global:Fx10Now } -ModuleName TpmProgress
        Mock Test-TpmProgressOutputRedirected { $true } -ModuleName TpmProgress
        Mock Test-TpmProgressColorEnabled { $false } -ModuleName TpmProgress
        Mock Get-TpmProgressStyle { 'Ascii' } -ModuleName TpmProgress
        Mock Write-TpmProgressPlainLine { [void]$global:Fx10Lines.Add($Text) } -ModuleName TpmProgress
    }
    AfterEach {
        Stop-TpmProgressAbandoned
        Remove-Variable -Name Fx10Now, Fx10Lines, Fx10ActiveAfterInner, Fx10TitleAfterInner -Scope Global -ErrorAction SilentlyContinue
    }

    It 'records a nested Error on the parent, names the inner work, and closes FAILED only at the owner close' {
        Start-TpmProgressOperation -Title 'Outer' -Group | Out-Null
        Start-TpmProgressOperation -Title 'Inner' -Stage 'Work' | Out-Null
        Complete-TpmProgressOperation -State Error -Message 'disk full'
        Test-TpmProgressActive | Should -BeTrue
        $state = Get-TpmProgressState
        $state.Title | Should -Be 'Outer'
        $state.Depth | Should -Be 1
        $state.Outcome | Should -Be 'Error'
        $state.Stage | Should -Be 'Inner failed: disk full'
        $global:Fx10Lines[$global:Fx10Lines.Count - 1] | Should -Match 'Inner failed: disk full'
        # The closing state word is upper-case FAILED; the running "Inner failed" note is not a close.
        @($global:Fx10Lines | Where-Object { $_ -cmatch 'FAILED' }).Count | Should -Be 0
        Complete-TpmProgressOperation -State Final
        Test-TpmProgressActive | Should -BeFalse
        @($global:Fx10Lines | Where-Object { $_ -cmatch 'FAILED' }).Count | Should -Be 1
        $global:Fx10Lines[$global:Fx10Lines.Count - 1] | Should -Match '^X\s+Outer'
    }

    It 'keeps the parent on a nested cancel and closes it canceled, not done' {
        Start-TpmProgressOperation -Title 'Outer' -Group | Out-Null
        Start-TpmProgressOperation -Title 'Inner' | Out-Null
        Complete-TpmProgressOperation -State Cancelled
        Test-TpmProgressActive | Should -BeTrue
        Complete-TpmProgressOperation -State Final
        $global:Fx10Lines[$global:Fx10Lines.Count - 1] | Should -Match 'canceled'
        $global:Fx10Lines[$global:Fx10Lines.Count - 1] | Should -Not -Match 'done'
    }

    It 'abandons the whole operation from any depth' {
        Start-TpmProgressOperation -Title 'Outer' -Group | Out-Null
        Start-TpmProgressOperation -Title 'Inner' | Out-Null
        Stop-TpmProgressAbandoned
        Test-TpmProgressActive | Should -BeFalse
        $global:Fx10Lines[$global:Fx10Lines.Count - 1] | Should -Match 'FAILED'
    }

    It 'keeps the outer group bar while the outer action continues after an inner group returned a failure' {
        $result = Invoke-TpmProgressGroup -Title 'Outer' -Action {
            [void](Invoke-TpmProgressGroup -Title 'Inner' -Action { [pscustomobject]@{ Outcome = 'ACTION_REQUIRED' } })
            $global:Fx10ActiveAfterInner = Test-TpmProgressActive
            $global:Fx10TitleAfterInner = Get-TpmProgressTitle
            [pscustomobject]@{ Outcome = 'SUCCEEDED' }
        }
        $result.Outcome | Should -Be 'SUCCEEDED'
        $global:Fx10ActiveAfterInner | Should -BeTrue
        $global:Fx10TitleAfterInner | Should -Be 'Outer'
        Test-TpmProgressActive | Should -BeFalse
        # One closing line only, owned by the outer title, and it cannot claim success after the inner failure.
        @($global:Fx10Lines | Where-Object { $_ -cmatch 'FAILED' }).Count | Should -Be 1
        $global:Fx10Lines[$global:Fx10Lines.Count - 1] | Should -Match '^X\s+Outer'
    }

    It 'keeps the outer group bar when an inner group throws and the outer action recovers' {
        $result = Invoke-TpmProgressGroup -Title 'Outer' -Action {
            try { [void](Invoke-TpmProgressGroup -Title 'Inner' -Action { throw 'inner boom' }) } catch { }
            $global:Fx10ActiveAfterInner = Test-TpmProgressActive
            [pscustomobject]@{ Outcome = 'SUCCEEDED' }
        }
        $result.Outcome | Should -Be 'SUCCEEDED'
        $global:Fx10ActiveAfterInner | Should -BeTrue
        @($global:Fx10Lines | Where-Object { $_ -match 'Inner failed: inner boom' }).Count | Should -BeGreaterThan 0
        @($global:Fx10Lines | Where-Object { $_ -cmatch 'FAILED' }).Count | Should -Be 1
        $global:Fx10Lines[$global:Fx10Lines.Count - 1] | Should -Match '^X\s+Outer'
    }
}

Describe 'FIX10 MAJOR 2: background-aware color and measured glyph evidence' {
    BeforeEach { Set-Fx10DefaultMocks }

    It 'returns no palette for an unknown background, so nothing is colored' {
        Get-TpmProgressPalette -Background $null | Should -BeNullOrEmpty
        InModuleScope TpmProgress { Get-TpmProgressSegmentColor -Role 'fill' -State 'Error' -Background $null } | Should -BeNullOrEmpty
    }

    It 'uses dark state colors on light backgrounds and bright ones on dark backgrounds' {
        $light = Get-TpmProgressPalette -Background 'White'
        $light.Running | Should -Be 'DarkCyan'
        $light.Final | Should -Be 'DarkGreen'
        $light.Error | Should -Be 'DarkRed'
        $light.Track | Should -Be 'DarkGray'
        $dark = Get-TpmProgressPalette -Background 'Black'
        $dark.Running | Should -Be 'Cyan'
        $dark.Error | Should -Be 'Red'
        $dark.Track | Should -Be 'DarkGray'
    }

    It 'never draws in the background hue and keeps dark gray off dark backgrounds other than black' {
        (Get-TpmProgressPalette -Background 'DarkRed').Error | Should -BeNullOrEmpty
        (Get-TpmProgressPalette -Background 'Yellow').Warn | Should -BeNullOrEmpty
        (Get-TpmProgressPalette -Background 'Gray').Track | Should -BeNullOrEmpty
        (Get-TpmProgressPalette -Background 'DarkMagenta').Track | Should -BeNullOrEmpty
    }

    It 'uses the background-aware text palette while leaving count in the host foreground' {
        InModuleScope TpmProgress {
            foreach ($background in @('Black', 'White', 'DarkMagenta')) {
                $palette = Get-TpmProgressPalette -Background $background
                Get-TpmProgressSegmentColor -Role 'count' -State 'Running' -Background $background | Should -BeNullOrEmpty
                foreach ($entry in @(@('pct', 'Percent'), @('time', 'Time'), @('eta', 'Time'), @('label', 'Label'))) {
                    Get-TpmProgressSegmentColor -Role $entry[0] -State 'Running' -Background $background | Should -Be $palette[$entry[1]]
                }
            }
        }
    }

    It 'colors an operation only when the console background is known, even with color enabled' {
        Mock Test-TpmProgressOutputRedirected { $false } -ModuleName TpmProgress
        Mock Get-TpmProgressStyle { 'Ascii' } -ModuleName TpmProgress
        Mock Write-TpmProgressRaw {} -ModuleName TpmProgress
        Mock Get-TpmProgressCursor { [pscustomobject]@{ Left = 0; Top = 0 } } -ModuleName TpmProgress
        Mock Get-TpmProgressWidth { 79 } -ModuleName TpmProgress
        Mock Get-TpmProgressBufferWidth { 80 } -ModuleName TpmProgress
        Mock Get-TpmProgressWindowHeight { 25 } -ModuleName TpmProgress
        Mock Clear-TpmProgressCells { $true } -ModuleName TpmProgress
        Mock Set-TpmProgressCursor { $true } -ModuleName TpmProgress
        Mock Test-TpmProgressColorEnabled { $true } -ModuleName TpmProgress
        # Color also needs VT processing (FIX20B R3): pin it, so this test neither depends on nor changes the real console mode.
        Mock Test-TpmProgressVt { $true } -ModuleName TpmProgress
        Mock Get-TpmProgressBackground { $null } -ModuleName TpmProgress
        try {
            Start-TpmProgressOperation -Title 'Scan' | Out-Null
            (Get-TpmProgressState).ColorMode | Should -BeExactly 'None'
        } finally { Stop-TpmProgressAbandoned }
        Mock Get-TpmProgressBackground { 'White' } -ModuleName TpmProgress
        Mock Write-TpmProgressSegments {} -ModuleName TpmProgress
        try {
            Start-TpmProgressOperation -Title 'Scan' | Out-Null
            (Get-TpmProgressState).ColorMode | Should -Not -BeExactly 'None'
            (Get-TpmProgressState).Background | Should -Be 'White'
        } finally { Stop-TpmProgressAbandoned }
    }

    It 'refuses glyphs on a CJK double-byte code page and when the measured cell probe fails' {
        $savedWt = $env:WT_SESSION
        try {
            $env:WT_SESSION = 'fixture-session'
            Mock Test-TpmProgressOutputRedirected { $false } -ModuleName TpmProgress
            Mock Test-TpmProgressWideWriteAvailable { $true } -ModuleName TpmProgress
            Mock Test-TpmProgressGlyphCells { $true } -ModuleName TpmProgress
            Mock Get-TpmProgressOutputCodePage { 932 } -ModuleName TpmProgress
            (InModuleScope TpmProgress { Test-TpmProgressUnicodeVerified }) | Should -BeFalse
            Mock Get-TpmProgressOutputCodePage { 437 } -ModuleName TpmProgress
            (InModuleScope TpmProgress { Test-TpmProgressUnicodeVerified }) | Should -BeTrue
            Mock Test-TpmProgressGlyphCells { $false } -ModuleName TpmProgress
            (InModuleScope TpmProgress { Test-TpmProgressUnicodeVerified }) | Should -BeFalse
        } finally { $env:WT_SESSION = $savedWt }
    }

    Context 'cell probe' {
        BeforeEach {
            InModuleScope TpmProgress { $script:TpmProgressGlyphCells = $null }
            $global:Fx10Cursor = @{ Left = 0; Top = 5 }
            $global:Fx10CellsPerGlyph = 1
            $global:Fx10Probe = New-Object System.Collections.Generic.List[string]
            Mock Get-TpmProgressWidth { 79 } -ModuleName TpmProgress
            Mock Get-TpmProgressCursor { [pscustomobject]@{ Left = $global:Fx10Cursor.Left; Top = $global:Fx10Cursor.Top } } -ModuleName TpmProgress
            Mock Set-TpmProgressCursor { $global:Fx10Cursor.Left = $Left; $global:Fx10Cursor.Top = $Top; $true } -ModuleName TpmProgress
            Mock Write-TpmProgressProbe {
                [void]$global:Fx10Probe.Add($Text)
                foreach ($ch in $Text.ToCharArray()) { $global:Fx10Cursor.Left += $(if ([int]$ch -gt 127) { $global:Fx10CellsPerGlyph } else { 1 }) }
                $true
            } -ModuleName TpmProgress
        }
        AfterEach {
            InModuleScope TpmProgress { $script:TpmProgressGlyphCells = $null }
            Remove-Variable -Name Fx10Cursor, Fx10CellsPerGlyph, Fx10Probe -Scope Global -ErrorAction SilentlyContinue
        }

        It 'accepts glyphs only when each one advanced the cursor by exactly one cell, then blanks them and restores the cursor' {
            (InModuleScope TpmProgress { Test-TpmProgressGlyphCells }) | Should -BeTrue
            # The probe writes only glyphs (no ASCII), including the bar glyphs, and the cleanup blanks twice as many
            # cells, so even a double-width rendering is fully erased.
            $global:Fx10Probe.Count | Should -Be 2
            $global:Fx10Probe[0] | Should -Match ([regex]::Escape([string][char]0x2501))
            @($global:Fx10Probe[0].ToCharArray() | Where-Object { [int]$_ -le 127 }).Count | Should -Be 0
            $global:Fx10Probe[1] | Should -Be (' ' * (2 * $global:Fx10Probe[0].Length))
            $global:Fx10Cursor.Left | Should -Be 0
            $global:Fx10Cursor.Top | Should -Be 5
        }

        It 'rejects glyphs that a terminal draws two cells wide' {
            $global:Fx10CellsPerGlyph = 2
            (InModuleScope TpmProgress { Test-TpmProgressGlyphCells }) | Should -BeFalse
            $global:Fx10Cursor.Left | Should -Be 0
        }

        It 'does not probe (and does not accept glyphs) when the cursor cannot be read' {
            Mock Get-TpmProgressCursor { $null } -ModuleName TpmProgress
            (InModuleScope TpmProgress { Test-TpmProgressGlyphCells }) | Should -BeFalse
            $global:Fx10Probe.Count | Should -Be 0
        }
    }
}

Describe 'FIX10 MAJOR 3: the ETA belongs to the stage on screen' {
    BeforeEach {
        Set-Fx10DefaultMocks
        $global:Fx10Now = [datetime]'2026-01-01T00:00:00'
        $global:Fx10Lines = New-Object System.Collections.Generic.List[string]
        Mock Get-TpmProgressNow { $global:Fx10Now } -ModuleName TpmProgress
        Mock Test-TpmProgressOutputRedirected { $true } -ModuleName TpmProgress
        Mock Test-TpmProgressColorEnabled { $false } -ModuleName TpmProgress
        Mock Get-TpmProgressStyle { 'Ascii' } -ModuleName TpmProgress
        Mock Write-TpmProgressPlainLine { [void]$global:Fx10Lines.Add($Text) } -ModuleName TpmProgress
    }
    AfterEach {
        Stop-TpmProgressAbandoned
        Remove-Variable -Name Fx10Now, Fx10Lines -Scope Global -ErrorAction SilentlyContinue
    }

    It 'restarts the clock and samples when a differently named stage reuses the same total' {
        Start-TpmProgressOperation -Title 'Work' -Stage 'Stage A' -Total 100 | Out-Null
        foreach ($n in 1..4) {
            $global:Fx10Now = $global:Fx10Now.AddSeconds(10)
            Set-TpmProgressStage -Stage 'Stage A' -Current ($n * 10) -Total 100
        }
        $global:Fx10Lines[$global:Fx10Lines.Count - 1] | Should -Match 'ETA'
        Set-TpmProgressStage -Stage 'Stage B' -Current 40 -Total 100
        $state = Get-TpmProgressState
        $state.StageSamples | Should -Be 0
        $state.StageStarted | Should -Be $global:Fx10Now
        $global:Fx10Now = $global:Fx10Now.AddSeconds(5)
        Set-TpmProgressStage -Stage 'Stage B' -Current 50 -Total 100
        $global:Fx10Lines[$global:Fx10Lines.Count - 1] | Should -Match 'Stage B'
        $global:Fx10Lines[$global:Fx10Lines.Count - 1] | Should -Not -Match 'ETA'
    }

    It 'keeps the clock for a cosmetic relabel of the same work (-SameStage)' {
        Start-TpmProgressOperation -Title 'Work' -Stage 'Scan' -Total 4 | Out-Null
        $global:Fx10Now = $global:Fx10Now.AddSeconds(3)
        Set-TpmProgressStage -Stage 'Scan' -Current 2 -Total 4
        $started = (Get-TpmProgressState).StageStarted
        $global:Fx10Now = $global:Fx10Now.AddSeconds(3)
        Set-TpmProgressStage -Stage 'Scan done' -Current 4 -Total 4 -SameStage
        (Get-TpmProgressState).StageStarted | Should -Be $started
        $global:Fx10Now = $global:Fx10Now.AddSeconds(1)
        Set-TpmProgressStage -Stage 'Scan done' -Current 4 -Total 4 -SameStage
        (Get-TpmProgressState).StageStarted | Should -Be $started
    }

    It 'hides the ETA after a text-only stage change until the new stage reports counts' {
        Start-TpmProgressOperation -Title 'Work' -Stage 'Copy' -Total 10 | Out-Null
        foreach ($n in 1..4) {
            $global:Fx10Now = $global:Fx10Now.AddSeconds(1)
            Set-TpmProgressStage -Stage 'Copy' -Current $n -Total 10
        }
        $global:Fx10Lines[$global:Fx10Lines.Count - 1] | Should -Match 'ETA'
        Set-TpmProgressStage -Stage 'Waiting for the child process' -StageOnly
        (Get-TpmProgressState).EtaHidden | Should -BeTrue
        Set-TpmProgressStage -Stage 'Copy' -Current 5 -Total 10
        (Get-TpmProgressState).EtaHidden | Should -BeFalse
    }

    It 'keeps the group stage clock when a leaf closes Final through the wrapper ("<label> done")' {
        function Import-TpmProgressModule {}
        . ([scriptblock]::Create((Get-Fx10FunctionText -Name @('Write-TpmCompactExtractionProgress'))))
        Start-TpmProgressOperation -Title 'Workflow' -Group | Out-Null
        Write-TpmCompactExtractionProgress -Phase Checking -Label 'Scan' -Current 1 -Total 2
        $started = (Get-TpmProgressState).StageStarted
        $global:Fx10Now = $global:Fx10Now.AddSeconds(10)
        Write-TpmCompactExtractionProgress -Phase Checking -Label 'Scan' -Current 2 -Total 2
        $global:Fx10Now = $global:Fx10Now.AddSeconds(5)
        Write-TpmCompactExtractionProgress -Phase Checking -Label 'Scan' -Current 2 -Total 2 -Complete
        $state = Get-TpmProgressState
        $state.Stage | Should -Be 'Scan done'
        $state.StageStarted | Should -Be $started
    }
}

Describe 'FIX10 MAJOR 4: live bar and other console output share the screen without collisions' {
    BeforeEach {
        Set-Fx10DefaultMocks
        $global:Fx10Now = [datetime]'2026-01-01T00:00:00'
        $global:Fx10Width = 80
        $global:Fx10Buffer = 81
        $global:Fx10Height = 30
        $global:Fx10Cursor = @{ Left = 0; Top = 10 }
        $global:Fx10Raw = New-Object System.Text.StringBuilder
        $global:Fx10ClearOk = $true
        # Emulated console: carriage return to column 0, line feed to the next row at column 0, other text advances.
        Mock Write-TpmProgressRaw {
            [void]$global:Fx10Raw.Append($Text)
            foreach ($ch in $Text.ToCharArray()) {
                if ($ch -eq [char]10) { $global:Fx10Cursor.Top++; $global:Fx10Cursor.Left = 0 }
                elseif ($ch -eq [char]13) { $global:Fx10Cursor.Left = 0 }
                else { $global:Fx10Cursor.Left++ }
            }
            if ($NewLine) { [void]$global:Fx10Raw.Append('<NL>'); $global:Fx10Cursor.Top++; $global:Fx10Cursor.Left = 0 }
        } -ModuleName TpmProgress
        Mock Get-TpmProgressNow { $global:Fx10Now } -ModuleName TpmProgress
        # Frame cost (adaptive throttle) is measured on the monotonic clock; keep it at 0 so the 100 ms floor applies.
        Mock Get-TpmProgressTimestamp { 0 } -ModuleName TpmProgress
        Mock Test-TpmProgressOutputRedirected { $false } -ModuleName TpmProgress
        Mock Test-TpmProgressColorEnabled { $false } -ModuleName TpmProgress
        Mock Get-TpmProgressStyle { 'Ascii' } -ModuleName TpmProgress
        Mock Get-TpmProgressBackground { 'Black' } -ModuleName TpmProgress
        Mock Get-TpmProgressWidth { $global:Fx10Width } -ModuleName TpmProgress
        Mock Get-TpmProgressBufferWidth { $global:Fx10Buffer } -ModuleName TpmProgress
        Mock Get-TpmProgressWindowHeight { $global:Fx10Height } -ModuleName TpmProgress
        Mock Get-TpmProgressCursor { [pscustomobject]@{ Left = $global:Fx10Cursor.Left; Top = $global:Fx10Cursor.Top } } -ModuleName TpmProgress
        Mock Set-TpmProgressCursor { $global:Fx10Cursor.Left = $Left; $global:Fx10Cursor.Top = $Top; $true } -ModuleName TpmProgress
        Mock Clear-TpmProgressCells { $global:Fx10ClearOk } -ModuleName TpmProgress
    }
    AfterEach {
        Stop-TpmProgressAbandoned
        Remove-Variable -Name Fx10Now, Fx10Width, Fx10Buffer, Fx10Height, Fx10Cursor, Fx10Raw, Fx10ClearOk -Scope Global -ErrorAction SilentlyContinue
    }

    It 'starts the first frame on a fresh line when text is pending mid-row (Write-Host -NoNewline)' {
        $global:Fx10Cursor.Left = 12
        Start-TpmProgressOperation -Title 'Scan' -Stage 'Files' -Total 10 | Out-Null
        $global:Fx10Raw.ToString() | Should -Match "^`n`r"
        $global:Fx10Cursor.Top | Should -Be 11
    }

    It 'takes the bar off its row before other output and redraws it on the row below that output' {
        Start-TpmProgressOperation -Title 'Scan' -Stage 'Files' -Total 10 | Out-Null
        $global:Fx10Cursor.Left | Should -Be 80
        Suspend-TpmProgressOutput | Should -BeTrue
        Should -Invoke Clear-TpmProgressCells -ModuleName TpmProgress -ParameterFilter { $Top -eq 10 -and $Count -eq 80 } -Times 1 -Exactly
        # The caller's text starts at column 0 of the bar's old row.
        $global:Fx10Cursor.Left | Should -Be 0
        $global:Fx10Cursor.Top | Should -Be 10
        # Simulate one full line of ordinary output.
        $global:Fx10Cursor.Top = 11
        $before = $global:Fx10Raw.Length
        Resume-TpmProgressOutput
        $redraw = $global:Fx10Raw.ToString().Substring($before)
        # The description column is right-aligned (padded on the left), so blanks may follow the spinner.
        $redraw | Should -Match "^`r\S\s+Scan"
        $redraw | Should -Not -Match "`n"
        $global:Fx10Cursor.Top | Should -Be 11
    }

    It 'falls back to a fresh line when the bar cannot be blanked, so the output still never starts after the bar' {
        Start-TpmProgressOperation -Title 'Scan' -Stage 'Files' -Total 10 | Out-Null
        $global:Fx10ClearOk = $false
        Suspend-TpmProgressOutput | Should -BeTrue
        $global:Fx10Raw.ToString() | Should -Match '<NL>$'
        $global:Fx10Cursor.Left | Should -Be 0
    }

    It 'does not redraw after output that ended mid-row' {
        Start-TpmProgressOperation -Title 'Scan' -Stage 'Files' -Total 10 | Out-Null
        [void](Suspend-TpmProgressOutput)
        $global:Fx10Cursor.Left = 7
        $before = $global:Fx10Raw.Length
        Resume-TpmProgressOutput
        $global:Fx10Raw.Length | Should -Be $before
    }

    It 'relocates a frame that the console reflowed onto two rows when the window narrowed, and redraws it in place' {
        Start-TpmProgressOperation -Title 'Scan' -Stage 'Files' -Total 10 | Out-Null
        # Narrow to 41 columns: the 80-cell frame now wraps; the cursor keeps its offset 80 = row +1, column 39.
        $global:Fx10Width = 40; $global:Fx10Buffer = 41
        $global:Fx10Cursor.Left = 39; $global:Fx10Cursor.Top = 11
        $global:Fx10Now = $global:Fx10Now.AddSeconds(1)
        Set-TpmProgressStage -Stage 'Files' -Current 3 -Total 10
        Should -Invoke Clear-TpmProgressCells -ModuleName TpmProgress -ParameterFilter { $Top -eq 10 -and $Count -eq 80 } -Times 1 -Exactly
        $global:Fx10Raw.ToString() | Should -Not -Match "`n"
        $global:Fx10Cursor.Top | Should -Be 10
        $global:Fx10Cursor.Left | Should -Be 40
    }

    It 'relocates the frame after a height-only change moved its row' {
        Start-TpmProgressOperation -Title 'Scan' -Stage 'Files' -Total 10 | Out-Null
        $global:Fx10Height = 20
        $global:Fx10Cursor.Top = 4
        $global:Fx10Now = $global:Fx10Now.AddSeconds(1)
        $before = $global:Fx10Raw.Length
        Set-TpmProgressStage -Stage 'Files' -Current 3 -Total 10
        # FIX24: same width and buffer width, so the one-row frame found on row 4 is overwritten in place from column 0
        # (carriage return on the cursor row) and never erased first: no cell is blanked.
        Should -Invoke Clear-TpmProgressCells -ModuleName TpmProgress -Times 0 -Exactly
        $redraw = $global:Fx10Raw.ToString().Substring($before)
        $redraw | Should -Match "^`r\S\s+Scan: Files"
        $redraw | Should -Match '3/10'
        $global:Fx10Raw.ToString() | Should -Not -Match "`n"
        $global:Fx10Cursor.Top | Should -Be 4
        (InModuleScope TpmProgress { $script:TpmProgressOp.Live.Frame.FrameTop }) | Should -Be 4
    }

    It 'never overdraws output written by someone else: it starts a fresh line and blanks nothing' {
        Start-TpmProgressOperation -Title 'Scan' -Stage 'Files' -Total 10 | Out-Null
        $global:Fx10Cursor.Left = 12; $global:Fx10Cursor.Top = 13
        $global:Fx10Now = $global:Fx10Now.AddSeconds(1)
        Set-TpmProgressStage -Stage 'Files' -Current 3 -Total 10
        Should -Invoke Clear-TpmProgressCells -ModuleName TpmProgress -Times 0 -Exactly
        $global:Fx10Raw.ToString() | Should -Match "`n`r"
    }
}

Describe 'FIX10 MAJOR 4: the manager Write-Host proxy coordinates with an open bar' {
    BeforeAll {
        function Suspend-TpmProgressOutput { [void]$script:fx10Calls.Add('suspend'); return $script:fx10Lifted }
        function Resume-TpmProgressOutput { [void]$script:fx10Calls.Add('resume') }
        function Clear-TpmWorkflowFooter { param($Context) }
        function Render-TpmWorkflowStatus { param($Context) }
        . ([scriptblock]::Create((Get-Fx10FunctionText -Name @('Write-Host'))))
    }
    BeforeEach {
        Set-Fx10DefaultMocks
        $script:fx10Calls = New-Object System.Collections.Generic.List[string]
        $script:fx10Lifted = $true
        $script:ActiveTpmWorkflowStatus = $null
        $script:TpmWorkflowRendering = $false
        $script:TpmProgressModuleImported = $true
    }

    It 'lifts the bar before the text and redraws it after' {
        Write-Host 'fixture line' 6>$null
        ($script:fx10Calls -join ',') | Should -Be 'suspend,resume'
    }

    It 'does not redraw when no bar was lifted' {
        $script:fx10Lifted = $false
        Write-Host 'fixture line' 6>$null
        ($script:fx10Calls -join ',') | Should -Be 'suspend'
    }

    It 'does nothing extra before the progress module was imported' {
        $script:TpmProgressModuleImported = $false
        Write-Host 'fixture line' 6>$null
        $script:fx10Calls.Count | Should -Be 0
    }
}

Describe 'FIX10 MINOR 2: a narrow failed line keeps a recognizable state word' {
    BeforeEach { Set-Fx10DefaultMocks }

    It 'never cuts FAILED into an ellipsis while the word fits' {
        foreach ($width in 8..27) {
            $line = Format-TpmProgressLine -Title 'Backup' -Stage 'A long fixture label' -Current 4 -Total 10 -State Error -Width $width
            $line.Length | Should -Be $width
            $line | Should -Match '^X\s+FAILED'
        }
    }

    It 'shows the leading letters of a long state word instead of an ellipsis when it does not fit' {
        $line = Format-TpmProgressLine -Title 'Backup' -Stage 'Fixture' -Current 4 -Total 10 -State Incomplete -Width 10
        $line | Should -Be '! incomple'
    }
}

Describe 'FIX10 run-5 amendment: the real Import-TpmProgressModule keeps exactly one TpmProgress loaded' {
    BeforeEach { Set-Fx10DefaultMocks }
    BeforeAll {
        # The real helper resolves scripts\TpmProgress.psm1 beside the file that defines it ($PSScriptRoot), so it is
        # extracted into its own fixture folder next to a product copy of the module, exactly like the product layout.
        $script:fx10ImportRoot = Join-Path $TestDrive ('fx10-import-' + [guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory((Join-Path $script:fx10ImportRoot 'scripts'))
        Copy-Item -LiteralPath $script:fx10ModulePath -Destination (Join-Path $script:fx10ImportRoot 'scripts\TpmProgress.psm1')
        $script:fx10ProductModule = [System.IO.Path]::GetFullPath((Join-Path $script:fx10ImportRoot 'scripts\TpmProgress.psm1'))
        $script:fx10StaleRoot = Join-Path $TestDrive ('fx10-stale-' + [guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory((Join-Path $script:fx10StaleRoot 'scripts'))
        Copy-Item -LiteralPath $script:fx10ModulePath -Destination (Join-Path $script:fx10StaleRoot 'scripts\TpmProgress.psm1')
        $helperFile = Join-Path $script:fx10ImportRoot 'fx10-import-helper.ps1'
        [System.IO.File]::WriteAllText($helperFile, (Get-Fx10FunctionText -Name @('Import-TpmProgressModule')))
        . $helperFile
        $script:TpmProgressModuleImported = $false
        $script:TpmProgressModuleLoadedPath = ''
    }
    AfterAll {
        # Leave the session as the file-level BeforeAll set it: only the repository copy loaded.
        Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
        Import-Module $script:fx10ModulePath -Force -ErrorAction Stop
    }

    It 'replaces copies loaded from other paths by its own copy, leaving exactly one module with working commands' {
        # Run-5 situation: a stale fixture copy from an earlier test file is loaded beside (or instead of) the repository
        # copy under the same name. Whatever is loaded, the helper must end with only its own copy.
        Import-Module (Join-Path $script:fx10StaleRoot 'scripts\TpmProgress.psm1') -Force -ErrorAction Stop
        Import-TpmProgressModule
        $loaded = @(Get-Module -Name TpmProgress -All)
        $loaded.Count | Should -Be 1
        [System.IO.Path]::GetFullPath([string]$loaded[0].Path) | Should -Be $script:fx10ProductModule
        # Exported commands resolve and run after the helper returns.
        Test-TpmProgressActive | Should -BeFalse
        (Format-TpmProgressLine -Title 'Scan' -Stage 'Fixture' -Current 1 -Total 2 -Width 60).Length | Should -Be 60
        # Module-scoped mocks work again: exactly one module answers to the name.
        { InModuleScope TpmProgress { $script:TpmProgressOp } } | Should -Not -Throw
    }

    It 'reuses its own copy on later calls, so an open operation keeps its state' {
        Import-TpmProgressModule
        $before = @(Get-Module -Name TpmProgress -All)
        $before.Count | Should -Be 1
        Mock Test-TpmProgressOutputRedirected { $true } -ModuleName TpmProgress
        Mock Write-TpmProgressPlainLine {} -ModuleName TpmProgress
        try {
            Start-TpmProgressOperation -Title 'Survive' -Stage 'Files' -Total 3 | Out-Null
            Set-TpmProgressStage -Stage 'Files' -Current 2 -Total 3
            Import-TpmProgressModule
            Import-TpmProgressModule
            $after = @(Get-Module -Name TpmProgress -All)
            $after.Count | Should -Be 1
            [System.IO.Path]::GetFullPath([string]$after[0].Path) | Should -Be ([System.IO.Path]::GetFullPath([string]$before[0].Path))
            # A re-import would have reset the module state; the open operation proves the loaded copy was kept.
            Test-TpmProgressActive | Should -BeTrue
            $state = Get-TpmProgressState
            $state.Title | Should -Be 'Survive'
            $state.Current | Should -Be 2
            $state.Total | Should -Be 3
        } finally { Stop-TpmProgressAbandoned }
        Test-TpmProgressActive | Should -BeFalse
    }
}
