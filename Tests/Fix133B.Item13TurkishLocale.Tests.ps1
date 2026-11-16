
Describe 'Finding13' {
  BeforeAll {
    $script:src = (Join-Path (Split-Path -Parent $PSScriptRoot) 'TeknoParrot-Manager.ps1')
    $ast = [System.Management.Automation.Language.Parser]::ParseInput((Get-Content -Raw -LiteralPath $script:src), [ref]$null, [ref]$null)
    $fn = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-GameFiles' }, $true)
    . ([scriptblock]::Create(($fn | ForEach-Object { $_.Extent.Text }) -join "`n"))
    $script:d = Join-Path $TestDrive 'f13g'
    New-Item -ItemType Directory -Force $script:d | Out-Null
    foreach ($n in 'A.ISO','B.BIN') { New-Item -ItemType File -Force (Join-Path $script:d $n) | Out-Null }
  }
  It 'a: finds .ISO/.BIN under tr-TR' {
    $old = [Threading.Thread]::CurrentThread.CurrentCulture
    try { [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('tr-TR')
      $names = @(Get-GameFiles $script:d | ForEach-Object Name) } finally { [Threading.Thread]::CurrentThread.CurrentCulture = $old }
    $names.Count | Should -Be 2
  }
}
