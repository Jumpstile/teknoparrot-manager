namespace TeknoParrotManager.LaunchBoxPlugin;

public sealed class TpmDiscoveryResult
{
    public bool IsSuccess { get; init; }
    public string ErrorCode { get; init; } = "NONE";
    public string Summary { get; init; } = string.Empty;
    public string? ScriptPath { get; init; }
    public string? TeknoParrotRoot { get; init; }
    public string? UserProfilesDirectory { get; init; }
    public IReadOnlyList<string> CandidateDescriptions { get; init; } = Array.Empty<string>();
}
public static class TpmDiscovery
{
    public static TpmDiscoveryResult Resolve(
        string? launchBoxRoot,
        string? pluginDirectory,
        string? configuredScriptPath,
        string? configuredTeknoParrotRoot)
    {
        var scriptCandidates = new List<string>();
        AddCandidate(scriptCandidates, configuredScriptPath);
        if (!string.IsNullOrWhiteSpace(launchBoxRoot))
        {
            AddCandidate(scriptCandidates, Path.Combine(launchBoxRoot, "TeknoParrot-Manager.ps1"));
            AddCandidate(scriptCandidates, Path.Combine(launchBoxRoot, "Scripts", "TeknoParrot-Manager.ps1"));
        }
        if (!string.IsNullOrWhiteSpace(pluginDirectory))
        {
            AddCandidate(scriptCandidates, Path.Combine(pluginDirectory, "TeknoParrot-Manager.ps1"));
        }

        var existingScripts = scriptCandidates
            .Where(File.Exists)
            .Select(Path.GetFullPath)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
        if (existingScripts.Count == 0)
        {
            return Failure("TPM_NOT_FOUND", "TeknoParrot Manager was not found from the LaunchBox/plugin context.", scriptCandidates);
        }
        if (existingScripts.Count > 1)
        {
            return Failure("TPM_DISCOVERY_AMBIGUOUS", "Multiple TeknoParrot Manager scripts were found; no path was guessed.", existingScripts);
        }

        var rootCandidates = new List<string>();
        AddCandidate(rootCandidates, configuredTeknoParrotRoot);
        if (!string.IsNullOrWhiteSpace(launchBoxRoot))
        {
            AddCandidate(rootCandidates, Path.Combine(launchBoxRoot, "Emulators", "TeknoParrot"));
        }
        if (!string.IsNullOrWhiteSpace(pluginDirectory))
        {
            var pluginParent = Directory.GetParent(pluginDirectory)?.FullName;
            if (!string.IsNullOrWhiteSpace(pluginParent))
            {
                AddCandidate(rootCandidates, Path.Combine(pluginParent, "Emulators", "TeknoParrot"));
            }
        }

        var existingRoots = rootCandidates
            .Where(IsTeknoParrotRoot)
            .Select(Path.GetFullPath)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
        if (existingRoots.Count == 0)
        {
            return Failure("TEKNOPARROT_NOT_FOUND", "TeknoParrot was not found from the LaunchBox/plugin context.", rootCandidates);
        }
        if (existingRoots.Count > 1)
        {
            return Failure("TEKNOPARROT_DISCOVERY_AMBIGUOUS", "Multiple TeknoParrot roots were found; no path was guessed.", existingRoots);
        }

        var root = existingRoots[0];
        return new TpmDiscoveryResult
        {
            IsSuccess = true,
            ScriptPath = existingScripts[0],
            TeknoParrotRoot = root,
            UserProfilesDirectory = Path.Combine(root, "UserProfiles"),
            Summary = "TeknoParrot Manager and TeknoParrot were discovered from host context.",
            CandidateDescriptions = existingScripts.Concat(existingRoots).ToArray()
        };
    }

    public static string? FindLaunchBoxRoot(IEnumerable<string> startingDirectories)
    {
        foreach (var start in startingDirectories.Where(value => !string.IsNullOrWhiteSpace(value)))
        {
            var current = new DirectoryInfo(Path.GetFullPath(start));
            for (var depth = 0; depth < 5 && current is not null; depth++)
            {
                if (File.Exists(Path.Combine(current.FullName, "LaunchBox.exe")) ||
                    File.Exists(Path.Combine(current.FullName, "BigBox.exe")))
                {
                    return current.FullName;
                }
                current = current.Parent;
            }
        }
        return null;
    }

    private static bool IsTeknoParrotRoot(string path)
    {
        return Directory.Exists(path) &&
               File.Exists(Path.Combine(path, "TeknoParrotUi.exe")) &&
               Directory.Exists(Path.Combine(path, "UserProfiles"));
    }

    private static void AddCandidate(List<string> candidates, string? path)
    {
        if (!string.IsNullOrWhiteSpace(path))
        {
            candidates.Add(path);
        }
    }

    private static TpmDiscoveryResult Failure(string errorCode, string summary, IEnumerable<string> candidates)
    {
        return new TpmDiscoveryResult
        {
            IsSuccess = false,
            ErrorCode = errorCode,
            Summary = summary,
            CandidateDescriptions = candidates.ToArray()
        };
    }
}
