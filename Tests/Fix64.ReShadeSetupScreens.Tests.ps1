#Requires -Module Pester
# FIX64: the ReShade setup screens (menu 5). The owner's screenshot showed five progress rows with a red FAILED on a normal fallback step
# of the installer search, the same four-sentence signature paragraph twice, a five-line wall of preview text with one sentence twice, and
# no blank line between the parts. These tests drive the real product functions with fake consoles and fake files; nothing touches
# TeknoParrot, LaunchBox, the registry, services or the network. Each It names the product change that makes it fail.
# What this CANNOT prove: how a real console paints the rows (the existing FIX46 and FIX52 files drive the real writer on a fake surface).

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX64 bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'fix64-functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $script:DisplayVersion = 'v1.0 RC8'
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false
    $script:logPath = Join-Path $TestDrive 'fix64.log'
    $script:logWarnShown = $false

    # A synthetic installer: a small non-zip stub, optionally a decoy "PK" region, then a real ZIP archive (the shape of ReShade_Setup_<version>.exe).
    function New-Fix64Exe {
        param([string]$Path, [hashtable]$Entries, [switch]$Decoy)
        $stub = [System.Text.Encoding]::ASCII.GetBytes('FAKE-PE-STUB-NOT-A-ZIP')
        $prefix = if ($Decoy) { $stub + [byte[]](0x50, 0x4B, 0x03, 0x04) + [System.Text.Encoding]::ASCII.GetBytes('decoy-not-a-real-entry') } else { $stub }
        $zipTemp = Join-Path $TestDrive ('zt-{0}.zip' -f ([guid]::NewGuid().ToString('N')))
        $fs = [System.IO.File]::Open($zipTemp, [System.IO.FileMode]::CreateNew)
        try {
            $archive = [System.IO.Compression.ZipArchive]::new($fs, [System.IO.Compression.ZipArchiveMode]::Create)
            try {
                foreach ($name in $Entries.Keys) {
                    $entry = $archive.CreateEntry($name)
                    $writer = New-Object System.IO.StreamWriter($entry.Open())
                    try { $writer.Write($Entries[$name]) } finally { $writer.Dispose() }
                }
            } finally { $archive.Dispose() }
        } finally { $fs.Dispose() }
        [System.IO.File]::WriteAllBytes($Path, $prefix + [System.IO.File]::ReadAllBytes($zipTemp))
    }

    # The most logical lines in a row with no blank row between them. A row that only continues the sentence above it (its first word did not
    # fit in Limit characters, so it was wrapped) belongs to that line: a wrapped sentence is one line at every width. This can only count too
    # few lines (never too many), so a failure is always a real run of lines. Limit 0 counts every row.
    function Get-Fix64LongestRun {
        param([string[]]$Rows, [int]$Limit = 0)
        $longest = 0
        $run = 0
        $previous = ''
        foreach ($row in @($Rows)) {
            if ([string]::IsNullOrWhiteSpace($row)) { $run = 0; $previous = ''; continue }
            $firstWord = ($row.Trim() -split '\s+')[0]
            $continues = ($Limit -gt 0 -and $previous.Length -gt 0 -and ($previous.Length + 1 + $firstWord.Length) -gt $Limit)
            if (-not $continues) { $run++; if ($run -gt $longest) { $longest = $run } }
            $previous = [string]$row
        }
        return $longest
    }

    # What Get-TpmReShadeDllCheck returns for the 64-bit DLL (fixed values, so the expected text is exact).
    function New-Fix64Checks {
        param([string]$Status = 'UnknownError', [string]$Version64 = '6.8.0')
        return @([pscustomobject]@{ Label = '64-bit'; Present = $true; Version = $Version64; Status = $Status; Signer = '(none)'; Thumbprint = ('C3' * 20); Sha256 = ('1A' * 32) })
    }
}

