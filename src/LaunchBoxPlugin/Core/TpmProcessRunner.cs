using System.Diagnostics;
using System.IO;

namespace TeknoParrotManager.LaunchBoxPlugin;

public static class TpmProcessRunner
{
    public static string FindPowerShell()
    {
        var windowsDirectory = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        var windowsPowerShell = Path.Combine(windowsDirectory, "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
        return File.Exists(windowsPowerShell) ? windowsPowerShell : "pwsh.exe";
    }

    public static async Task<TpmFrontendResult> RunHealthCheckAsync(
        string powershellPath,
        string scriptPath,
        string teknoParrotRoot,
        string userProfilesDirectory,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        var correlationId = Guid.NewGuid();
        var tempRoot = Path.Combine(
            Path.GetTempPath(),
            "TeknoParrotManager",
            "LaunchBox",
            correlationId.ToString("N"));

        try
        {
            if (!File.Exists(powershellPath))
            {
                return Failure(correlationId, "TPM_PROCESS_FAILED", "PowerShell was not found for the bounded TPM invocation.");
            }
            if (!File.Exists(scriptPath))
            {
                return Failure(correlationId, "TPM_NOT_FOUND", "TeknoParrot Manager was not found at the discovered location.");
            }

            Directory.CreateDirectory(tempRoot);
            var requestPath = Path.Combine(tempRoot, "request.json");
            var resultPath = Path.Combine(tempRoot, "result.json");
            var request = new TpmFrontendRequest
            {
                ContractVersion = TpmFrontendContract.Version,
                OperationId = TpmFrontendContract.HealthCheckOperationId,
                CorrelationId = correlationId.ToString(),
                Paths = new TpmFrontendPaths
                {
                    UserProfilesDirectory = userProfilesDirectory,
                    TeknoParrotRoot = teknoParrotRoot
                }
            };
            await File.WriteAllTextAsync(requestPath, System.Text.Json.JsonSerializer.Serialize(request, TpmFrontendContract.JsonOptions), cancellationToken);

            var startInfo = new ProcessStartInfo
            {
                FileName = powershellPath,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            };
            startInfo.ArgumentList.Add("-NoProfile");
            startInfo.ArgumentList.Add("-NonInteractive");
            startInfo.ArgumentList.Add("-ExecutionPolicy");
            startInfo.ArgumentList.Add("Bypass");
            startInfo.ArgumentList.Add("-File");
            startInfo.ArgumentList.Add(scriptPath);
            startInfo.ArgumentList.Add("-FrontendContractRequestPath");
            startInfo.ArgumentList.Add(requestPath);
            startInfo.ArgumentList.Add("-FrontendContractResultPath");
            startInfo.ArgumentList.Add(resultPath);
            startInfo.ArgumentList.Add("-FrontendContractCorrelationId");
            startInfo.ArgumentList.Add(correlationId.ToString());

            using var process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
            if (!process.Start())
            {
                return Failure(correlationId, "TPM_PROCESS_FAILED", "The bounded TPM process could not be started.");
            }

            var standardOutputTask = process.StandardOutput.ReadToEndAsync();
            var standardErrorTask = process.StandardError.ReadToEndAsync();
            using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeoutSource.CancelAfter(timeout);
            try
            {
                await process.WaitForExitAsync(timeoutSource.Token);
            }
            catch (OperationCanceledException)
            {
                try
                {
                    if (!process.HasExited)
                    {
                        process.Kill(entireProcessTree: true);
                    }
                }
                catch (InvalidOperationException)
                {
                }
                await ObserveOutputAsync(standardOutputTask, standardErrorTask);
                return Failure(
                    correlationId,
                    cancellationToken.IsCancellationRequested ? "TPM_CANCELLED" : "TPM_TIMEOUT",
                    cancellationToken.IsCancellationRequested
                        ? "The TPM health check was cancelled."
                        : "The TPM health check exceeded its bounded timeout.",
                    cancelled: cancellationToken.IsCancellationRequested);
            }

            await ObserveOutputAsync(standardOutputTask, standardErrorTask);
            if (!File.Exists(resultPath))
            {
                var missing = Failure(correlationId, "RESULT_MISSING", "The TPM process exited without a result file.");
                TpmFrontendResultFactory.AddTechnicalEvidence(missing, "exitCode", process.ExitCode);
                return missing;
            }

            var resultJson = await File.ReadAllTextAsync(resultPath, cancellationToken);
            var validation = TpmFrontendContractValidator.ValidateResult(resultJson, correlationId);
            if (!validation.IsValid)
            {
                var invalid = Failure(correlationId, validation.ErrorCode, validation.Summary);
                TpmFrontendResultFactory.AddTechnicalEvidence(invalid, "exitCode", process.ExitCode);
                return invalid;
            }

            var result = validation.Result!;
            TpmFrontendResultFactory.AddTechnicalEvidence(result, "exitCode", process.ExitCode);
            if (process.ExitCode != 0 && result.Success)
            {
                return Failure(correlationId, "TPM_PROCESS_FAILED", "The TPM process reported success with a nonzero exit code.");
            }
            return result;
        }
        catch (OperationCanceledException)
        {
            return Failure(correlationId, "TPM_CANCELLED", "The TPM health check was cancelled.", cancelled: true);
        }
        catch (UnauthorizedAccessException)
        {
            return Failure(correlationId, "ACCESS_DENIED", "The TPM contract could not access its isolated invocation files.");
        }
        catch (IOException)
        {
            return Failure(correlationId, "RESULT_MISSING", "The TPM contract result could not be read.");
        }
        catch (System.ComponentModel.Win32Exception)
        {
            return Failure(correlationId, "TPM_PROCESS_FAILED", "The bounded TPM process could not be started.");
        }
        finally
        {
            try
            {
                if (Directory.Exists(tempRoot))
                {
                    Directory.Delete(tempRoot, recursive: true);
                }
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
            }
        }
    }

    private static async Task ObserveOutputAsync(Task<string> standardOutputTask, Task<string> standardErrorTask)
    {
        await Task.WhenAll(standardOutputTask, standardErrorTask);
    }

    private static TpmFrontendResult Failure(Guid correlationId, string errorCode, string summary, bool cancelled = false)
    {
        var result = TpmFrontendResultFactory.Failure(correlationId, errorCode, summary, cancelled);
        TpmFrontendResultFactory.AddTechnicalEvidence(result, "processMode", "non-interactive-contract");
        return result;
    }
}
