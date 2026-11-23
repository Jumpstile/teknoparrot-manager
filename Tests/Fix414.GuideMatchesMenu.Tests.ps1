# The guides must describe the Restore from Backup menu the way the program shows it.
# The size of the menu is read from the program itself, so a change to the menu fails this test until the guides are updated.
BeforeDiscovery {
    $root = Split-Path -Parent $PSScriptRoot
    $files = @(
        'README.md', 'QUICKSTART.md', 'TeknoParrot-Manager-README.txt', 'TeknoParrot-Manager-QuickStart.txt'
    ) | ForEach-Object { Join-Path $root $_ }
    $files += @(Get-ChildItem -LiteralPath (Join-Path $root 'docs') -Filter '*.md' -File -Recurse | ForEach-Object { $_.FullName })
    $script:f414Cases = @($files | ForEach-Object { @{ Path = $_; Name = $_.Substring($root.Length + 1) } })
}

BeforeAll {
    $script:root414 = Split-Path -Parent $PSScriptRoot
    $source = [System.IO.File]::ReadAllText((Join-Path $script:root414 'TeknoParrot-Manager.ps1'))
    $m = [regex]::Match($source, 'Enter 1-(\d+), or B to go back')
    $script:restoreMax = if ($m.Success) { [int]$m.Groups[1].Value } else { 0 }
    $words = @{ 1 = 'one'; 2 = 'two'; 3 = 'three'; 4 = 'four'; 5 = 'five'; 6 = 'six'; 7 = 'seven'; 8 = 'eight'; 9 = 'nine' }
    $script:restoreWord = $words[$script:restoreMax]
    $script:numberWords = '(one|two|three|four|five|six|seven|eight|nine)'

    # Each place a guide talks about the Restore from Backup screen: the line that names it and the two lines after it.
    function Get-RestoreMentions {
        param([string]$Path)
        $lines = [System.IO.File]::ReadAllLines($Path)
        $found = New-Object System.Collections.Generic.List[object]
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '(?i)restore\s+from\s+backup|restore\s+backup\)') {
                $last = [Math]::Min($i + 2, $lines.Count - 1)
                $found.Add([pscustomobject]@{ Line = $i + 1; Text = (($lines[$i..$last]) -join ' ') })
            }
        }
        return $found
    }
}

Describe 'Fix414 guides match the Restore from Backup menu' {
    It 'the program has a Restore menu prompt this test can read' {
        $script:restoreMax | Should -BeGreaterThan 0
        $script:restoreWord | Should -Not -BeNullOrEmpty
    }

    It '<Name> gives the same number of choices as the program' -ForEach $script:f414Cases {
        $bad = New-Object System.Collections.Generic.List[string]
        foreach ($hit in (Get-RestoreMentions -Path $Path)) {
            foreach ($c in [regex]::Matches($hit.Text, "(?i)\b$($script:numberWords)\s+(numbered\s+)?(choices|options)\b")) {
                if ($c.Groups[1].Value.ToLowerInvariant() -ne $script:restoreWord) { $bad.Add("${Name}:$($hit.Line): says '$($c.Value)', the menu has $script:restoreWord") }
            }
            foreach ($c in [regex]::Matches($hit.Text, 'Enter 1-(\d+), or B')) {
                if ([int]$c.Groups[1].Value -ne $script:restoreMax) { $bad.Add("${Name}:$($hit.Line): says '$($c.Value)', the menu says Enter 1-$script:restoreMax") }
            }
            foreach ($c in [regex]::Matches($hit.Text, '\b1 to (\d+)\b')) {
                if ([int]$c.Groups[1].Value -ne $script:restoreMax) { $bad.Add("${Name}:$($hit.Line): says '$($c.Value)', the menu goes to $script:restoreMax") }
            }
            if ($hit.Text -match '(?i)\b1, 2, 3 or 4\b') { $bad.Add("${Name}:$($hit.Line): lists only 1, 2, 3 or 4") }
        }
        $bad.Count | Should -Be 0 -Because ($bad -join "`n")
    }

    It '<Name> never says pressing only Enter is refused on the Restore screen' -ForEach $script:f414Cases {
        $bad = New-Object System.Collections.Generic.List[string]
        foreach ($hit in (Get-RestoreMentions -Path $Path)) {
            if ($hit.Text -match '(?i)(only|just|alone)\s+Enter[^.]*\b(not accepted|is refused|does nothing|is not allowed)') { $bad.Add("${Name}:$($hit.Line): $($hit.Text)") }
        }
        $bad.Count | Should -Be 0 -Because ($bad -join "`n")
    }
}