Describe 'FIX64 installer search: a normal fallback step never shows as FAILED' {
    BeforeEach {
        $script:fix64Rows = New-Object System.Collections.Generic.List[object]
        Mock Write-Log {}
        Mock Invoke-TpmTransactionalPromote {}
        Mock Write-TpmCompactExtractionProgress {
            [void]$script:fix64Rows.Add([pscustomobject]@{ Label = $Label; Complete = [bool]$Complete; Outcome = $(if ($PesterBoundParameters.ContainsKey('Outcome')) { [string]$Outcome } else { 'Final' }) })
        }
    }

    It 'closes no progress row as failed when a decoy archive is skipped and the real archive is found' {
        # Mutation: make the outer catch of Expand-ReShadeSelfExtractingArchive close the candidate row with Outcome Error when a candidate is rejected
        # (an InvalidDataException) instead of moving on -> on both runtimes the decoy closes the shared row as FAILED (the owner's red "0/7 FAILED").
        # The entry-scan close of a decoy is guarded by the next test, which only means something on Windows PowerShell 5.1.
        $exe = Join-Path $TestDrive 'decoy-setup.exe'
        New-Fix64Exe -Path $exe -Entries @{ 'ReShade32.dll' = 'r32'; 'ReShade64.dll' = 'r64' } -Decoy
        Expand-ReShadeSelfExtractingArchive -SetupExePath $exe -DestDir (Join-Path $TestDrive 'decoy-out')
        Should -Invoke Invoke-TpmTransactionalPromote -Times 1 -Exactly
        @($script:fix64Rows | Where-Object { $_.Complete -and $_.Outcome -eq 'Error' }).Count | Should -Be 0
        $candidateCloses = @($script:fix64Rows | Where-Object { $_.Label -eq 'ReShade embedded archive candidates' -and $_.Complete })
        $candidateCloses.Count | Should -Be 1
        $candidateCloses[0].Outcome | Should -BeExactly 'Final'
    }

    It 'does not close the entry-scan row for a decoy that fails before its first entry row (Windows PowerShell 5.1 only)' -Skip:($PSVersionTable.PSEdition -eq 'Core') {
        # Skipped on PowerShell 7: .NET Core rejects the decoy inside the ZipArchive constructor, so the entry scan and its close are never reached and
        # this assertion would pass with or without the guard. On Windows PowerShell 5.1 the central directory is read lazily and the decoy throws inside the scan.
        # Mutation: replace "$entryScanRejected = ($entryCurrent -eq 0)" with "$entryScanRejected = $false" -> on 5.1 the decoy closes the entry-scan row as Error.
        $exe = Join-Path $TestDrive 'decoy-scan-setup.exe'
        New-Fix64Exe -Path $exe -Entries @{ 'ReShade32.dll' = 'r32'; 'ReShade64.dll' = 'r64' } -Decoy
        Expand-ReShadeSelfExtractingArchive -SetupExePath $exe -DestDir (Join-Path $TestDrive 'decoy-scan-out')
        $entryCloses = @($script:fix64Rows | Where-Object { $_.Label -eq 'ReShade embedded archive entry scan' -and $_.Complete })
        @($entryCloses | Where-Object { $_.Outcome -eq 'Error' }).Count | Should -Be 0 -Because 'the decoy was skipped on purpose'
        $entryCloses.Count | Should -Be 1 -Because 'only the real archive closes an entry-scan row'
    }

    It 'closes the entry-scan row as failed when an archive turns out to be bad after its entry rows started (both runtimes)' {
        # Mutation: set $entryScanRejected = $true again in the InvalidDataException catch (ignore $entryCurrent) -> the row is never closed and no FAILED close is seen.
        $script:fix72Thrown = $false
        Mock Write-TpmCompactExtractionProgress {
            if ($Label -eq 'ReShade embedded archive entry scan' -and -not $Complete -and -not $script:fix72Thrown) {
                $script:fix72Thrown = $true
                throw [System.IO.InvalidDataException]::new('simulated bad archive after the first entry row')
            }
            [void]$script:fix64Rows.Add([pscustomobject]@{ Label = $Label; Complete = [bool]$Complete; Outcome = $(if ($PesterBoundParameters.ContainsKey('Outcome')) { [string]$Outcome } else { 'Final' }) })
        }
        $exe = Join-Path $TestDrive 'bad-after-rows-setup.exe'
        New-Fix64Exe -Path $exe -Entries @{ 'ReShade32.dll' = 'r32'; 'ReShade64.dll' = 'r64' }
        { Expand-ReShadeSelfExtractingArchive -SetupExePath $exe -DestDir (Join-Path $TestDrive 'bad-after-rows-out') } | Should -Throw '*not found*'
        $script:fix72Thrown | Should -BeTrue -Because 'the fault was injected at the first entry row'
        $closes = @($script:fix64Rows | Where-Object { $_.Label -eq 'ReShade embedded archive entry scan' -and $_.Complete })
        $closes.Count | Should -Be 1
        $closes[0].Outcome | Should -BeExactly 'Error'
    }

    It 'closes no progress row as failed for a plain valid installer' {
        # Mutation: close the candidate row with Outcome Error whenever the loop stopped early (a break) -> the success path shows FAILED.
        $exe = Join-Path $TestDrive 'valid-setup.exe'
        New-Fix64Exe -Path $exe -Entries @{ 'ReShade32.dll' = 'r32'; 'ReShade64.dll' = 'r64' }
        Expand-ReShadeSelfExtractingArchive -SetupExePath $exe -DestDir (Join-Path $TestDrive 'valid-out')
        Should -Invoke Invoke-TpmTransactionalPromote -Times 1 -Exactly
        @($script:fix64Rows | Where-Object { $_.Complete -and $_.Outcome -ne 'Final' }).Count | Should -Be 0
        @($script:fix64Rows | Where-Object { $_.Complete }).Count | Should -BeGreaterThan 0
    }

    It 'still closes the candidate row as failed when the installer does not hold the expected DLLs' {
        # Mutation: set the candidate close back to Final whenever the loop ended normally (drop "and $extracted") -> this real failure shows a success row.
        $exe = Join-Path $TestDrive 'missing-setup.exe'
        New-Fix64Exe -Path $exe -Entries @{ 'SomeOtherFile.dll' = 'x' }
        { Expand-ReShadeSelfExtractingArchive -SetupExePath $exe -DestDir (Join-Path $TestDrive 'missing-out') } | Should -Throw '*not found*'
        $failed = @($script:fix64Rows | Where-Object { $_.Complete -and $_.Outcome -eq 'Error' })
        $failed.Count | Should -Be 1
        $failed[0].Label | Should -BeExactly 'ReShade embedded archive candidates'
        Should -Invoke Invoke-TpmTransactionalPromote -Times 0 -Exactly
    }

    It 'still closes the candidate row as failed when copying an extracted file fails' {
        # Mutation: set $candidateCurrentDone before the extraction work (or ignore it) -> a failure while copying shows a success row.
        Mock Copy-TpmZipEntryToFile { throw 'simulated copy failure' }
        $exe = Join-Path $TestDrive 'copyfail-setup.exe'
        New-Fix64Exe -Path $exe -Entries @{ 'ReShade32.dll' = 'r32'; 'ReShade64.dll' = 'r64' }
        { Expand-ReShadeSelfExtractingArchive -SetupExePath $exe -DestDir (Join-Path $TestDrive 'copyfail-out') } | Should -Throw '*simulated copy failure*'
        $failed = @($script:fix64Rows | Where-Object { $_.Complete -and $_.Outcome -eq 'Error' })
        $failed.Count | Should -Be 1
        $failed[0].Label | Should -BeExactly 'ReShade embedded archive candidates'
    }
}

