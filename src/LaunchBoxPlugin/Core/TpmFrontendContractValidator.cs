using System.Text.Json;

namespace TeknoParrotManager.LaunchBoxPlugin;

public sealed class TpmContractValidationOutcome
{
    public bool IsValid { get; init; }
    public string ErrorCode { get; init; } = "NONE";
    public string Summary { get; init; } = string.Empty;
    public TpmFrontendResult? Result { get; init; }
}
public static class TpmFrontendContractValidator
{
    private static readonly HashSet<string> ResultProperties = new(StringComparer.Ordinal)
    {
        "contractVersion",
        "operationId",
        "correlationId",
        "status",
        "success",
        "cancelled",
        "errorCode",
        "summary",
        "warnings",
        "evidence",
        "technicalEvidence"
    };

    public static TpmContractValidationOutcome ValidateResult(string? json, Guid expectedCorrelationId)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            return Invalid("RESULT_MISSING", "The TPM result was empty.");
        }

        try
        {
            using var document = JsonDocument.Parse(json);
            if (document.RootElement.ValueKind != JsonValueKind.Object)
            {
                return Invalid("RESULT_MALFORMED", "The TPM result was not a JSON object.");
            }

            foreach (var property in document.RootElement.EnumerateObject())
            {
                if (!ResultProperties.Contains(property.Name))
                {
                    return Invalid("RESULT_SCHEMA_INVALID", "The TPM result contained an unknown field.");
                }
            }

            var result = JsonSerializer.Deserialize<TpmFrontendResult>(json, TpmFrontendContract.JsonOptions);
            if (result is null || result.Warnings is null || result.Evidence is null || result.TechnicalEvidence is null)
            {
                return Invalid("RESULT_SCHEMA_INVALID", "The TPM result was missing required fields.");
            }

            if (!string.Equals(result.ContractVersion, TpmFrontendContract.Version, StringComparison.Ordinal))
            {
                return Invalid("CONTRACT_UNSUPPORTED_VERSION", "The TPM result contract version is not supported.");
            }

            if (!string.Equals(result.OperationId, TpmFrontendContract.HealthCheckOperationId, StringComparison.Ordinal))
            {
                return Invalid("OPERATION_UNSUPPORTED", "The TPM result operation was not supported.");
            }

            if (!Guid.TryParse(result.CorrelationId, out var resultCorrelation) || resultCorrelation != expectedCorrelationId)
            {
                return Invalid("CORRELATION_MISMATCH", "The TPM result correlation ID did not match the request.");
            }

            if (result.Status is not ("success" or "failure" or "cancelled"))
            {
                return Invalid("RESULT_SCHEMA_INVALID", "The TPM result status was invalid.");
            }

            if (result.Success != string.Equals(result.Status, "success", StringComparison.Ordinal) ||
                result.Cancelled != string.Equals(result.Status, "cancelled", StringComparison.Ordinal))
            {
                return Invalid("RESULT_SCHEMA_INVALID", "The TPM result status flags were inconsistent.");
            }

            if (string.IsNullOrWhiteSpace(result.ErrorCode) || string.IsNullOrWhiteSpace(result.Summary))
            {
                return Invalid("RESULT_SCHEMA_INVALID", "The TPM result error code or summary was empty.");
            }

            return new TpmContractValidationOutcome
            {
                IsValid = true,
                Result = result,
                Summary = "The TPM result passed contract validation."
            };
        }
        catch (JsonException)
        {
            return Invalid("RESULT_MALFORMED", "The TPM result was malformed JSON.");
        }
    }

    private static TpmContractValidationOutcome Invalid(string errorCode, string summary)
    {
        return new TpmContractValidationOutcome
        {
            IsValid = false,
            ErrorCode = errorCode,
            Summary = summary
        };
    }
}
