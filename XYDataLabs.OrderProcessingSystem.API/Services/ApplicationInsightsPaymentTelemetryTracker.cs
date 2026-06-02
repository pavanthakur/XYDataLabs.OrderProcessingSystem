using System.Globalization;
using Microsoft.ApplicationInsights;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Observability;

namespace XYDataLabs.OrderProcessingSystem.API.Services;

public sealed class ApplicationInsightsPaymentTelemetryTracker : IPaymentTelemetryTracker
{
    private readonly TelemetryClient? _telemetryClient;

    public ApplicationInsightsPaymentTelemetryTracker(TelemetryClient? telemetryClient)
    {
        _telemetryClient = telemetryClient;
    }

    public void Track(PaymentTelemetryEvent telemetryEvent)
    {
        ArgumentNullException.ThrowIfNull(telemetryEvent);

        if (_telemetryClient is null || string.IsNullOrWhiteSpace(telemetryEvent.EventName))
        {
            return;
        }

        var properties = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["TelemetryCategory"] = "payment-validation",
            ["Application"] = NormalizeValue(telemetryEvent.Application, 16) ?? "API",
        };

        AddProperty(properties, "TenantCode", telemetryEvent.TenantCode, 64);
        AddProperty(properties, "CustomerOrderId", telemetryEvent.CustomerOrderId, 128);
        AddProperty(properties, "AttemptOrderId", telemetryEvent.AttemptOrderId, 128);
        AddProperty(properties, "PaymentId", telemetryEvent.PaymentId, 128);
        AddProperty(properties, "PaymentTraceId", telemetryEvent.PaymentTraceId, 128);
        AddProperty(properties, "ProviderType", telemetryEvent.ProviderType, 64);
        AddProperty(properties, "PaymentStatus", telemetryEvent.PaymentStatus, 64);
        AddProperty(properties, "StatusCategory", telemetryEvent.StatusCategory, 32);
        AddProperty(properties, "StatusSource", telemetryEvent.StatusSource, 32);
        AddProperty(properties, "ThreeDSecureStage", telemetryEvent.ThreeDSecureStage, 64);
        AddProperty(properties, "ClientFlowId", telemetryEvent.ClientFlowId, 64);
        AddProperty(properties, "PagePath", telemetryEvent.PagePath, 256);
        AddProperty(properties, "ErrorCode", telemetryEvent.ErrorCode, 64);
        AddProperty(properties, "ErrorMessage", telemetryEvent.ErrorMessage, 512);
        AddProperty(properties, "ClientTimestampUtc", telemetryEvent.ClientTimestampUtc, 64);
        AddProperty(properties, "Severity", telemetryEvent.Severity, 16);
        AddProperty(properties, "RunPrefix", PaymentTelemetryCorrelation.ResolveRunPrefix(telemetryEvent.CustomerOrderId), 64);
        AddNumber(properties, "HttpStatus", telemetryEvent.HttpStatus);
        AddBoolean(properties, "RemoteStatusConfirmed", telemetryEvent.RemoteStatusConfirmed);
        AddBoolean(properties, "CallbackRecorded", telemetryEvent.CallbackRecorded);
        AddBoolean(properties, "IsThreeDSecureEnabled", telemetryEvent.IsThreeDSecureEnabled);

        _telemetryClient.TrackEvent(telemetryEvent.EventName, properties);
    }

    private static void AddProperty(IDictionary<string, string> properties, string key, string? value, int maxLength)
    {
        var normalized = NormalizeValue(value, maxLength);
        if (!string.IsNullOrWhiteSpace(normalized))
        {
            properties[key] = normalized;
        }
    }

    private static void AddNumber(IDictionary<string, string> properties, string key, int? value)
    {
        if (value.HasValue)
        {
            properties[key] = value.Value.ToString(CultureInfo.InvariantCulture);
        }
    }

    private static void AddBoolean(IDictionary<string, string> properties, string key, bool? value)
    {
        if (value.HasValue)
        {
            properties[key] = value.Value ? "true" : "false";
        }
    }

    private static string? NormalizeValue(string? value, int maxLength)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var trimmed = value.Trim();
        return trimmed.Length <= maxLength ? trimmed : trimmed[..maxLength];
    }
}