Describe 'FIX64 wrapping and the short DLL notice' {
    It 'wraps with a hanging indent and never writes a row wider than <Width>, even for a 64-character hash' -ForEach @(
        @{ Width = 40 }
        @{ Width = 60 }
        @{ Width = 120 }
    ) {
        # Mutation: stop breaking a word that is longer than the room in Get-TpmReShadeHangingRows -> the SHA-256 runs past the width.
        $hash = ('AB' * 32)
        $rows = @(Get-TpmReShadeHangingRows -Text ('SHA-256: ' + $hash) -Width $Width -FirstPrefix '      ' -HangPrefix '          ')
        foreach ($row in $rows) { $row.Length | Should -BeLessOrEqual $Width -Because "width $Width"; $row | Should -Not -Match '\s$' }
        $rows[0] | Should -Match '^ {6}\S'
        foreach ($row in @($rows | Select-Object -Skip 1)) { $row | Should -Match '^ {10}\S' -Because 'continuation rows hang under the label text' }
        ((($rows | ForEach-Object { $_.Trim() }) -join '') -replace '\s', '') | Should -BeExactly ('SHA-256:' + $hash) -Because 'no character is lost by the wrap'
    }

    It 'keeps the text of an unknown width unchanged in one row' {
        # Mutation: normalize white space (or wrap) in the Width 0 branch -> the legacy single row changes.
        $rows = @(Get-TpmReShadeHangingRows -Text 'one  two' -Width 0 -FirstPrefix '  ' -HangPrefix '    ')
        $rows.Count | Should -Be 1
        $rows[0] | Should -BeExactly '  one  two'
    }

    It 'says the version and the signature once at <Width> columns' -ForEach @(
        @{ Width = 40 }
        @{ Width = 60 }
        @{ Width = 120 }
    ) {
        # Mutation: print the notice twice -> the signature sentence and the version appear twice.
        $lines = @(Get-TpmReShadeDllNoticeLines -Checks (New-Fix64Checks) -TextWidth $Width)
        foreach ($line in $lines) { $line.Text.Length | Should -BeLessOrEqual $Width -Because "width $Width" }
        $joined = (@($lines | ForEach-Object { $_.Text.Trim() }) -join ' ')
        ([regex]::Matches($joined, 'could not confirm who published the DLL')).Count | Should -Be 1
        ([regex]::Matches($joined, '6\.8\.0')).Count | Should -Be 1
        ([regex]::Matches($joined, '\[D\]')).Count | Should -Be 1
        $joined | Should -Match 'ReShade 6\.8\.0 is ready to use\.'
        $joined | Should -Not -Match 'does not automatically mean'
        $joined | Should -Not -Match 'SHA-256 is recorded'
    }

    It 'gives the exact one-line notice for the unverified and the valid case' {
        # Mutation: change the wording, the color, or the choice between the unverified and the confirmed sentence in Get-TpmReShadeDllNoticeLines.
        $unverified = @(Get-TpmReShadeDllNoticeLines -Checks (New-Fix64Checks) -TextWidth 0)
        $unverified.Count | Should -Be 2
        $unverified[0].Text | Should -BeExactly '  ReShade 6.8.0 is ready to use. Windows could not confirm who published the DLL, which is common for ReShade.'
        $unverified[0].Color | Should -BeExactly 'Yellow'
        $unverified[1].Text | Should -BeExactly '  Choose [D] below for the signature status, SHA-256 and thumbprint.'
        $valid = @(Get-TpmReShadeDllNoticeLines -Checks (New-Fix64Checks -Status 'Valid') -TextWidth 0)
        $valid[0].Text | Should -BeExactly '  ReShade 6.8.0 is ready to use. Windows confirmed the DLL signature.'
        $valid[0].Color | Should -BeExactly 'DarkGray'
    }

    It 'shows nothing when no DLL was found' {
        # Mutation: drop the Present filter in Get-TpmReShadeDllNoticeLines -> a notice about a file that does not exist.
        @(Get-TpmReShadeDllNoticeLines -Checks @([pscustomobject]@{ Label = '64-bit'; Present = $false; Version = ''; Status = ''; Signer = ''; Thumbprint = ''; Sha256 = '' }) -TextWidth 0).Count | Should -Be 0
    }
}

