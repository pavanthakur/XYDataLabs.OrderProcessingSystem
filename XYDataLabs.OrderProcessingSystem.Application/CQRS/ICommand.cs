namespace XYDataLabs.OrderProcessingSystem.Application.CQRS;

/// <summary>
/// Marker interface for commands (write operations with side effects).
/// </summary>
public interface ICommand<TResult>;
