param(
    [Parameter(Mandatory = $true)]
    [string[]]$Path,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)
$results = New-Object System.Collections.Generic.List[object]
foreach ($p in $Path) {
    try {
        $parseErrors = $null
        $tokens = $null
        [System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$tokens, [ref]$parseErrors) | Out-Null
        $errorCount = $parseErrors.Count
    } catch {
        $errorCount = -1
    }
    $results.Add([pscustomobject]@{
        Path       = $p
        ErrorCount = $errorCount
        Version    = $PSVersionTable.PSVersion.ToString()
    })
}
$payload = [pscustomobject]@{ Results = $results.ToArray() }
$json = $payload | ConvertTo-Json -Depth 4 -Compress
[IO.File]::WriteAllText($OutputPath, $json, (New-Object Text.UTF8Encoding($false)))
