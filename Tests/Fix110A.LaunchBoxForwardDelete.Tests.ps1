#Requires -Module Pester

# FIX110A (B-3): a LaunchBox restore that has to remove a file the snapshot did not have (a file an earlier TeknoParrot Manager
#   run created) must never delete a newer save. The check and the delete are one step on one open file: the file must still be
#   the inventoried file (same file identity), still hold the inventoried bytes and still carry the inventoried write time.
#   A file that is no longer exactly that is kept, the restore is NOT reported as saved, and the error says why.
# The production script is parsed and only its function definitions are dot-sourced; no top-level product code runs.
# Everything lives under TestDrive with synthetic files. The race is simulated at the exact point between the check and the delete.
# Each It names the product change that makes it fail.
# What this CANNOT prove: a real LaunchBox or BigBox, or a second program racing in real time.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX110A tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:F110FunctionFile = Join-Path $TestDrive 'tpm-fix110a-lb-functions.ps1'
    [System.IO.File]::WriteAllText($script:F110FunctionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:F110FunctionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')

    $script:F110Created = '<LaunchBox><Platform><Name>Created by an earlier run</Name></Platform></LaunchBox>'
    $script:F110Newer = '<LaunchBox><Platform><Name>Saved by LaunchBox meanwhile</Name></Platform></LaunchBox>'

    # A LaunchBox library that holds one file the snapshot did not have (Data\Platforms\Fresh.xml).
    function New-F110LaunchBox {
        $root = Join-Path $TestDrive ('f110-lb-' + [guid]::NewGuid().ToString('N'))
        $library = Join-Path $root 'LaunchBox'
        [void][System.IO.Directory]::CreateDirectory((Join-Path $library 'Data\Platforms'))
        $fresh = Join-Path $library 'Data\Platforms\Fresh.xml'
        [System.IO.File]::WriteAllText($fresh, $script:F110Created)
        return [pscustomobject]@{ Root = $library; Backups = (Join-Path $root 'Backups'); Fresh = $fresh }
    }

    # $AtDelete runs between the deletion's check and its delete.
    function Invoke-F110ForwardDelete {
        param([Parameter(Mandatory)]$Fixture, [scriptblock]$AtDelete = $null)
        $script:F110AtDelete = $AtDelete
        $plan = [pscustomobject]@{
            RelativePath = 'Data\Platforms\Fresh.xml'; Changed = $true; Delete = $true
            Before = (Get-TpmLaunchBoxFileState -Path $Fixture.Fresh)
            Document = $null; Source = $null; SourceHash = $null; AfterHash = $null; BaseChildCount = 0
        }
        return (Invoke-TpmLaunchBoxFileTransaction -lbRoot $Fixture.Root -Plans @($plan) -BackupRoot $Fixture.Backups -Operation 'restore-safety')
    }
}

