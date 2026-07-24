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
    # Windows can briefly hold the redirected-output file handle open after
    # Start-Process's own .HasExited/.ExitCode already report the child as
    # exited (confirmed by direct reproduction: reading a just-exited
    # child's redirected stdout log immediately afterward intermittently
    # threw "being used by another process"). This is a transient handle-
    # release delay, not a real error condition -- retry briefly with a
    # bounded backoff. If the file is still locked once the budget is
    # exhausted, leave it unsanitized rather than losing the only captured
    # diagnostic evidence to a thrown exception; sanitization is a
    # best-effort readability step, not a safety invariant the caller
    # should be aborted over.
    param([Parameter(Mandatory=$true)][string]$Path)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return}
    $raw=$null
    for($attempt=0;$attempt-lt20;$attempt++){
        try{$raw=[IO.File]::ReadAllText($Path);break}
        catch [IO.IOException]{Start-Sleep -Milliseconds 100}
    }
    if($null-eq$raw){return}
    $safe=ConvertTo-TPMSafeTechnicalTextV1 -Text $raw
    for($attempt=0;$attempt-lt20;$attempt++){
        try{[IO.File]::WriteAllText($Path,$safe,(New-Object Text.UTF8Encoding $false));return}
        catch [IO.IOException]{Start-Sleep -Milliseconds 100}
    }
}

