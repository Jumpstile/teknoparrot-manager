# =============================================================================
# TeknoParrot Manager backup-first updater helper
# =============================================================================
# This helper intentionally stays separate from TeknoParrot-Manager.ps1 for the
# first implementation pass so it can be reviewed and tested before being wired
# into the main menu. It never runs silently and never updates without -Apply.

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$CheckOnly,
    [switch]$Apply,
    [string]$ScriptPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'TeknoParrot-Manager.ps1'),
    [string]$Owner = 'Jumpstile',
    [string]$Repository = 'teknoparrot-manager',
    [string]$AssetNamePattern = '^TeknoParrot\.Manager\.v?\d+\.\d+\.\d+\.BETA\.zip$'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'TpmAutoUpdate.psm1') -Force

Invoke-TpmAutoUpdate `
    -CheckOnly:$CheckOnly `
    -Apply:$Apply `
    -ScriptPath $ScriptPath `
    -Owner $Owner `
    -Repository $Repository `
    -AssetNamePattern $AssetNamePattern `
    -WhatIf:$WhatIfPreference
