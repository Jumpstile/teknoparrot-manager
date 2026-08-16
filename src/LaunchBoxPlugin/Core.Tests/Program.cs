using System.Text.Json;
using TeknoParrotManager.LaunchBoxPlugin;

var failures = new List<string>();

void Check(string name, bool condition)
{
    if (!condition)
    {
        failures.Add(name);
    }
}

var correlationId = Guid.NewGuid();
var validResult = TpmFrontendResultFactory.Success(correlationId, "Health check completed.");
validResult.Evidence.Add(new TpmFrontendEvidence
{
    Name = "registeredProfiles",
    Value = JsonSerializer.SerializeToElement(3)
});
var validJson = JsonSerializer.Serialize(validResult, TpmFrontendContract.JsonOptions);
var validOutcome = TpmFrontendContractValidator.ValidateResult(validJson, correlationId);
Check("valid result", validOutcome.IsValid);

var malformedOutcome = TpmFrontendContractValidator.ValidateResult("{", correlationId);
Check("malformed result", malformedOutcome.ErrorCode == "RESULT_MALFORMED");

var unsupportedJson = validJson.Replace("\"contractVersion\":\"1.0\"", "\"contractVersion\":\"9.0\"", StringComparison.Ordinal);
var unsupportedOutcome = TpmFrontendContractValidator.ValidateResult(unsupportedJson, correlationId);
Check("unsupported contract", unsupportedOutcome.ErrorCode == "CONTRACT_UNSUPPORTED_VERSION");

var mismatchOutcome = TpmFrontendContractValidator.ValidateResult(validJson, Guid.NewGuid());
Check("correlation mismatch", mismatchOutcome.ErrorCode == "CORRELATION_MISMATCH");

var unknownFieldJson = validJson[..^1] + ",\"unexpected\":true}";
var unknownFieldOutcome = TpmFrontendContractValidator.ValidateResult(unknownFieldJson, correlationId);
Check("unknown field", unknownFieldOutcome.ErrorCode == "RESULT_SCHEMA_INVALID");

var inconsistentJson = validJson.Replace("\"status\":\"success\"", "\"status\":\"failure\"", StringComparison.Ordinal);
var inconsistentOutcome = TpmFrontendContractValidator.ValidateResult(inconsistentJson, correlationId);
Check("inconsistent flags", inconsistentOutcome.ErrorCode == "RESULT_SCHEMA_INVALID");

var tempRoot = Path.Combine(Path.GetTempPath(), "tpm-phase0-core-test-" + Guid.NewGuid().ToString("N"));
try
{
    var launchBoxRoot = Path.Combine(tempRoot, "LaunchBox Root");
    var pluginDirectory = Path.Combine(launchBoxRoot, "Plugins", "TeknoParrot Manager");
    var scriptPath = Path.Combine(pluginDirectory, "TeknoParrot-Manager.ps1");
    var teknoParrotRoot = Path.Combine(launchBoxRoot, "Emulators", "TeknoParrot");
    Directory.CreateDirectory(pluginDirectory);
    Directory.CreateDirectory(Path.Combine(teknoParrotRoot, "UserProfiles"));
    File.WriteAllText(Path.Combine(launchBoxRoot, "LaunchBox.exe"), string.Empty);
    File.WriteAllText(scriptPath, string.Empty);
    File.WriteAllText(Path.Combine(teknoParrotRoot, "TeknoParrotUi.exe"), string.Empty);

    var discovery = TpmDiscovery.Resolve(launchBoxRoot, pluginDirectory, scriptPath, teknoParrotRoot);
    Check("context discovery", discovery.IsSuccess);
    Check("space-safe discovery", discovery.UserProfilesDirectory?.Contains("LaunchBox Root", StringComparison.Ordinal) == true);

    var secondRoot = Path.Combine(tempRoot, "Second Root");
    Directory.CreateDirectory(Path.Combine(secondRoot, "UserProfiles"));
    File.WriteAllText(Path.Combine(secondRoot, "TeknoParrotUi.exe"), string.Empty);
    var ambiguous = TpmDiscovery.Resolve(launchBoxRoot, pluginDirectory, scriptPath, secondRoot);
    Check("ambiguous discovery", ambiguous.ErrorCode == "TEKNOPARROT_DISCOVERY_AMBIGUOUS");

    var powershellPath = TpmProcessRunner.FindPowerShell();
    var fakeBase = "param([string]$FrontendContractRequestPath, [string]$FrontendContractResultPath, [string]$FrontendContractCorrelationId)";
    var missingResultScript = Path.Combine(pluginDirectory, "missing-result.ps1");
    File.WriteAllText(missingResultScript, fakeBase + Environment.NewLine + "exit 0");
    var missingResult = TpmProcessRunner.RunHealthCheckAsync(
        powershellPath, missingResultScript, teknoParrotRoot, Path.Combine(teknoParrotRoot, "UserProfiles"),
        TimeSpan.FromSeconds(5), CancellationToken.None).GetAwaiter().GetResult();
    Check("missing result", missingResult.ErrorCode == "RESULT_MISSING");

    var malformedResultScript = Path.Combine(pluginDirectory, "malformed-result.ps1");
    File.WriteAllText(malformedResultScript, fakeBase + Environment.NewLine + "Set-Content -LiteralPath $FrontendContractResultPath -Value '{' -Encoding UTF8" + Environment.NewLine + "exit 0");
    var malformedResult = TpmProcessRunner.RunHealthCheckAsync(
        powershellPath, malformedResultScript, teknoParrotRoot, Path.Combine(teknoParrotRoot, "UserProfiles"),
        TimeSpan.FromSeconds(5), CancellationToken.None).GetAwaiter().GetResult();
    Check("malformed result", malformedResult.ErrorCode == "RESULT_MALFORMED");

    var slowScript = Path.Combine(pluginDirectory, "slow-result.ps1");
    File.WriteAllText(slowScript, fakeBase + Environment.NewLine + "Start-Sleep -Seconds 30");
    var timedOut = TpmProcessRunner.RunHealthCheckAsync(
        powershellPath, slowScript, teknoParrotRoot, Path.Combine(teknoParrotRoot, "UserProfiles"),
        TimeSpan.FromMilliseconds(250), CancellationToken.None).GetAwaiter().GetResult();
    Check("timeout", timedOut.ErrorCode == "TPM_TIMEOUT");

    using var cancellation = new CancellationTokenSource();
    cancellation.Cancel();
    var cancelled = TpmProcessRunner.RunHealthCheckAsync(
        powershellPath, missingResultScript, teknoParrotRoot, Path.Combine(teknoParrotRoot, "UserProfiles"),
        TimeSpan.FromSeconds(5), cancellation.Token).GetAwaiter().GetResult();
    Check("cancellation", cancelled.ErrorCode == "TPM_CANCELLED" && cancelled.Cancelled);

    var processFailure = TpmProcessRunner.RunHealthCheckAsync(
        Path.Combine(pluginDirectory, "not-a-powershell.exe"), missingResultScript, teknoParrotRoot,
        Path.Combine(teknoParrotRoot, "UserProfiles"), TimeSpan.FromSeconds(5), CancellationToken.None)
        .GetAwaiter().GetResult();
    Check("process failure", processFailure.ErrorCode == "TPM_PROCESS_FAILED");
}
finally
{
    if (Directory.Exists(tempRoot))
    {
        Directory.Delete(tempRoot, recursive: true);
    }
}

if (failures.Count > 0)
{
    Console.Error.WriteLine("Core self-test failures: " + string.Join(", ", failures));
    return 1;
}

Console.WriteLine("LaunchBox Phase 0 core self-test passed.");
return 0;
