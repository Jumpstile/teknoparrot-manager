#Requires -Module Pester

# FIX107 (NEW-N1): `Preview-TPM-ProgressStyles.ps1 -LookOnly -Style <style>` draws the color look in the requested glyph style.
#   The look demo used to run before the requested style was applied and returned early for -LookOnly, so -Style Ascii on a host that
#   can draw glyphs still showed the glyph look.
# The preview script is run from a temporary folder next to a stub renderer module that only records which style the renderer was told to
# use each time a bar starts. Nothing is drawn, no product code runs, and nothing leaves $TestDrive.
# What this CANNOT prove: how the real renderer paints either style in a real console (that needs the owner's window).

BeforeAll {
    $script:F107PreviewSource = (Resolve-Path (Join-Path $PSScriptRoot '..\scripts\Preview-TPM-ProgressStyles.ps1')).Path
    $script:F107Folder = Join-Path $TestDrive ('preview-' + [guid]::NewGuid().ToString('N'))
    [void][System.IO.Directory]::CreateDirectory($script:F107Folder)
    Copy-Item -LiteralPath $script:F107PreviewSource -Destination (Join-Path $script:F107Folder 'Preview-TPM-ProgressStyles.ps1')
    $stub = @'
function Get-TpmProgressCapabilities { [pscustomobject]@{ Style = 'Unicode'; ColorMode = 'None' } }
function Get-TpmProgressStyle { 'Unicode' }
function Start-TpmProgressOperation { param([Parameter(ValueFromRemainingArguments = $true)]$Arguments) $global:F107StylesSeen += [string]$env:TPM_PROGRESS_STYLE }
function Add-TpmProgressTask { param([Parameter(ValueFromRemainingArguments = $true)]$Arguments) 1 }
function Set-TpmProgressStage { param([Parameter(ValueFromRemainingArguments = $true)]$Arguments) }
function Set-TpmProgressTask { param([Parameter(ValueFromRemainingArguments = $true)]$Arguments) }
function Complete-TpmProgressOperation { param([Parameter(ValueFromRemainingArguments = $true)]$Arguments) }
function Stop-TpmProgressAbandoned { }
function Suspend-TpmProgressOutput { $false }
function Resume-TpmProgressOutput { }
Export-ModuleMember -Function *
'@
    [System.IO.File]::WriteAllText((Join-Path $script:F107Folder 'TpmProgress.psm1'), $stub)
}

AfterAll {
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
}

Describe 'FIX107 N1 the look-only preview uses the requested glyph style' {
    BeforeEach {
        $global:F107StylesSeen = @()
        $script:F107SavedStyle = $env:TPM_PROGRESS_STYLE
        $env:TPM_PROGRESS_STYLE = $null
    }
    AfterEach {
        $env:TPM_PROGRESS_STYLE = $script:F107SavedStyle
        Remove-Variable -Name F107StylesSeen -Scope Global -ErrorAction SilentlyContinue
    }

    It 'draws the look in <Requested> when asked for -Style <Requested> -LookOnly, and puts the setting back' -ForEach @(
        @{ Requested = 'Ascii'; Expected = 'ascii' }
        @{ Requested = 'Unicode'; Expected = 'unicode' }
    ) {
        # Mutation: call the look demo before the requested style is applied (or return before it) -> the bars start with no style set and this list holds an empty entry.
        $env:TPM_PROGRESS_STYLE = 'block'
        & (Join-Path $script:F107Folder 'Preview-TPM-ProgressStyles.ps1') -LookOnly -Fast -Style $Requested 6>&1 | Out-Null
        @($global:F107StylesSeen).Count | Should -BeGreaterThan 0
        @($global:F107StylesSeen | Select-Object -Unique) | Should -Be @($Expected)
        $env:TPM_PROGRESS_STYLE | Should -BeExactly 'block'
    }

    It 'shows the look once per style for -Style Both, glyphs first' {
        # Mutation: show the look only once for -Style Both -> the ASCII look is never drawn.
        & (Join-Path $script:F107Folder 'Preview-TPM-ProgressStyles.ps1') -LookOnly -Fast -Style Both 6>&1 | Out-Null
        @($global:F107StylesSeen | Select-Object -Unique) | Should -Be @('unicode', 'ascii')
        $env:TPM_PROGRESS_STYLE | Should -BeNullOrEmpty
    }
}
