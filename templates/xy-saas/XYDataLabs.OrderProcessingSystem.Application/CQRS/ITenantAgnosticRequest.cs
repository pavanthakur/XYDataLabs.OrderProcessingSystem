namespace XYDataLabs.OrderProcessingSystem.Application.CQRS;

/// <summary>
/// Marks a CQRS request as explicitly safe to execute without an ambient tenant context.
/// Use sparingly for bootstrap and system-level flows only.
/// </summary>
public interface ITenantAgnosticRequest;