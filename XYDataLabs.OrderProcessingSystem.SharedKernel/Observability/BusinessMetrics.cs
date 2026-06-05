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

    // Phase 8.7 — Webhook + Inbox metrics (DW-003)
    private static readonly Counter<long> WebhookHmacFailures = Meter.CreateCounter<long>(
        name: "orderprocessing.webhook.hmac_failures",
        unit: "{failure}",
        description: "Webhook requests rejected due to HMAC signature validation failure.");
    private static readonly Counter<long> InboxDedupHits = Meter.CreateCounter<long>(
        name: "orderprocessing.inbox.dedup_hits",
        unit: "{hit}",
        description: "Webhook events deduplicated by the Inbox (duplicate ProviderEventId detected).");
    private static readonly Histogram<double> InboxHandlerDuration = Meter.CreateHistogram<double>(
        name: "orderprocessing.inbox.handler_duration",
        unit: "ms",
        description: "Processing duration for Inbox event handlers, per event type.");
    private static readonly Counter<long> WebhookUnresolvableTenant = Meter.CreateCounter<long>(
        name: "orderprocessing.webhook.unresolvable_tenant",
        unit: "{event}",
        description: "Webhook events rejected because tenant could not be resolved from metadata.");

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

    // Phase 8.7 — Webhook + Inbox metric recording methods

    public static void RecordWebhookHmacFailure(string providerName)
    {
        WebhookHmacFailures.Add(1, new TagList
        {
            { "provider", Normalize(providerName) }
        });
    }

    public static void RecordInboxDedupHit(string providerName, string eventType)
    {
        InboxDedupHits.Add(1, new TagList
        {
            { "provider", Normalize(providerName) },
            { "event_type", Normalize(eventType) }
        });
    }

    public static void RecordInboxHandlerDuration(string eventType, string outcome, TimeSpan duration)
    {
        InboxHandlerDuration.Record(duration.TotalMilliseconds, new TagList
        {
            { "event_type", Normalize(eventType) },
            { "outcome", Normalize(outcome) }
        });
    }

    public static void RecordWebhookUnresolvableTenant(string providerName, string eventType)
    {
        WebhookUnresolvableTenant.Add(1, new TagList
        {
            { "provider", Normalize(providerName) },
            { "event_type", Normalize(eventType) }
        });
    }

    private static string Normalize(string? value) =>
        string.IsNullOrWhiteSpace(value) ? "unknown" : value.Trim();
}