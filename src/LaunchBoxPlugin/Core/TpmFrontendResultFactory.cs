using System.Text.Json;

namespace TeknoParrotManager.LaunchBoxPlugin;

public static class TpmFrontendResultFactory
{
    public static TpmFrontendResult Success(Guid correlationId, string summary, IEnumerable<string>? warnings = null)
    {
        return new TpmFrontendResult
        {
            ContractVersion = TpmFrontendContract.Version,
            OperationId = TpmFrontendContract.HealthCheckOperationId,
            CorrelationId = correlationId.ToString(),
            Status = "success",
            Success = true,
            Cancelled = false,
            ErrorCode = "NONE",
            Summary = summary,
            Warnings = warnings?.ToList() ?? new List<string>(),
            Evidence = new List<TpmFrontendEvidence>(),
            TechnicalEvidence = new Dictionary<string, JsonElement>()
        };
    }

    public static TpmFrontendResult Failure(Guid? correlationId, string errorCode, string summary, bool cancelled = false)
    {
        return new TpmFrontendResult
        {
            ContractVersion = TpmFrontendContract.Version,
            OperationId = TpmFrontendContract.HealthCheckOperationId,
            CorrelationId = correlationId?.ToString(),
            Status = cancelled ? "cancelled" : "failure",
            Success = false,
            Cancelled = cancelled,
            ErrorCode = errorCode,
            Summary = summary,
            Warnings = new List<string>(),
            Evidence = new List<TpmFrontendEvidence>(),
            TechnicalEvidence = new Dictionary<string, JsonElement>()
        };
    }

    public static void AddTechnicalEvidence(TpmFrontendResult result, string name, object? value)
    {
        result.TechnicalEvidence[name] = JsonSerializer.SerializeToElement(value, TpmFrontendContract.JsonOptions);
    }
}
