# FIX129: shared test helper (dot-sourced by the PostgreSQL tests that replace the tool runner with an in-memory fake).
# Since FIX129 a caller that must DECIDE from a tool's text passes -Interpret / -InterpretContext to
# Invoke-PostgresNativeCommand / Invoke-Postgres83RestoreCommand, and the real runner calls that block with the RAW result.
# A fake runner has to do the same, or the caller gets no answer and fails closed. This function is that one step: it runs the
# block on the fake's text and puts the answer on the result as Interpretation. Like the real tools, pg_restore.exe puts its text on
# standard error only and every other tool (psql) on standard output only, so a caller that reads the wrong stream fails here too.
# A block that throws leaves Interpretation $null, exactly like the real runner (fail closed).
function Add-FakePostgresInterpretation {
    param(
        [Parameter(Mandatory)]$Command,
        [scriptblock]$Interpret = $null,
        $InterpretContext = $null,
        [bool]$TimedOut = $false
    )
    if ($null -eq $Interpret) { return $Command }
    $text = [string]$Command.Output
    $tool = if ($null -ne $Command.PSObject.Properties['Tool']) { [string]$Command.Tool } elseif ($null -ne $Command.PSObject.Properties['ToolName']) { [string]$Command.ToolName } else { '' }
    $onStdErr = ($tool -ieq 'pg_restore.exe')
    $raw = [pscustomobject]@{ ExitCode = [int]$Command.ExitCode; TimedOut = $TimedOut; StdOut = $(if ($onStdErr) { '' } else { $text }); StdErr = $(if ($onStdErr) { $text } else { '' }); Output = $text }
    $interpretation = $null
    try { $interpretation = & $Interpret $raw $InterpretContext } catch { $interpretation = $null }
    $Command | Add-Member -NotePropertyName Interpretation -NotePropertyValue $interpretation -Force
    return $Command
}
