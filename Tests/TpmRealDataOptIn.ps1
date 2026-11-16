# Real-data test opt-in (FIX107, FIX110A). Dot-sourced by a test file that has one optional real-data case.
#
# Tests are fixture-only. A test that reads data the tester already owns (a collection folder or .zip, for example) runs only when
# the tester asks for it on purpose, for that run:
#   1. set TPM_REAL_SOURCE_TESTS=1 (exactly 1; nothing else counts), and
#   2. set the case's own variable (for example TPM_CPS3_REAL_SOURCE) to the folder or file to read.
# TPM_REAL_DATA_TESTS=1 is NOT enough: that variable only allows the certification harness to read the TeknoParrot folder it is given, and
# the certification run clears it, TPM_REAL_SOURCE_TESTS and TPM_CPS3_REAL_SOURCE for its Pester child. A program cannot tell a value the
# tester set on purpose from one an earlier shell left behind, so the only protection is the separate variable and clearing it where a run
# must stay fixture-only. The case may read the source; it must not write to it, and Get-TpmSourceStamp lets the case prove that.

# Returns the path in the named variable only when the real-source opt-in is set and the path exists; otherwise ''.
function Get-TpmRealDataSource {
    param([Parameter(Mandatory)][string]$VariableName)
    if ([Environment]::GetEnvironmentVariable('TPM_REAL_SOURCE_TESTS') -cne '1') { return '' }
    $path = [Environment]::GetEnvironmentVariable($VariableName)
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) { return '' }
    return $path
}

# One text line per file under the path (one line when the path is a file): relative name, length, last write time, attributes and the
# SHA-256 of the content (empty for a folder). Two equal stamps mean nothing in the source was added, removed, resized or rewritten,
# even when a rewrite kept the length and restored the time. A folder or file that cannot be read makes this throw, never a short stamp.
function Get-TpmSourceStamp {
    param([Parameter(Mandatory)][string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    $files = if ($item.PSIsContainer) { @(Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction Stop) } else { @($item) }
    $base = if ($item.PSIsContainer) { $item.FullName.TrimEnd('\') } else { $item.DirectoryName.TrimEnd('\') }
    return @($files | Sort-Object FullName | ForEach-Object {
        $hash = if ($_.PSIsContainer) { '' } else { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256 -ErrorAction Stop).Hash }
        '{0}|{1}|{2}|{3}|{4}' -f $_.FullName.Substring($base.Length), $(if ($_.PSIsContainer) { 'dir' } else { $_.Length }), $_.LastWriteTimeUtc.Ticks, $_.Attributes, $hash
    })
}
