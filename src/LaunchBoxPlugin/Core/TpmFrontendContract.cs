using System.Text.Json;
using System.Text.Json.Serialization;

namespace TeknoParrotManager.LaunchBoxPlugin;

public static class TpmFrontendContract
{
    public const string Version = "1.0";
    public const string HealthCheckOperationId = "library.health-check";

    public static JsonSerializerOptions JsonOptions { get; } = new()
    {
        PropertyNameCaseInsensitive = false,
        WriteIndented = false
    };
}
public sealed class TpmFrontendRequest
{
    [JsonPropertyName("contractVersion")]
    public string ContractVersion { get; set; } = string.Empty;

    [JsonPropertyName("operationId")]
    public string OperationId { get; set; } = string.Empty;

    [JsonPropertyName("correlationId")]
    public string CorrelationId { get; set; } = string.Empty;

    [JsonPropertyName("paths")]
    public TpmFrontendPaths Paths { get; set; } = new();
}

public sealed class TpmFrontendPaths
{
    [JsonPropertyName("userProfilesDirectory")]
    public string UserProfilesDirectory { get; set; } = string.Empty;

    [JsonPropertyName("teknoParrotRoot")]
    public string TeknoParrotRoot { get; set; } = string.Empty;
}

public sealed class TpmFrontendResult
{
    [JsonPropertyName("contractVersion")]
    public string ContractVersion { get; set; } = string.Empty;

    [JsonPropertyName("operationId")]
    public string OperationId { get; set; } = string.Empty;

    [JsonPropertyName("correlationId")]
    public string? CorrelationId { get; set; }

    [JsonPropertyName("status")]
    public string Status { get; set; } = string.Empty;

    [JsonPropertyName("success")]
    public bool Success { get; set; }

    [JsonPropertyName("cancelled")]
    public bool Cancelled { get; set; }

    [JsonPropertyName("errorCode")]
    public string ErrorCode { get; set; } = string.Empty;

    [JsonPropertyName("summary")]
    public string Summary { get; set; } = string.Empty;

    [JsonPropertyName("warnings")]
    public List<string> Warnings { get; set; } = new();

    [JsonPropertyName("evidence")]
    public List<TpmFrontendEvidence> Evidence { get; set; } = new();

    [JsonPropertyName("technicalEvidence")]
    public Dictionary<string, JsonElement> TechnicalEvidence { get; set; } = new();
}

public sealed class TpmFrontendEvidence
{
    [JsonPropertyName("name")]
    public string Name { get; set; } = string.Empty;

    [JsonPropertyName("value")]
    public JsonElement Value { get; set; }
}