Describe 'FIX64 DLL details: readable blocks with every fact, common notes once' {
    It 'lists thumbprint, SHA-256, status and signer per DLL at <Width> columns, the installer signer once, and the notes once' -ForEach @(
        @{ Width = 40 }
        @{ Width = 60 }
        @{ Width = 120 }
    ) {
        # Mutation: drop the SHA-256 or Thumbprint row of Get-TpmReShadeDllDetailLines, or repeat the "What to do" note for each DLL.
        $installer = [pscustomobject]@{ Signer = 'CN=ReShade, E=info@reshade.me'; Thumbprint = ('D4' * 20) }
        $lines = @(Get-TpmReShadeDllDetailLines -Checks (New-Fix64Checks) -Installer $installer -TextWidth $Width)
        foreach ($line in $lines) { $line.Text.Length | Should -BeLessOrEqual $Width -Because "width $Width" }
        # wrapped hash and thumbprint rows are joined again, so the full values are found at any width
        $squashed = ((@($lines | ForEach-Object { $_.Text.Trim() }) -join '') -replace '\s', '')
        ([regex]::Matches($squashed, ('1A' * 32))).Count | Should -Be 1
        ([regex]::Matches($squashed, ('C3' * 20))).Count | Should -Be 1
        ([regex]::Matches($squashed, ('D4' * 20))).Count | Should -Be 1
        $joined = (@($lines | ForEach-Object { $_.Text.Trim() }) -join ' ')
        ([regex]::Matches($joined, 'What to do:')).Count | Should -Be 1
        ([regex]::Matches($joined, 'What it means:')).Count | Should -Be 1
        $joined | Should -Match 'Stop and replace the DLL if you do not trust where it came from'
        $joined | Should -Match '64-bit DLL -- version 6\.8\.0'
        $joined | Should -Match 'Signature: not verified by Windows \(status UnknownError\)'
        $joined | Should -Match 'recorded in the log'
    }

    It 'separates the blocks with a blank row and keeps each block short at <Width> columns' -ForEach @(
        @{ Width = 40 }
        @{ Width = 60 }
        @{ Width = 120 }
    ) {
        # Mutation: remove the blank-row separator between DLL blocks in Get-TpmReShadeDllDetailLines -> blocks run together (10 lines in a row).
        $installer = [pscustomobject]@{ Signer = 'CN=ReShade, E=info@reshade.me'; Thumbprint = ('D4' * 20) }
        $rows = @(Get-TpmReShadeDllDetailLines -Checks (New-Fix64Checks) -Installer $installer -TextWidth $Width | ForEach-Object { [string]$_.Text })
        foreach ($heading in @('    64-bit DLL -- version 6.8.0', '    Installer download')) {
            $at = [Array]::IndexOf($rows, $heading)
            $at | Should -BeGreaterThan 0 -Because $heading
            $rows[$at - 1] | Should -BeExactly '' -Because "$heading starts a new block"
        }
        (Get-Fix64LongestRun -Rows $rows -Limit $Width) | Should -BeLessOrEqual 5 -Because "wrapped rows count once at $Width columns"
    }

    It 'shows the confirmed signature without the unverified advice' {
        # Mutation: show the unverified advice for a confirmed signature.
        $rows = @(Get-TpmReShadeDllDetailLines -Checks (New-Fix64Checks -Status 'Valid') -TextWidth 0 | ForEach-Object { [string]$_.Text })
        $rows | Should -Contain '      Signature: valid -- Windows confirmed it'
        @($rows | Where-Object { $_ -like '*What to do:*' }).Count | Should -Be 0
    }

    It 'says Not found for a missing 64-bit DLL and never mentions 32-bit' {
        # Mutation: bring back the 32-bit wording in the missing-DLL row.
        $rows = @(Get-TpmReShadeDllDetailLines -Checks @([pscustomobject]@{ Label = '64-bit'; Present = $false; Version = ''; Status = ''; Signer = ''; Thumbprint = ''; Sha256 = '' }) -TextWidth 0 | ForEach-Object { [string]$_.Text })
        $rows | Should -Contain '    64-bit DLL'
        $rows | Should -Contain '      Not found'
        ($rows -join ' ') | Should -Not -Match '32-bit'
    }

    It 'has nothing to show without a DLL check and without installer evidence' {
        # Mutation: remove the early return -> an empty "ReShade files" heading.
        @(Get-TpmReShadeDllDetailLines -Checks @() -Installer $null -TextWidth 0).Count | Should -Be 0
    }
}

