using System.Diagnostics;
using System.Diagnostics.Metrics;

namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Observability;

public static class BusinessMetrics
{
    public const string MeterName = "OrderProcessing.Business";

    private static readonly Meter Meter = new(MeterName);
    private static readonly Counter<long> TenantContextFailures = Meter.CreateCounter<long>(
        name: "orderprocessing.tenant_context.failures",
        unit: "{failure}",
        description: "Requests rejected because tenant context was missing or invalid.");
    private static readonly Counter<long> ProblemResponses = Meter.CreateCounter<long>(
        name: "orderprocessing.api.problem_responses",
        unit: "{response}",
        description: "ProblemDetails responses emitted by the API.");
    private static readonly Counter<long> PaymentAttempts = Meter.CreateCounter<long>(
        name: "orderprocessing.payments.completed",
        unit: "{attempt}",
        description: "Completed payment processing attempts grouped by outcome.");
    private static readonly Histogram<double> PaymentDuration = Meter.CreateHistogram<double>(
        name: "orderprocessing.payments.duration",
        unit: "ms",
        description: "End-to-end duration for payment processing attempts.");

    public static void RecordTenantContextFailure(string requestName, bool hasTenantContext)
    {
        TenantContextFailures.Add(1, new TagList
        {
            { "request_name", requestName },
            { "tenant_context_present", hasTenantContext }
        });
    }

    public static void RecordProblemResponse(int statusCode, string? problemType)
    {
        ProblemResponses.Add(1, new TagList
        {
            { "status_code", statusCode },
            { "problem_type", Normalize(problemType) }
        });
    }

    public static void RecordPaymentAttempt(
        string outcome,
        string providerName,
        bool isThreeDSecureEnabled,
        string? paymentStatus,
        TimeSpan duration)
    {
        var tags = new TagList
        {
            { "outcome", Normalize(outcome) },
            { "provider", Normalize(providerName) },
            { "three_d_secure_enabled", isThreeDSecureEnabled },
            { "payment_status", Normalize(paymentStatus) }
        };

        PaymentAttempts.Add(1, tags);
        PaymentDuration.Record(duration.TotalMilliseconds, tags);
    }

    private static string Normalize(string? value) =>
        string.IsNullOrWhiteSpace(value) ? "unknown" : value.Trim();
}