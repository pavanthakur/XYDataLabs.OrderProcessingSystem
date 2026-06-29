namespace XYDataLabs.OrderProcessingSystem.Application.CQRS;

/// <summary>
/// Backward-compatible alias for the shared CQRS query marker.
/// </summary>
public interface IQuery<TResult> : XYDataLabs.OrderProcessingSystem.SharedKernel.CQRS.IQuery<TResult>;
