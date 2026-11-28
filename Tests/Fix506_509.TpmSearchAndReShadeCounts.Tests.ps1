#Requires -Module Pester
# Issue 506: first-run setup must find every TeknoParrot install on every local drive and let the player choose.
# Issue 509: the ReShade bulk result must reconcile "ready" with "set up" and name each game that was skipped at the last check.
# Temporary folders stand in for two drive roots; nothing touches TeknoParrot, LaunchBox or the network.
# What this CANNOT prove: real drive-type detection, a real console, or why the tester's four games changed state.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'RC95U2 bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'rc95u2-functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')

    function New-Rc95Install { param([string]$Path) [void][IO.Directory]::CreateDirectory($Path); [IO.File]::WriteAllText((Join-Path $Path 'TeknoParrotUi.exe'), 'stub') }
}

Describe 'TeknoParrot search on every drive (issue 506)' {
    BeforeEach {
        $script:SavedProfile = $env:USERPROFILE
        $env:USERPROFILE = Join-Path $TestDrive 'NoProfile'
        $script:DriveA = Join-Path $TestDrive ("A" + [guid]::NewGuid().ToString("N"))
        $script:DriveB = Join-Path $TestDrive ("B" + [guid]::NewGuid().ToString("N"))
        [void][IO.Directory]::CreateDirectory($script:DriveA)
        [void][IO.Directory]::CreateDirectory($script:DriveB)
    }
    AfterEach { $env:USERPROFILE = $script:SavedProfile }

    It 'finds the usual install, a nonstandard one, and one inside Games\Emulators, on two drives, without stopping at the first' {
        New-Rc95Install (Join-Path $script:DriveA 'Emulators\TeknoParrot')
        New-Rc95Install (Join-Path $script:DriveA 'Cabinet\TP Latest')
        New-Rc95Install (Join-Path $script:DriveB 'Games\Emulators\TeknoParrot')
        $found = Find-TeknoParrotRoot -DriveRoots @($script:DriveA, $script:DriveB)
        $found.Count | Should -Be 3
        $found | Should -Contain (Join-Path $script:DriveA 'Emulators\TeknoParrot')
        $found | Should -Contain (Join-Path $script:DriveA 'Cabinet\TP Latest')
        $found | Should -Contain (Join-Path $script:DriveB 'Games\Emulators\TeknoParrot')
    }

    It 'lists each install once and does not go looking inside an install or deep inside a game library' {
        New-Rc95Install (Join-Path $script:DriveA 'TeknoParrot')
        New-Rc95Install (Join-Path $script:DriveA 'TeknoParrot\Nested\TeknoParrot')
        New-Rc95Install (Join-Path $script:DriveB 'Library\Letter A\Game One\Extra\TeknoParrot')
        $found = Find-TeknoParrotRoot -DriveRoots @($script:DriveA, $script:DriveB)
        $found.Count | Should -Be 1
        $found[0] | Should -Be (Join-Path $script:DriveA 'TeknoParrot')
    }

    It 'stops a huge drive early, says so, and still keeps what it found' {
        New-Rc95Install (Join-Path $script:DriveA "Aaa")
        foreach ($n in 1..6) { [void][IO.Directory]::CreateDirectory((Join-Path $script:DriveA ('Zgame{0}' -f $n))) }
        $scan = Get-TpmTeknoParrotRootsOnDrive -DriveRoot $script:DriveA -MaxFolders 3
        $scan.LimitHit | Should -BeTrue
        @($scan.Roots) | Should -Contain (Join-Path $script:DriveA "Aaa")
        $full = Get-TpmTeknoParrotRootsOnDrive -DriveRoot $script:DriveA
        $full.LimitHit | Should -BeFalse
    }
}