function Assert-TPMOwnedDirectoryV1 {
    # -CreateIfMissing creates the directory (and any missing parents) when
    # it does not yet exist -- callers such as Invoke-TPMIsolatedProcessV1
    # own their working/log directories and are expected to bring them into
    # existence on first use, not to fail because nothing has written to
    # that path yet. The reparse-point rejection below still applies to
    # whatever directory ends up at this exact path, whether it already
    # existed or was just created here.
    param([Parameter(Mandatory=$true)][string]$Path,[switch]$CreateIfMissing)
    $full=[IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    if(-not(Test-Path -LiteralPath $full -PathType Container)){
        if(-not$CreateIfMissing){throw "PROCESS_DIRECTORY_INVALID: directory does not exist: $full"}
        [void](New-Item -ItemType Directory -Path $full -Force -ErrorAction Stop)
    }
    $item=Get-Item -LiteralPath $full -Force
    if(($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw "PROCESS_DIRECTORY_INVALID: reparse point rejected: $full"}
    return $full
}

function New-TPMCreateNewFileV1 {
    param([Parameter(Mandatory=$true)][string]$Parent,[Parameter(Mandatory=$true)][string]$Name)
    $root=Assert-TPMOwnedDirectoryV1 -Path $Parent
    $path=[IO.Path]::GetFullPath((Join-Path $root $Name))
    $prefix=$root+[IO.Path]::DirectorySeparatorChar
    if(-not$path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'PROCESS_PATH_OUTSIDE_OWNED_ROOT'}
    $stream=New-Object IO.FileStream($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    $stream.Dispose()
    return $path
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
    $workingRoot=Assert-TPMOwnedDirectoryV1 -Path $WorkingDirectory -CreateIfMissing
    $logRoot=Assert-TPMOwnedDirectoryV1 -Path $LogDirectory -CreateIfMissing
    $nonce=[guid]::NewGuid().ToString('N')
    $prefix=$nonce+'-'+$Identity
    $stdinPath=New-TPMCreateNewFileV1 -Parent $logRoot -Name ($prefix+'-stdin.empty')
    $stdoutPath=New-TPMCreateNewFileV1 -Parent $logRoot -Name ($prefix+'-stdout.log')
    $stderrPath=New-TPMCreateNewFileV1 -Parent $logRoot -Name ($prefix+'-stderr.log')
    $metadataPath=Join-Path $logRoot ($prefix+'-process.json')
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
            $process=Start-Process -FilePath $FilePath -ArgumentList $quoted -WorkingDirectory $workingRoot -NoNewWindow -PassThru -RedirectStandardInput $stdinPath -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
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
        SchemaVersion=1;Identity=$Identity;FilePath=[IO.Path]::GetFileName($FilePath);ArgumentCount=@($ArgumentList).Count
        Pid=$processId;StartedUtc=$started.ToString('o');EndedUtc=$ended.ToString('o')
        DurationMilliseconds=[long]($ended-$started).TotalMilliseconds
        ExitCode=$exitCode;TimedOut=$timedOut;TerminationConfirmed=$terminationConfirmed
        StandardInput=$stdinPath;StandardOutput=$stdoutPath;StandardError=$stderrPath
    }
    $metadataStream=New-Object IO.FileStream($metadataPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try{
        $bytes=(New-Object Text.UTF8Encoding $false).GetBytes(($metadata|ConvertTo-Json -Depth 5))
        $metadataStream.Write($bytes,0,$bytes.Length)
    }finally{$metadataStream.Dispose()}
    return [pscustomobject]@{
        ExitCode=$exitCode;TimedOut=$timedOut;TerminationConfirmed=$terminationConfirmed
        StdOutPath=$stdoutPath;StdErrPath=$stderrPath;MetadataPath=$metadataPath
        StandardInputPath=$stdinPath;Pid=$metadata.Pid
    }
}

function Stop-TPMPesterSchemaV1 {
    param([Parameter(Mandatory=$true)][string]$Reason)
    throw "PESTER_RESULT_SCHEMA_INVALID: $Reason"
}

function Assert-TPMExactObjectFieldsV1 {
    param($Value,[string[]]$Expected,[string]$Label)
    if($null-eq$Value-or$Value-isnot[pscustomobject]){Stop-TPMPesterSchemaV1 "$Label must be an object"}
    $actual=@($Value.PSObject.Properties.Name)
    if(@($Expected|Where-Object{$_-cnotin$actual}).Count-ne0-or@($actual|Where-Object{$_-cnotin$Expected}).Count-ne0){Stop-TPMPesterSchemaV1 "$Label must contain the exact documented field set"}
    return $Value
}

function Assert-TPMResultIntegerV1 {
    param($Value,[string]$Label)
    $integralTypes=@([byte],[sbyte],[int16],[uint16],[int32],[uint32],[int64])
    if($null-eq$Value-or$Value-is[bool]-or$Value.GetType()-notin$integralTypes){Stop-TPMPesterSchemaV1 "$Label must be an integral numeric value"}
    try{$number=[long]$Value}catch{Stop-TPMPesterSchemaV1 "$Label is outside the supported integer range"}
    if($number-lt0-or$number-gt2147483647){Stop-TPMPesterSchemaV1 "$Label is outside the safe range 0..2147483647"}
    return $number
}

function Assert-TPMNonblankResultStringV1 {
    param($Value,[string]$Label)
    if($Value-isnot[string]-or[string]::IsNullOrWhiteSpace($Value)){Stop-TPMPesterSchemaV1 "$Label must be a nonblank string"}
    return [string]$Value
}

function Read-TPMPesterResultV1 {
    param([Parameter(Mandatory=$true)][string]$Path)
    try{
        if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){Stop-TPMPesterSchemaV1 'result file is missing'}
        $raw=Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        if([string]::IsNullOrWhiteSpace($raw)){Stop-TPMPesterSchemaV1 'result file is empty'}
        try{$result=$raw|ConvertFrom-Json -ErrorAction Stop}catch{Stop-TPMPesterSchemaV1 'result JSON is malformed or truncated'}
        $topFields=@('SchemaVersion','Discovered','Passed','Failed','Skipped','NotRun','Containers','FailedContainers','DurationMilliseconds','Failures','Categories','Engine')
        $result=Assert-TPMExactObjectFieldsV1 $result $topFields 'result'
        $version=Assert-TPMResultIntegerV1 $result.SchemaVersion 'SchemaVersion'
        if($version-ne1){Stop-TPMPesterSchemaV1 'unsupported SchemaVersion'}
        [void](Assert-TPMNonblankResultStringV1 $result.Engine 'Engine')
        foreach($name in @('Discovered','Passed','Failed','Skipped','NotRun','Containers','FailedContainers','DurationMilliseconds')){
            $result.$name=Assert-TPMResultIntegerV1 $result.$name $name
        }
        if($result.Discovered-ne($result.Passed+$result.Failed+$result.Skipped+$result.NotRun)){Stop-TPMPesterSchemaV1 'discovered total contradicts result totals'}
        if($result.FailedContainers-gt$result.Containers){Stop-TPMPesterSchemaV1 'failed container total exceeds container total'}
        $categoryFields=@('VirtualBetaTesterTotal','VirtualBetaTesterPassed','VirtualBetaTesterFailed','HumanBehaviors','IdempotencyChecks','RecoveryBehaviors','EnvironmentVariations','HighTvdBehaviors')
        $categories=Assert-TPMExactObjectFieldsV1 $result.Categories $categoryFields 'Categories'
        foreach($name in $categoryFields){$categories.$name=Assert-TPMResultIntegerV1 $categories.$name "Categories.$name"}
        if($categories.VirtualBetaTesterTotal-ne($categories.VirtualBetaTesterPassed+$categories.VirtualBetaTesterFailed)){Stop-TPMPesterSchemaV1 'Virtual Beta Tester totals contradict pass/fail totals'}
        if($categories.VirtualBetaTesterTotal-gt$result.Discovered-or$categories.VirtualBetaTesterPassed-gt$result.Passed-or$categories.VirtualBetaTesterFailed-gt$result.Failed){Stop-TPMPesterSchemaV1 'Virtual Beta Tester totals exceed global totals'}
        foreach($name in @('HumanBehaviors','IdempotencyChecks','RecoveryBehaviors','EnvironmentVariations','HighTvdBehaviors')){
            if($categories.$name-gt$categories.VirtualBetaTesterTotal){Stop-TPMPesterSchemaV1 "Categories.$name exceeds VirtualBetaTesterTotal"}
        }
        if($null-eq$result.Failures-or$result.Failures-isnot[array]){Stop-TPMPesterSchemaV1 'Failures must be a JSON array'}
        foreach($failure in @($result.Failures)){
            $entry=Assert-TPMExactObjectFieldsV1 $failure @('Name','Message') 'Failures entry'
            [void](Assert-TPMNonblankResultStringV1 $entry.Name 'Failures.Name')
            [void](Assert-TPMNonblankResultStringV1 $entry.Message 'Failures.Message')
        }
        if(@($result.Failures).Count-ne$result.Failed){Stop-TPMPesterSchemaV1 'failure-entry count does not equal Failed'}
        return $result
    }catch{
        if($_.Exception.Message-like'PESTER_RESULT_SCHEMA_INVALID:*'){throw}
        Stop-TPMPesterSchemaV1 'unexpected validation failure'
    }
}
Export-ModuleMember -Function ConvertTo-TPMWin32ArgumentV1,ConvertTo-TPMSafeTechnicalTextV1,Write-TPMSafeTechnicalFileV1,Invoke-TPMIsolatedProcessV1,Read-TPMPesterResultV1
