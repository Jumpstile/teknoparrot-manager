param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)
$errors = $null
$tokens = $null
[System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors) | Out-Null
[pscustomobject]@{
    ErrorCount = $errors.Count
    Version    = $PSVersionTable.PSVersion.ToString()
} | ConvertTo-Json -Compress
