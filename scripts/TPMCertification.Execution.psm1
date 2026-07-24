Set-StrictMode -Version Latest

function ConvertTo-TPMWin32ArgumentV1 {
    param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$Value)
    if($Value.Length-gt0-and$Value.IndexOfAny([char[]](' ',"`t",'"'))-lt0){return $Value}
    $builder=New-Object Text.StringBuilder
    [void]$builder.Append('"')
    $index=0
    while($index-lt$Value.Length){
        $backslashes=0
        while($index-lt$Value.Length-and$Value[$index]-eq'\'){$backslashes++;$index++}
        if($index-eq$Value.Length){[void]$builder.Append('\'*($backslashes*2));break}
        if($Value[$index]-eq'"'){
            [void]$builder.Append('\'*($backslashes*2+1))
            [void]$builder.Append('"')
        }else{
            [void]$builder.Append('\'*$backslashes)
            [void]$builder.Append($Value[$index])
        }
        $index++
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function ConvertTo-TPMSafeTechnicalTextV1 {
    param([AllowNull()][string]$Text)
    if($null-eq$Text){return ''}
    $withoutAnsi=[regex]::Replace($Text,"`e(?:\[[0-?]*[ -/]*[@-~]|\][^`a]*(?:`a|`e\\))",'')
    $builder=New-Object Text.StringBuilder
    foreach($character in $withoutAnsi.ToCharArray()){
        $code=[int][char]$character
        if($code-eq9-or$code-eq10-or$code-eq13-or$code-ge32){
            [void]$builder.Append($character)
        }else{
            [void]$builder.Append(('\x{0:X2}'-f$code))
        }
    }
    return $builder.ToString()
}

function Write-TPMSafeTechnicalFileV1 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return}
    $raw=[IO.File]::ReadAllText($Path)
    $safe=ConvertTo-TPMSafeTechnicalTextV1 -Text $raw
    [IO.File]::WriteAllText($Path,$safe,(New-Object Text.UTF8Encoding $false))
}

function Invoke-TPMIsolatedProcessV1 {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string[]]$ArgumentList,
        [Parameter(Mandatory=$true)][string]$WorkingDirectory,
        [Parameter(Mandatory=$true)][string]$LogDirectory,
        [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$Identity,
        [int]$TimeoutSeconds=3600,
        [string]$OperatorStatusPath,
        [switch]$RelayOperatorStatus,
        [hashtable]$Environment
    )
    foreach($directory in @($WorkingDirectory,$LogDirectory)){
        if(-not(Test-Path -LiteralPath $directory -PathType Container)){[void](New-Item -ItemType Directory -Path $directory -Force)}
    }
    $stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
    $prefix=Join-Path $LogDirectory ($stamp+'-'+$Identity)
    $stdinPath=$prefix+'-stdin.empty'
    $stdoutPath=$prefix+'-stdout.log'
    $stderrPath=$prefix+'-stderr.log'
    $metadataPath=$prefix+'-process.json'
    [IO.File]::WriteAllBytes($stdinPath,[byte[]]@())
    [IO.File]::WriteAllBytes($stdoutPath,[byte[]]@())
    [IO.File]::WriteAllBytes($stderrPath,[byte[]]@())
    $quoted=@($ArgumentList|ForEach-Object{ConvertTo-TPMWin32ArgumentV1 -Value $_})
    $started=[DateTime]::UtcNow
    $process=$null
    $timedOut=$false
    $terminationConfirmed=$false
    $exitCode=$null
    $processId=$null
    $statusOffset=0L
    $lastHeartbeat=[DateTime]::UtcNow
    try{
        $savedEnvironment=@{}
        if($Environment){
            foreach($key in $Environment.Keys){
                $savedEnvironment[$key]=[Environment]::GetEnvironmentVariable([string]$key,'Process')
                [Environment]::SetEnvironmentVariable([string]$key,[string]$Environment[$key],'Process')
            }
        }
        try{
            $process=Start-Process -FilePath $FilePath -ArgumentList $quoted -WorkingDirectory $WorkingDirectory -NoNewWindow -PassThru -RedirectStandardInput $stdinPath -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
            [void]$process.Handle
            $processId=$process.Id
        }finally{
            if($Environment){foreach($key in $Environment.Keys){[Environment]::SetEnvironmentVariable([string]$key,$savedEnvironment[$key],'Process')}}
        }
        while(-not$process.HasExited){
            if($RelayOperatorStatus-and-not[string]::IsNullOrWhiteSpace($OperatorStatusPath)-and(Test-Path -LiteralPath $OperatorStatusPath)){
                $stream=[IO.File]::Open($OperatorStatusPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
                try{
                    [void]$stream.Seek($statusOffset,[IO.SeekOrigin]::Begin)
                    $reader=New-Object IO.StreamReader($stream,(New-Object Text.UTF8Encoding $false),$true,1024,$true)
                    try{
                        while(-not$reader.EndOfStream){
                            $line=$reader.ReadLine()
                            if($line-match '^(\[[1-8]/8\] |Pester totals:|FINAL STATUS:|Reason:|Total elapsed:|Report:|Technical log:)'){Write-Host $line}
                        }
                        $statusOffset=$stream.Position
                    }finally{$reader.Dispose()}
                }finally{$stream.Dispose()}
            }
            if($RelayOperatorStatus-and([DateTime]::UtcNow-$lastHeartbeat).TotalSeconds-ge30){
                $lastHeartbeat=[DateTime]::UtcNow
                Write-Host ("Certification is still running - {0:hh\:mm\:ss} elapsed" -f ([DateTime]::UtcNow-$started))
            }
            if($TimeoutSeconds-gt0-and([DateTime]::UtcNow-$started).TotalSeconds-ge$TimeoutSeconds){$timedOut=$true;break}
            Start-Sleep -Milliseconds 250
        }
        if($timedOut-and-not$process.HasExited){
            try{Stop-Process -Id $process.Id -Force -ErrorAction Stop}catch{[Diagnostics.Debug]::WriteLine($_.Exception.Message)}
            try{[void]$process.WaitForExit(5000)}catch{[Diagnostics.Debug]::WriteLine($_.Exception.Message)}
        }
        $process.Refresh()
        $terminationConfirmed=$process.HasExited
        if($terminationConfirmed){$exitCode=$process.ExitCode}
    }finally{
        if($null-ne$process-and-not$process.HasExited){
            try{Stop-Process -Id $process.Id -Force -ErrorAction Stop}catch{[Diagnostics.Debug]::WriteLine($_.Exception.Message)}
            try{[void]$process.WaitForExit(5000)}catch{[Diagnostics.Debug]::WriteLine($_.Exception.Message)}
            $terminationConfirmed=$process.HasExited
        }
        if($null-ne$process){$process.Dispose()}
    }
    if(-not$terminationConfirmed){throw "PROCESS_TERMINATION_UNCONFIRMED: $Identity; logs preserved at $LogDirectory"}
    Write-TPMSafeTechnicalFileV1 -Path $stdoutPath
    Write-TPMSafeTechnicalFileV1 -Path $stderrPath
    $ended=[DateTime]::UtcNow
    $metadata=[ordered]@{
        SchemaVersion=1;Identity=$Identity;FilePath=$FilePath;Arguments=@($ArgumentList)
        Pid=$processId;StartedUtc=$started.ToString('o');EndedUtc=$ended.ToString('o')
        DurationMilliseconds=[long]($ended-$started).TotalMilliseconds
        ExitCode=$exitCode;TimedOut=$timedOut;TerminationConfirmed=$terminationConfirmed
        StandardInput=$stdinPath;StandardOutput=$stdoutPath;StandardError=$stderrPath
    }
    [IO.File]::WriteAllText($metadataPath,($metadata|ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding $false))
    return [pscustomobject]@{
        ExitCode=$exitCode;TimedOut=$timedOut;TerminationConfirmed=$terminationConfirmed
        StdOutPath=$stdoutPath;StdErrPath=$stderrPath;MetadataPath=$metadataPath
        StandardInputPath=$stdinPath;Pid=$metadata.Pid
    }
}

function Read-TPMPesterResultV1 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "PESTER_RESULT_MISSING: $Path"}
    try{$result=Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json}catch{throw "PESTER_RESULT_INVALID_JSON: $($_.Exception.Message)"}
    $expected=@('SchemaVersion','Discovered','Passed','Failed','Skipped','NotRun','Containers','FailedContainers','DurationMilliseconds','Failures','Categories','Engine')
    $actual=@($result.PSObject.Properties.Name)
    if(@($expected|Where-Object{$_-notin$actual}).Count-gt0-or@($actual|Where-Object{$_-notin$expected}).Count-gt0){throw 'PESTER_RESULT_SCHEMA_INVALID: exact field set required'}
    if($result.SchemaVersion-ne1){throw "PESTER_RESULT_VERSION_UNKNOWN: $($result.SchemaVersion)"}
    foreach($name in @('Discovered','Passed','Failed','Skipped','NotRun','Containers','FailedContainers','DurationMilliseconds')){
        if($result.$name-isnot[int]-and$result.$name-isnot[long]){throw "PESTER_RESULT_SCHEMA_INVALID: $name must be an integer"}
        if([long]$result.$name-lt0){throw "PESTER_RESULT_SCHEMA_INVALID: $name cannot be negative"}
    }
    if([long]$result.Discovered-ne([long]$result.Passed+[long]$result.Failed+[long]$result.Skipped+[long]$result.NotRun)){throw 'PESTER_RESULT_CONTRADICTORY: discovered total does not equal result totals'}
    if([long]$result.FailedContainers-gt[long]$result.Containers){throw 'PESTER_RESULT_CONTRADICTORY: failed containers exceed containers'}
    $categoryNames=@('VirtualBetaTesterTotal','VirtualBetaTesterPassed','VirtualBetaTesterFailed','HumanBehaviors','IdempotencyChecks','RecoveryBehaviors','EnvironmentVariations','HighTvdBehaviors')
    if($null-eq$result.Categories-or@($categoryNames|Where-Object{$_-notin$result.Categories.PSObject.Properties.Name}).Count-gt0){throw 'PESTER_RESULT_SCHEMA_INVALID: required category counts missing'}
    return $result
}

Export-ModuleMember -Function ConvertTo-TPMWin32ArgumentV1,ConvertTo-TPMSafeTechnicalTextV1,Write-TPMSafeTechnicalFileV1,Invoke-TPMIsolatedProcessV1,Read-TPMPesterResultV1
