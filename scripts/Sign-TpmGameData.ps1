<#
Signs, or checks the signature of, the game-rules data file. Owner tool.

Sign:    .\scripts\Sign-TpmGameData.ps1 -DataPath game-data\TpmGameRules.json -PrivateKeyPath <path to your private key file>
Check:   .\scripts\Sign-TpmGameData.ps1 -DataPath game-data\TpmGameRules.json -Verify

The private key file is supplied by the owner at run time. It is never created here, never copied, never printed and never
belongs in the repository (docs\GAME-RULES-UPDATE.md says how to create it once and where to keep it).
The file is checked with the same strict rules TPM uses (taken from TeknoParrot-Manager.ps1, so there is one copy of the rules)
and is refused if it would not pass. The signature is RSA / SHA-256 / PKCS#1 v1.5 over the exact bytes of the file, written as
base64 to <DataPath>.sig. The signature is then checked against the public key built into TeknoParrot-Manager.ps1; if that key is
missing or is a different key, the script says so, because TPM would reject the file.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$DataPath,
    [string]$PrivateKeyPath = '',
    [string]$SignaturePath = '',
    [switch]$Verify,
    [string]$ManagerScriptPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ManagerScriptPath)) { $ManagerScriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'TeknoParrot-Manager.ps1' }
if ([string]::IsNullOrWhiteSpace($SignaturePath)) { $SignaturePath = $DataPath + '.sig' }

# Load TPM's own validator functions and built-in public key from the manager script without running it.
$tokens = $null; $parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path -LiteralPath $ManagerScriptPath).Path, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw 'The manager script could not be parsed.' }
$wanted = @('Test-TpmGameRulesSignature', 'Test-TpmGameRulesDocument')
$functionText = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in $wanted }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n"
if ([regex]::Matches($functionText, '(?m)^function ').Count -ne $wanted.Count) { throw 'The game-rules checking functions were not found in the manager script.' }
. ([scriptblock]::Create($functionText))
$assignments = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -in @('$TpmGameRulesPublicKeyXml', '$TpmGameRulesMaxBytes') }, $true))
$script:TpmGameRulesMaxBytes = 0
$embeddedKey = ''
foreach ($assignment in $assignments) {
    if ($assignment.Left.Extent.Text -eq '$TpmGameRulesMaxBytes') { $script:TpmGameRulesMaxBytes = [int](& ([scriptblock]::Create($assignment.Right.Extent.Text))) }
    else { $embeddedKey = [string](& ([scriptblock]::Create($assignment.Right.Extent.Text))) }
}
if ($script:TpmGameRulesMaxBytes -le 0) { throw 'The size limit was not found in the manager script.' }

$dataBytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $DataPath).Path)
$checked = Test-TpmGameRulesDocument -DataBytes $dataBytes
if (-not $checked.Valid) { throw "The data file would be rejected by TeknoParrot Manager: $($checked.Error)" }

if ($Verify) {
    if ([string]::IsNullOrWhiteSpace($embeddedKey)) { throw 'No public key is built into TeknoParrot-Manager.ps1 yet, so nothing can be verified.' }
    $sigBytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $SignaturePath).Path)
    if (-not (Test-TpmGameRulesSignature -DataBytes $dataBytes -SignatureBytes $sigBytes -PublicKeyXml $embeddedKey)) { throw 'The signature does NOT match the data file under the key built into TeknoParrot Manager.' }
    Write-Host ("OK: version {0}, signature matches the key built into TeknoParrot Manager." -f $checked.Document.Version)
    return
}

if ([string]::IsNullOrWhiteSpace($PrivateKeyPath)) { throw 'Give -PrivateKeyPath (your private key file), or use -Verify.' }
$rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
try {
    $rsa.FromXmlString([System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $PrivateKeyPath).Path))
    if ($rsa.PublicOnly) { throw 'That key file holds only a public key. Use the private key file.' }
    if ($rsa.KeySize -lt 2048) { throw 'The key is smaller than 2048 bits.' }
    $signature = $rsa.SignData($dataBytes, 'SHA256')
    $publicXml = $rsa.ToXmlString($false)
} finally {
    $rsa.Dispose()
}
[System.IO.File]::WriteAllText($SignaturePath, [System.Convert]::ToBase64String($signature), (New-Object System.Text.UTF8Encoding $false))
if (-not (Test-TpmGameRulesSignature -DataBytes $dataBytes -SignatureBytes ([System.IO.File]::ReadAllBytes($SignaturePath)) -PublicKeyXml $publicXml)) { throw 'The new signature did not verify under its own public key. Nothing should be published.' }
Write-Host ("Signed version {0}: {1}" -f $checked.Document.Version, $SignaturePath)
if ([string]::IsNullOrWhiteSpace($embeddedKey)) {
    Write-Warning 'No public key is built into TeknoParrot-Manager.ps1 yet. TeknoParrot Manager ignores this file until the public key below is pasted into $TpmGameRulesPublicKeyXml.'
    Write-Host $publicXml
} elseif (-not (Test-TpmGameRulesSignature -DataBytes $dataBytes -SignatureBytes ([System.IO.File]::ReadAllBytes($SignaturePath)) -PublicKeyXml $embeddedKey)) {
    throw 'This private key does not match the public key built into TeknoParrot Manager, so TeknoParrot Manager would reject the file. Do not publish it.'
} else {
    Write-Host 'The signature matches the public key built into TeknoParrot Manager.'
}
