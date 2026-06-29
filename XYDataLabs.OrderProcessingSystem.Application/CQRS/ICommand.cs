namespace XYDataLabs.OrderProcessingSystem.Application.CQRS;

/// <summary>
/// Backward-compatible alias for the shared CQRS command marker.
/// </summary>
public interface ICommand<TResult> : XYDataLabs.OrderProcessingSystem.SharedKernel.CQRS.ICommand<TResult>;
