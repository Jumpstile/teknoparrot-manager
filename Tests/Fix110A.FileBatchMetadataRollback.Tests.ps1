#Requires -Module Pester

# FIX110A (S-4): the rollback of a file batch's metadata (the plugin ownership list) never overwrites a newer save.
#   After the commit step the batch records what the commit left on disk: its bytes, its write time and its file identity.
#   A rollback removes and restores the metadata only while the file is still exactly that. When another window saved
#   something else meanwhile (different bytes, or a different file with the same bytes and write time), that current state is
#   kept, the batch reports ACTION_REQUIRED (not a verified rollback) and the verified backup stays as recovery evidence.
# The production script is parsed and only its function definitions are dot-sourced; no top-level product code runs.
# Everything lives under TestDrive with synthetic files; the staging base is inside TestDrive, never the shared temp folder.
# Each It names the product change that makes it fail.
# What this CANNOT prove: a real second TeknoParrot Manager window racing in real time.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX110A tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $functionFile = Join-Path $TestDrive 'tpm-fix110a-batch-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')

    function Set-F110Text {
        param([string]$Path, [string]$Text)
        [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
    }

    # One plugin file is added next to an existing ownership list ("old-manifest").
    function New-F110BatchFixture {
        $root = Join-Path $TestDrive ('f110-batch-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $source = Join-Path $root 'source'
        $game = Join-Path $root 'game'
        [void][System.IO.Directory]::CreateDirectory($source)
        [void][System.IO.Directory]::CreateDirectory($game)
        $pluginSource = Join-Path $source 'plugin.dll'
        Set-F110Text -Path $pluginSource -Text 'plugin'
        $metadata = Join-Path $root 'ownership.json'
        Set-F110Text -Path $metadata -Text 'old-manifest'
        $hash = (Get-FileHash -LiteralPath $pluginSource -Algorithm SHA256).Hash
        $operation = [pscustomobject]@{
            ItemId = 'plugin'; Operation = 'ADD'; SourcePath = $pluginSource; DestinationPath = (Join-Path $game 'plugin.dll'); RootPath = $game
            ExpectedSourceHash = $hash; ExpectedFinalHash = $hash
        }
        return [pscustomobject]@{ Root = $root; Metadata = $metadata; Operation = $operation; Plugin = (Join-Path $game 'plugin.dll'); Staging = (Join-Path $root 'staging') }
    }

    function Invoke-F110Batch {
        param([Parameter(Mandatory)]$Fixture, [Parameter(Mandatory)][scriptblock]$Commit, [Parameter(Mandatory)][scriptblock]$Verify)
        return (Invoke-TpmTransactionalFileBatch -WorkflowKey 'F110Test' -OperationKey 'Metadata' -Operations @($Fixture.Operation) -MetadataPaths @($Fixture.Metadata) -StagingDir $Fixture.Staging -CommitAction $Commit -PostCommitVerification $Verify)
    }
}

Describe 'FIX110A S-4: the metadata rollback undoes only the commit it can prove' {
    BeforeEach {
        Mock Write-Log {}
        Mock Write-TpmCompactExtractionProgress {}
        $script:F110Metadata = $null
    }

    It 'restores the old metadata when the file is still exactly what the commit wrote' {
        # Mutation: refuse every metadata rollback (for example a missing committed identity) -> ACTION_REQUIRED instead of a verified rollback.
        $fx = New-F110BatchFixture
        $script:F110Metadata = $fx.Metadata
        $r = Invoke-F110Batch -Fixture $fx -Commit { Set-F110Text -Path $script:F110Metadata -Text 'new-manifest' } -Verify { throw 'simulated verification failure' }
        $r.Outcome | Should -Be 'ROLLED_BACK_VERIFIED'
        [System.IO.File]::ReadAllText($fx.Metadata) | Should -BeExactly 'old-manifest'
        Test-Path -LiteralPath $fx.Plugin | Should -BeFalse
    }

    It 'keeps another window''s newer metadata and reports that the rollback is not verified' {
        # Mutation: delete the current metadata and copy the old backup over it without checking it (the old behavior) -> the newer entries disappear.
        $fx = New-F110BatchFixture
        $script:F110Metadata = $fx.Metadata
        $r = Invoke-F110Batch -Fixture $fx -Commit { Set-F110Text -Path $script:F110Metadata -Text 'new-manifest' } -Verify {
            Set-F110Text -Path $script:F110Metadata -Text 'newer-manifest-from-another-window'
            throw 'simulated verification failure'
        }
        $r.Outcome | Should -Be 'ACTION_REQUIRED'
        @($r.Rollback.FailedItems) | Should -Contain 'metadata:ownership.json'
        [System.IO.File]::ReadAllText($fx.Metadata) | Should -BeExactly 'newer-manifest-from-another-window'
    }

    It 'keeps a different file that has the same bytes and the same write time as the commit' {
        # Mutation: compare only bytes and write time (no identity check on the deleting handle) -> a foreign file with matching bytes is deleted.
        $fx = New-F110BatchFixture
        $script:F110Metadata = $fx.Metadata
        $r = Invoke-F110Batch -Fixture $fx -Commit { Set-F110Text -Path $script:F110Metadata -Text 'new-manifest' } -Verify {
            $stamp = [System.IO.File]::GetLastWriteTimeUtc($script:F110Metadata)
            $other = $script:F110Metadata + '.other'
            Set-F110Text -Path $other -Text 'new-manifest'
            [System.IO.File]::SetLastWriteTimeUtc($other, $stamp)
            [System.IO.File]::Replace($other, $script:F110Metadata, [NullString]::Value)
            throw 'simulated verification failure'
        }
        $r.Outcome | Should -Be 'ACTION_REQUIRED'
        @($r.Rollback.FailedItems) | Should -Contain 'metadata:ownership.json'
        [System.IO.File]::ReadAllText($fx.Metadata) | Should -BeExactly 'new-manifest'
    }

    It 'keeps metadata it cannot prove the commit wrote when the commit itself failed after changing it' {
        # Mutation: treat any current metadata as this transaction's when the commit threw -> an unproven file is overwritten.
        $fx = New-F110BatchFixture
        $script:F110Metadata = $fx.Metadata
        $r = Invoke-F110Batch -Fixture $fx -Commit {
            Set-F110Text -Path $script:F110Metadata -Text 'changed-before-the-commit-failed'
            throw 'simulated commit failure'
        } -Verify { }
        $r.Outcome | Should -Be 'ACTION_REQUIRED'
        [System.IO.File]::ReadAllText($fx.Metadata) | Should -BeExactly 'changed-before-the-commit-failed'
    }

    It 'treats metadata that never changed as already rolled back' {
        # Mutation: remove and re-copy metadata even when it still equals the pre-state -> an unchanged file is touched (write time changes) or the rollback fails.
        $fx = New-F110BatchFixture
        $before = [System.IO.File]::GetLastWriteTimeUtc($fx.Metadata)
        $identityBefore = Get-TpmFileIdentityString -Path $fx.Metadata
        $r = Invoke-F110Batch -Fixture $fx -Commit { throw 'simulated commit failure' } -Verify { }
        $r.Outcome | Should -Be 'ROLLED_BACK_VERIFIED'
        [System.IO.File]::ReadAllText($fx.Metadata) | Should -BeExactly 'old-manifest'
        [System.IO.File]::GetLastWriteTimeUtc($fx.Metadata) | Should -Be $before
        (Get-TpmFileIdentityString -Path $fx.Metadata) | Should -BeExactly $identityBefore
    }

    It 'backs up and rolls back a metadata file whose attribute is Normal (as after a ZIP extract)' {
        # Mutation: remove the attribute match after the backup copy -> the batch stops at the backup check and the outcome is not ROLLED_BACK_VERIFIED.
        $fx = New-F110BatchFixture
        [System.IO.File]::SetAttributes($fx.Metadata, [System.IO.FileAttributes]::Normal)
        $script:F110Metadata = $fx.Metadata
        $r = Invoke-F110Batch -Fixture $fx -Commit { Set-F110Text -Path $script:F110Metadata -Text 'new-manifest' } -Verify { throw 'simulated verification failure' }
        $r.Outcome | Should -Be 'ROLLED_BACK_VERIFIED'
        [System.IO.File]::ReadAllText($fx.Metadata) | Should -BeExactly 'old-manifest'
        [int][System.IO.File]::GetAttributes($fx.Metadata) | Should -Be ([int][System.IO.FileAttributes]::Normal)
    }
}