Describe 'FIX110A B-3: a LaunchBox restore removes only the exact file it inventoried' {
    BeforeEach {
        $script:F110AtDelete = $null
        Mock Write-Log {}
        Mock Test-LaunchBoxRunning { $false }
        Mock Write-TpmCompactExtractionProgress {}
        Mock Assert-TpmNoReparseWriteTarget {
            if ($Operation -eq 'LaunchBox restore deletion' -and $null -ne $script:F110AtDelete) { & $script:F110AtDelete $Path }
        }
        Mock Backup-LaunchBoxFiles {
            $backupDir = Join-Path $BackupRoot 'saved-copy'
            foreach ($item in $Items) {
                $from = Join-Path $lbRoot $item.RelativePath
                $to = Join-Path $backupDir $item.RelativePath
                [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($to))
                if (Test-Path -LiteralPath $from) { [System.IO.File]::Copy($from, $to) }
            }
            return [pscustomobject]@{ Path = $backupDir; Verified = $true }
        }
    }

    It 'removes an untouched file and reports the restore as saved' {
        # Mutation: refuse every forward deletion (for example a missing identity) -> the file stays and the restore is not saved.
        $fx = New-F110LaunchBox
        $r = Invoke-F110ForwardDelete -Fixture $fx
        $r.Outcome | Should -BeExactly 'SAVED'
        $r.FinalVerified | Should -BeTrue
        Test-Path -LiteralPath $fx.Fresh | Should -BeFalse
    }

    It 'keeps a newer save that has the very same bytes but is a different file' {
        # Mutation: check only the hash before the delete (delete by path) -> a file another program saved in its place is deleted when its bytes match.
        $fx = New-F110LaunchBox
        $r = Invoke-F110ForwardDelete -Fixture $fx -AtDelete {
            param($Path)
            $other = $Path + '.other'
            [System.IO.File]::WriteAllText($other, $script:F110Created)
            [System.IO.File]::Replace($other, $Path, [NullString]::Value)
        }
        $r.Outcome | Should -Not -BeExactly 'SAVED'
        $r.Succeeded | Should -BeFalse
        $r.FinalVerified | Should -BeFalse
        Test-Path -LiteralPath $fx.Fresh | Should -BeTrue
        [System.IO.File]::ReadAllText($fx.Fresh) | Should -BeExactly $script:F110Created
        ($r.Errors -join ' ') | Should -Match 'no longer the file that was inventoried'
        @($r.FailedPaths) | Should -Contain 'Data\Platforms\Fresh.xml'
    }

    It 'keeps a newer save with different bytes written in place and reports the library as not restored' {
        # Mutation: delete without comparing the bytes on the open file (or with Remove-Item by path) -> the newer save is deleted and the restore says saved.
        $fx = New-F110LaunchBox
        $r = Invoke-F110ForwardDelete -Fixture $fx -AtDelete {
            param($Path)
            [System.IO.File]::WriteAllText($Path, $script:F110Newer)
        }
        $r.Outcome | Should -Not -BeExactly 'SAVED'
        $r.Succeeded | Should -BeFalse
        Test-Path -LiteralPath $fx.Fresh | Should -BeTrue
        [System.IO.File]::ReadAllText($fx.Fresh) | Should -BeExactly $script:F110Newer
        @($r.UnrecoveredPaths) | Should -Contain 'Data\Platforms\Fresh.xml'
        ($r.Errors -join ' ') | Should -Match 'no longer the file that was inventoried'
    }

    It 'keeps a newer in-place save with the same file identity and the same bytes' {
        # Mutation: leave -ExpectedLastWriteTimeUtc out of the forward deletion -> identity and hash both match and the newer save is deleted.
        $fx = New-F110LaunchBox
        $script:F110IdentityBefore = $null
        $r = Invoke-F110ForwardDelete -Fixture $fx -AtDelete {
            param($Path)
            $script:F110IdentityBefore = Get-TpmFileIdentityString -Path $Path
            [System.IO.File]::WriteAllText($Path, $script:F110Created)
            [System.IO.File]::SetLastWriteTimeUtc($Path, [datetime]::UtcNow.AddMinutes(5))
        }
        (Get-TpmFileIdentityString -Path $fx.Fresh) | Should -BeExactly $script:F110IdentityBefore
        $r.Outcome | Should -Not -BeExactly 'SAVED'
        $r.Succeeded | Should -BeFalse
        Test-Path -LiteralPath $fx.Fresh | Should -BeTrue
        ($r.Errors -join ' ') | Should -Match 'rewritten|no longer the file that was inventoried'
    }

    It 'leaves the file alone when the identity of the inventoried file is unknown' {
        # Mutation: delete by path when no identity could be recorded -> a file that cannot be proven to be the inventoried one is deleted.
        Mock Get-TpmFileIdentityString { $null }
        $fx = New-F110LaunchBox
        $r = Invoke-F110ForwardDelete -Fixture $fx
        $r.Outcome | Should -Not -BeExactly 'SAVED'
        Test-Path -LiteralPath $fx.Fresh | Should -BeTrue
        ($r.Errors -join ' ') | Should -Match 'could not prove which file it inventoried'
    }
}