Describe 'TeknoParrot chooser (issue 506)' {
    BeforeEach {
        $script:RootOne = Join-Path $TestDrive 'ChooseA\Emulators\TeknoParrot'
        $script:RootTwo = Join-Path $TestDrive 'ChooseB\TP'
        New-Rc95Install $script:RootOne
        New-Rc95Install $script:RootTwo
        $script:TpmLastRootSearch = [pscustomobject]@{ Drives = @('A:\', 'B:\'); LimitDrives = @() }
        $script:Said = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { $script:Said.Add([string]$Object) }
        Mock Write-Log { }
        Mock Find-TeknoParrotRoot { $l = New-Object System.Collections.ArrayList; [void]$l.Add($script:RootOne); [void]$l.Add($script:RootTwo); return ,$l }
        Mock Get-TpmInstalledTeknoParrotVersion { if ($TeknoParrotRoot -eq $script:RootOne) { '1.0.2.3' } else { '' } }
        Mock Exit-TpmProcess { }
    }

    It 'lists every install with drive, full path and version, and returns the one the player picks' {
        Mock Read-TpmChoice { '2' }
        $picked = Select-TpmTeknoParrotRoot
        $picked | Should -Be $script:RootTwo
        $text = $script:Said -join "`n"
        $text | Should -Match ([regex]::Escape(('1) Drive {0}  {1}  (version 1.0.2.3)' -f [IO.Path]::GetPathRoot($script:RootOne), $script:RootOne)))
        $text | Should -Match ([regex]::Escape(('2) Drive {0}  {1}  (version not readable)' -f [IO.Path]::GetPathRoot($script:RootTwo), $script:RootTwo)))
        $text | Should -Match 'Searched: A:\\, B:\\'
        $text | Should -Match 'Nothing is changed until you choose one'
    }

    It 'searches again on R and sends B to the type-or-browse question' {
        $script:Answers = New-Object System.Collections.Queue
        foreach ($a in 'R', 'B') { $script:Answers.Enqueue($a) }
        Mock Read-TpmChoice { $script:Answers.Dequeue() }
        Mock Read-TpmTeknoParrotRoot { 'X:\ByHand' }
        (Select-TpmTeknoParrotRoot) | Should -Be 'X:\ByHand'
        Should -Invoke Find-TeknoParrotRoot -Times 2 -Exactly
    }

    It 'quits on Q with nothing changed' {
        Mock Read-TpmChoice { 'Q' }
        (Select-TpmTeknoParrotRoot) | Should -BeNullOrEmpty
        Should -Invoke Exit-TpmProcess -Times 1 -Exactly
        ($script:Said -join "`n") | Should -Match 'Nothing was changed'
    }
}

Describe 'ReShade bulk counts add up (issue 509)' {
    BeforeAll {
        # The tester's run: 339 selected; check said 88 ready, 43 protected, 1 missing, 207 cannot be changed; 84 set up; 47 protected at the end.
        function New-Rc95Result {
            param([int]$Dropped = 4, [int]$UnknownArch = 0)
            $selected = @(1..339 | ForEach-Object { 'Game{0:D3}' -f $_ })
            $changed = @($selected | Select-Object -First (88 - $Dropped))
            $drops = @((1..[Math]::Max(1, $Dropped)) | Select-Object -First $Dropped | ForEach-Object { [pscustomobject]@{ Game = ('Dropped Game {0}' -f $_); Id = ('Drop{0}' -f $_); Kind = 'Protected'; Reason = 'ReShade files that TeknoParrot Manager did not install were found in the game folder, so nothing was changed.' } })
            return [pscustomobject]@{
                SelectedItems = $selected; ChangedItems = $changed; SkippedItems = @($selected | Select-Object -Skip (88 - $Dropped)); FailedItems = @()
                Deployed = (88 - $Dropped); Errors = 0; ErrorCount = 0
                Protected = (43 + $Dropped); Unsafe = 207; UnresolvedTarget = 0; MissingPath = 1; MissingDevice = 0; Unsupported = 0; LinuxStyle = 0; UnknownArch = $UnknownArch; KeptPrevious = 0
                SourceFolderItems = @(); UnverifiedItems = @(); NativeCrtNeedsRestoreItems = @(); NativeShaderWarnings = @()
                ReadyAtCheck = 88; DroppedAfterCheck = $drops
            }
        }
    }

    It 'shows first-check and last-check numbers apart, so 88 ready = 84 set up + 4 skipped, and 47 protected = 43 + 4' {
        $text = (@(Format-TpmReShadeBulkSummaryRows -Result (New-Rc95Result))) -join "`n"
        $text | Should -Match 'First check, before you confirmed: 88 ready, 251 left out\.'
        $text | Should -Match 'Of the 88 ready, 84 were set up and 4 were skipped at the last check'
        $text | Should -Match 'Protected: 47 in all, 43 at the first check and 4 more found at the last check\.'
    }

    It 'names every game skipped at the last check, with a plain reason' {
        $text = (@(Format-TpmReShadeBulkSummaryRows -Result (New-Rc95Result))) -join "`n"
        foreach ($n in 1..4) { $text | Should -Match ([regex]::Escape(('- Dropped Game {0}: ReShade files that TeknoParrot Manager did not install were found' -f $n))) }
    }

    It 'shows no last-check block when nothing was skipped after the first check' {
        $result = New-Rc95Result -Dropped 0
        $text = (@(Format-TpmReShadeBulkSummaryRows -Result $result)) -join "`n"
        $text | Should -Match 'Of the 88 ready, 88 were set up and 0 were skipped'
        $text | Should -Not -Match 'Skipped at the last check \('
    }

    It 'never calls a game whose program type could not be read 32-bit in the next-step advice' {
        $result = New-Rc95Result -Dropped 0 -UnknownArch 3
        $text = (@(Format-TpmReShadeBulkSummaryRows -Result $result)) -join "`n"
        $text | Should -Match 'program type could not be read'
        $text | Should -Not -Match '(?i)(not found or|are) 32-bit'
    }
}