Describe 'FIX64 setup screen: the notice before the chooser' {
    BeforeEach {
        $script:fix64Screen = New-Object System.Collections.Generic.List[string]
        $script:fix64Log = New-Object System.Collections.Generic.List[string]
        $script:fix64ChooserChecks = $null
        $script:fix64Root = Join-Path $TestDrive ('setup-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path (Join-Path $script:fix64Root 'UserProfiles') -Force)
        $script:fix64Dll64 = Join-Path $script:fix64Root 'ReShade64.dll'
        [IO.File]::WriteAllText($script:fix64Dll64, 'fixture-64')
        $script:TpmOwnedLayout = [pscustomobject]@{ Assets = (Join-Path $script:fix64Root 'Assets') }
        Mock Write-Host { [void]$script:fix64Screen.Add([string]$Object) }
        Mock Write-Log { [void]$script:fix64Log.Add([string]$msg) }
        $script:fix64Width = 120
        Mock Get-TpmConsoleMetrics { [pscustomobject]@{ Width = $script:fix64Width; Left = 0; Top = 0; Height = 40; BufferWidth = $script:fix64Width; BufferHeight = 300 } }
        Mock Test-TpmNoReparsePath { $true }
        Mock Test-ReShadeDllSignature { [pscustomobject]@{ Status = 'UnknownError'; Signer = '(none)'; Thumbprint = $(if ($Path -like '*64.dll') { ('C3' * 20) } else { ('E5' * 20) }) } }
        Mock Invoke-ReShadeUpdateIfAvailable { param($SourceDll, $InstalledVersion) [pscustomobject]@{ Updated = $false; SourceDll = $SourceDll } }
        Mock Read-TpmReShadeState { [pscustomobject]@{ Favorites = @() } }
        Mock Get-TpmReShadeHdrGate { [pscustomobject]@{ State = 'HIDDEN'; Visible = $false; Enabled = $false; Reason = 'test'; Fingerprint = '' } }
        Mock Write-TpmCompactExtractionProgress {}
        Mock Show-TpmReShadeProfileGalleryWindow { [pscustomobject]@{ Available = $false; Reason = 'fixture' } }
        Mock Close-TpmReShadeProfileGallerySession {}
        Mock Read-TpmReShadeTerminalProfile { $script:fix64ChooserChecks = @($DllChecks); [pscustomobject]@{ Cancelled = $true; SelectedProfile = $null } }
    }
    AfterEach { $script:TpmOwnedLayout = $null }

    It 'prints one short notice for the DLL, no old paragraphs, no long unbroken block, and hands the facts to the chooser and the log' {
        # Mutation: restore the per-DLL Write-Host paragraphs in Invoke-ReShadeSetupLegacy -> the sentence appears twice and the old wording returns.
        # Mutation: stop passing -DllChecks to Read-TpmReShadeTerminalProfile -> the chooser's Details has no SHA-256 or thumbprint to show.
        $result = Invoke-ReShadeSetupLegacy -UserProfilesDir (Join-Path $script:fix64Root 'UserProfiles') -SourceDll $script:fix64Dll64
        $result.Reason | Should -BeExactly 'PROFILE_SELECTION_CANCELLED'
        $rows = @($script:fix64Screen)
        @($rows | Where-Object { $_ -like '*could not confirm who published the DLL*' }).Count | Should -Be 1
        @($rows | Where-Object { $_ -like '*Choose `[D`] below*' }).Count | Should -Be 1
        $text = $rows -join "`n"
        $text | Should -Not -Match 'could not be verified by Windows'
        $text | Should -Not -Match 'ReShade \((64|32)-bit\) :'
        $text | Should -Not -Match 'Technical signature status'
        $text | Should -Not -Match 'SHA-256 is recorded'
        $text | Should -Not -Match 'bundled-image approximation'
        $text | Should -Not -Match 'Preview gallery \('
        $rows[0] | Should -BeExactly '' -Because 'the notice is separated from what came before'
        (Get-Fix64LongestRun -Rows $rows) | Should -BeLessOrEqual 5
        $script:fix64ChooserChecks.Count | Should -Be 1
        $script:fix64ChooserChecks[0].Sha256 | Should -BeExactly ((Get-FileHash -LiteralPath $script:fix64Dll64 -Algorithm SHA256).Hash)
        $script:fix64ChooserChecks[0].Thumbprint | Should -BeExactly ('C3' * 20)
        @($script:fix64Log | Where-Object { $_ -like "ReShade (64-bit): signature=UnknownError*sha256=$((Get-FileHash -LiteralPath $script:fix64Dll64 -Algorithm SHA256).Hash)" }).Count | Should -Be 1
    }

    It 'keeps the notice before the chooser to a short run of lines at <Width> columns' -ForEach @(
        @{ Width = 40 }
        @{ Width = 60 }
        @{ Width = 120 }
    ) {
        # Mutation: print the notice, its pointer line and the Favorites line with no blank row between them (or restore the old per-DLL paragraphs) -> more than 5 lines in a row.
        $script:fix64Width = $Width
        $null = Invoke-ReShadeSetupLegacy -UserProfilesDir (Join-Path $script:fix64Root 'UserProfiles') -SourceDll $script:fix64Dll64
        $rows = @($script:fix64Screen)
        foreach ($row in $rows) { $row.Length | Should -BeLessOrEqual ($Width - 1) -Because "a notice row at $Width columns: '$row'" }
        $joined = (@($rows | ForEach-Object { $_.Trim() }) -join ' ')
        ([regex]::Matches($joined, 'could not confirm who published the DLL')).Count | Should -Be 1
        (Get-Fix64LongestRun -Rows $rows -Limit ($Width - 1)) | Should -BeLessOrEqual 5
    }
}

Describe 'FIX64 chooser screen and Details through the real chooser' {
    BeforeEach {
        $script:fix64Screen = New-Object System.Collections.Generic.List[string]
        $script:fix64Answers = New-Object 'System.Collections.Generic.Queue[string]'
        foreach ($answer in @('D', 'B')) { $script:fix64Answers.Enqueue($answer) }
        $script:fix64Width = 120
        $script:TpmReShadeInstallerEvidence = [pscustomobject]@{ Signer = 'CN=ReShade, E=info@reshade.me'; Thumbprint = ('D4' * 20) }
        Mock Write-Host { [void]$script:fix64Screen.Add([string]$Object) }
        Mock Write-TpmConsoleText { if ($Text -ne "`n") { [void]$script:fix64Screen.Add([string]$Text) } }
        Mock Get-TpmConsoleMetrics { [pscustomobject]@{ Width = $script:fix64Width; Left = 0; Top = 0; Height = 40; BufferWidth = $script:fix64Width; BufferHeight = 300 } }
        Mock Get-TpmConsoleCursorPosition { throw 'this fake console has no cursor' }
        Mock Test-TpmConsoleInputRedirected { $true }
        Mock Read-HostSafe { [void]$script:fix64Screen.Add('<<PROMPT>>'); $script:fix64Answers.Dequeue() }
        Mock Get-TpmReShadeHdrGate { [pscustomobject]@{ State = 'HIDDEN'; Visible = $false; Enabled = $false; Reason = 'test'; Fingerprint = '' } }
        Mock Write-Log {}
    }
    AfterEach { $script:TpmReShadeInstallerEvidence = $null }

    It 'draws a short intro once, a blank row between entries and a hanging indent at <Width> columns' -ForEach @(
        @{ Width = 40 }
        @{ Width = 60 }
        @{ Width = 120 }
    ) {
        # Mutation: remove the blank row between entries in Get-TpmReShadeTerminalMenuLines, or stop passing -TextWidth from Read-TpmReShadeTerminalProfile
        # (descriptions longer than the console are no longer wrapped under the entry).
        # Mutation: put the preview sentence back into the intro AND the old Write-Host lines -> "approximation" appears twice.
        $script:fix64Width = $Width
        $profiles = @(Get-TpmReShadeProfiles | Where-Object { -not $_.RequiresHdr })
        $null = Read-TpmReShadeTerminalProfile -Profiles $profiles -DefaultProfileId 'Original' -DllChecks (New-Fix64Checks)
        $all = @($script:fix64Screen)
        $firstPrompt = [Array]::IndexOf($all, '<<PROMPT>>')
        $firstPrompt | Should -BeGreaterThan 0
        $first = @($all[0..($firstPrompt - 1)])
        @($first | Where-Object { $_ -match 'approximation' }).Count | Should -Be 1
        @($first | Where-Object { $_ -match 'Nothing will be changed until you confirm' }).Count | Should -Be 1
        @($first | Where-Object { $_ -match 'synchronized' -or $_ -match 'Preview gallery' -or $_ -match 'beginner-friendly' }).Count | Should -Be 0
        $introAt = [Array]::IndexOf($first, '  Choose how your game should look. Nothing will be changed until you confirm.')
        $currentAt = -1
        for ($i = 0; $i -lt $first.Count; $i++) { if ($first[$i] -like '  Current selection:*') { $currentAt = $i } }
        $introAt | Should -BeGreaterThan 0
        $currentAt | Should -BeGreaterThan $introAt
        $first[$introAt - 1] | Should -BeExactly '' -Because 'the intro starts after a blank row'
        $menu = @($first[($introAt + 2)..($currentAt - 1)])
        $headings = @('Crt', 'Main' | ForEach-Object { '  ' + (Get-TpmReShadeProfileGroupLabel -Group $_) })
        $titles = 0
        for ($i = 0; $i -lt $menu.Count; $i++) {
            $row = $menu[$i]
            $row.Length | Should -BeLessOrEqual ($Width - 1) -Because "a menu row at $Width columns: '$row'"
            if ($row -match '^  \[\d+\] [ *] ') {
                $titles++
                if ($i -gt 0) { ($menu[$i - 1] -eq '' -or $headings -contains $menu[$i - 1]) | Should -BeTrue -Because "entry '$row' follows a blank row or its group heading" }
            } elseif ($row -ne '' -and $headings -notcontains $row) {
                $row | Should -Match '^ {6,}\S' -Because "text under an entry hangs under it: '$row'"
            }
        }
        $titles | Should -Be $profiles.Count
        $menu[$menu.Count - 1] | Should -BeExactly '' -Because 'a blank row separates the list from the Current selection line'
        $beforeSelection = @($first[0..($currentAt - 1)])
        (Get-Fix64LongestRun -Rows $beforeSelection -Limit ($Width - 1)) | Should -BeLessOrEqual 5 -Because "the intro and the list at $Width columns"
    }

    It 'shows every fact under Details in short blocks at <Width> columns, and returns to the chooser' -ForEach @(
        @{ Width = 40 }
        @{ Width = 60 }
        @{ Width = 120 }
    ) {
        # Mutation: remove the DLL block (or the -DllChecks parameter) from the chooser's Details -> no SHA-256 or thumbprint.
        # Mutation: drop the preview-window or catalog sentence from the Details -> the facts that moved out of the intro are lost.
        $script:fix64Width = $Width
        $profiles = @(Get-TpmReShadeProfiles | Where-Object { -not $_.RequiresHdr })
        $result = Read-TpmReShadeTerminalProfile -Profiles $profiles -DefaultProfileId 'Original' -DllChecks (New-Fix64Checks)
        $result.Cancelled | Should -BeTrue
        $all = @($script:fix64Screen)
        $prompts = @(for ($i = 0; $i -lt $all.Count; $i++) { if ($all[$i] -eq '<<PROMPT>>') { $i } })
        $prompts.Count | Should -Be 2
        $secondIntro = -1
        for ($i = $prompts[0] + 1; $i -lt $all.Count; $i++) { if ($all[$i] -eq '  Choose how your game should look. Nothing will be changed until you confirm.') { $secondIntro = $i; break } }
        $secondIntro | Should -BeGreaterThan $prompts[0] -Because 'the chooser is drawn again after the Details'
        $details = @($all[($prompts[0] + 1)..($secondIntro - 2)])
        foreach ($row in $details) { $row.Length | Should -BeLessOrEqual ($Width - 1) -Because "a Details row at $Width columns: '$row'" }
        $squashed = ((@($details | ForEach-Object { $_.Trim() }) -join '') -replace '\s', '')
        ([regex]::Matches($squashed, ('1A' * 32))).Count | Should -Be 1
        ([regex]::Matches($squashed, ('C3' * 20))).Count | Should -Be 1
        ([regex]::Matches($squashed, ('D4' * 20))).Count | Should -Be 1
        $joined = (@($details | ForEach-Object { $_.Trim() }) -join ' ')
        foreach ($fact in @(
            'a safe preview approximation using a bundled image',
            'does not run the game or execute ReShade shaders during preview',
            'compare Original/After or Split',
            'synchronized between the preview selector and the terminal list',
            'the v1.0 RC8 beginner-friendly catalog',
            'profiles built from',
            'never stacked automatically',
            'Stop and replace the DLL if you do not trust where it came from',
            'Cost: heavy (rough estimate, not measured).'
        )) { $joined | Should -BeLike ('*' + $fact + '*') -Because $fact }
        # every profile is its own block: a heading row after a blank row
        foreach ($label in @('Classic Arcade CRT [CRT Lottes]', 'Original', 'Fast CRT [CRT-ZFast]')) {
            $heading = @($details | Where-Object { $_ -ceq ('    ' + $label) })
            $heading.Count | Should -Be 1 -Because $label
            $details[[Array]::IndexOf($details, $heading[0]) - 1] | Should -BeExactly ''
        }
    }
}
