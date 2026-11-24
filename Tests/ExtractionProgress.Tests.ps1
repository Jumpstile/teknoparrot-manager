#Requires -Module Pester
# Unpacking a game ZIP: the progress line counts bytes, always gets closed, and Ctrl+C reads "canceled", not "failed".
# The real Expand-ZipFileSafe runs on small ZIPs under $TestDrive; only the progress display is recorded.

BeforeAll {
    $sourcePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'TeknoParrot-Manager.ps1'
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw ($errors -join '; ') }
    $text = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    . ([scriptblock]::Create($text))
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    function Write-Log { param([string]$Message) }
    function Write-TpmCompactExtractionProgress { param($Phase, $Label, $Current, $Total, $StartedAt, [switch]$Complete, $Outcome, $Unit, [switch]$Completed) }
    function Test-TpmProgressCancellationError { param($ErrorRecord) $ErrorRecord.Exception -is [System.OperationCanceledException] }

    function New-ProgressZip {
        param([string]$Path, [hashtable]$Files)
        $zip = [System.IO.Compression.ZipFile]::Open($Path, 'Create')
        try {
            foreach ($name in $Files.Keys) {
                $entry = $zip.CreateEntry($name)
                $w = New-Object System.IO.StreamWriter($entry.Open())
                try { $w.Write($Files[$name]) } finally { $w.Dispose() }
            }
        } finally { $zip.Dispose() }
    }
}

Describe 'Unpacking progress' {
    BeforeEach {
        $script:Calls = New-Object System.Collections.Generic.List[object]
        Mock Write-TpmCompactExtractionProgress {
            $script:Calls.Add([pscustomobject]@{ Complete = [bool]$Complete; Outcome = $Outcome; Unit = $Unit; Current = $Current; Total = $Total })
        }
        $script:Zip = Join-Path $TestDrive ('p-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.zip')
        $script:Dest = Join-Path $TestDrive ('d-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    }

    It 'counts bytes and closes the line once as finished, with everything counted' {
        New-ProgressZip -Path $script:Zip -Files @{ 'a.bin' = ('x' * 100); 'b.bin' = ('y' * 300) }
        Expand-ZipFileSafe -ZipPath $script:Zip -DestDir $script:Dest -GameName 'Game'
        $updates = @($script:Calls | Where-Object { -not $_.Complete })
        $updates.Count | Should -Be 2
        @($updates | Where-Object { $_.Unit -ne 'Bytes' -or $_.Total -ne 400 }).Count | Should -Be 0
        $updates[0].Current | Should -Be 0
        $updates[1].Current | Should -BeIn @(100, 300)
        $done = @($script:Calls | Where-Object { $_.Complete })
        $done.Count | Should -Be 1
        $done[0].Outcome | Should -Be 'Final'
        $done[0].Current | Should -Be 400
        (Get-ChildItem -LiteralPath $script:Dest -File).Count | Should -Be 2
    }

    It 'closes the line as failed when the ZIP cannot be unpacked' {
        [IO.File]::WriteAllText($script:Zip, 'this is not a zip file')
        { Expand-ZipFileSafe -ZipPath $script:Zip -DestDir $script:Dest -GameName 'Game' } | Should -Throw
        $done = @($script:Calls | Where-Object { $_.Complete })
        $done.Count | Should -Be 1
        $done[0].Outcome | Should -Be 'Error'
    }

    It 'closes the line as canceled, not failed, when the player presses Ctrl+C' {
        New-ProgressZip -Path $script:Zip -Files @{ 'a.bin' = ('x' * 100); 'b.bin' = ('y' * 300) }
        Mock Write-TpmCompactExtractionProgress {
            $script:Calls.Add([pscustomobject]@{ Complete = [bool]$Complete; Outcome = $Outcome; Unit = $Unit; Current = $Current; Total = $Total })
            if (-not $Complete -and $Current -gt 0) { throw (New-Object System.OperationCanceledException) }
        }
        { Expand-ZipFileSafe -ZipPath $script:Zip -DestDir $script:Dest -GameName 'Game' } | Should -Throw
        $done = @($script:Calls | Where-Object { $_.Complete })
        $done.Count | Should -Be 1
        $done[0].Outcome | Should -Be 'Cancelled'
    }
}
