# Shared pcsx2x6 directory resolution for the TPM Certification Suite.
#
# Before this existed, Invoke-TPM-RealInstanceSmoke.ps1 resolved the pcsx2x6
# folder two different ways in the same run: backup and before/after
# snapshot both hardcoded the literal folder name "pcsx2x6", while the
# issue #79 verification block did a proper candidate search (pcsx2x6,
# PCSX2x6, pcsx2, PCSX2, then any pcsx2-prefixed folder) matching what the
# production script itself does. On an install where the real folder isn't
# literally named "pcsx2x6", that meant the backup and smoke-mode
# no-change snapshot silently missed the real folder while the #79 check
# still correctly found it -- an inconsistency Codex's review flagged
# (Priority action: "Resolve the PCSX2 directory once and reuse it
# consistently"). Invoke-TPM-InstallHealthCheck.ps1 carried its own
# separate copy of the same candidate-search logic. Both now dot-source
# this file and call Resolve-Pcsx2Directory once instead.
#
# A full module conversion (so this and the harness's other helper
# functions become properly importable rather than dot-sourced/AST-
# extracted) is tracked as post-1.0 technical debt -- this file is
# intentionally the minimal fix for the specific inconsistency Codex
# flagged as required before 1.0, not that larger refactor.

function Resolve-Pcsx2Directory {
    param([Parameter(Mandatory = $true)][string]$TeknoParrotRoot)

    $candidates = @('pcsx2x6', 'PCSX2x6', 'pcsx2', 'PCSX2')
    foreach ($candidate in $candidates) {
        $try = Join-Path $TeknoParrotRoot $candidate
        if (Test-Path -LiteralPath $try -PathType Container) { return $try }
    }

    return Get-ChildItem -LiteralPath $TeknoParrotRoot -Directory -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -imatch '^pcsx2' } | Select-Object -First 1 -ExpandProperty FullName
}
