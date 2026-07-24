param(
    [Parameter(Mandatory=$true)][string]$RepositoryPath,
    [Parameter(Mandatory=$true)][string]$ResultPath,
    [Parameter(Mandatory=$true)][string]$NUnitPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
try{
    Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop
    $configuration=New-PesterConfiguration
    $configuration.Run.Path=Join-Path $RepositoryPath 'Tests'
    $configuration.Run.PassThru=$true
    $configuration.Output.Verbosity='Detailed'
    $configuration.Output.CIFormat='None'
    $configuration.Output.RenderMode='Plaintext'
    $configuration.Output.StackTraceVerbosity='Filtered'
    $configuration.TestResult.Enabled=$true
    $configuration.TestResult.OutputPath=$NUnitPath
    $configuration.TestResult.OutputFormat='NUnitXml'
    $started=[DateTime]::UtcNow
    $result=Invoke-Pester -Configuration $configuration
    $ended=[DateTime]::UtcNow
    $tests=@($result.Tests)
    $vbt=@($tests|Where-Object{$_.ScriptBlock-and$_.ScriptBlock.File-and[IO.Path]::GetFileName($_.ScriptBlock.File)-like'VirtualBetaTester.*.Tests.ps1'})
    function Get-CategoryCount([object[]]$Items,[string[]]$Keywords){
        return @($Items|Where-Object{
            $name=[string]$_.Block.Name
            $matched=$false
            foreach($keyword in $Keywords){if($name-like("*"+$keyword+"*")){$matched=$true;break}}
            $matched
        }).Count
    }
    $failures=@($result.Failed|ForEach-Object{
        $name=if($_.PSObject.Properties.Name-contains'ExpandedPath'){[string]$_.ExpandedPath}else{[string]$_.Name}
        $message=''
        if($_.PSObject.Properties.Name-contains'ErrorRecord'-and$_.ErrorRecord){$message=[string](@($_.ErrorRecord)[0].Exception.Message)}
        if([string]::IsNullOrWhiteSpace($name)){$name='Unnamed Pester failure'}
        if([string]::IsNullOrWhiteSpace($message)){$message='Pester reported failure without an exception message'}
        [ordered]@{Name=$name;Message=$message}
    })
    $contract=[ordered]@{
        SchemaVersion=1
        Discovered=[long]$result.TotalCount
        Passed=[long]$result.PassedCount
        Failed=[long]$result.FailedCount
        Skipped=[long]$result.SkippedCount
        NotRun=[long]$result.NotRunCount
        Containers=[long]@($result.Containers).Count
        FailedContainers=[long]@($result.Containers|Where-Object Result -eq Failed).Count
        DurationMilliseconds=[long]($ended-$started).TotalMilliseconds
        Failures=$failures
        Categories=[ordered]@{
            VirtualBetaTesterTotal=[long]$vbt.Count
            VirtualBetaTesterPassed=[long]@($vbt|Where-Object Result -eq Passed).Count
            VirtualBetaTesterFailed=[long]@($vbt|Where-Object Result -eq Failed).Count
            HumanBehaviors=[long](Get-CategoryCount $vbt @('human workflow','main menu','decision paths'))
            IdempotencyChecks=[long](Get-CategoryCount $vbt @('idempotency','repeat-run','AutoSync repeat-run','preview'))
            RecoveryBehaviors=[long](Get-CategoryCount $vbt @('backup safety','read-only','recovery'))
            EnvironmentVariations=[long](Get-CategoryCount $vbt @('messy environment'))
            HighTvdBehaviors=[long]@($vbt|Where-Object{$_.Block-and$_.Block.Tag-and$_.Block.Tag-contains'TVD-High'}).Count
        }
        Engine=("Pester {0} / pwsh {1}"-f(Get-Module Pester).Version,$PSVersionTable.PSVersion)
    }
    if(Test-Path -LiteralPath $ResultPath){throw 'PESTER_RESULT_DESTINATION_EXISTS'}
    $temp=$ResultPath+'.'+[guid]::NewGuid().ToString('N')+'.partial'
    $stream=New-Object IO.FileStream($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try{$bytes=(New-Object Text.UTF8Encoding $false).GetBytes(($contract|ConvertTo-Json -Depth 8));$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
    Move-Item -LiteralPath $temp -Destination $ResultPath
    if($result.FailedCount-gt0-or@($result.Containers|Where-Object Result -eq Failed).Count-gt0){exit 1}
    exit 0
}catch{
    [Console]::Error.WriteLine(($_|Out-String))
    exit 70
}
