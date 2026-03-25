namespace XYDataLabs.OrderProcessingSystem.Application.CQRS;

/// <summary>
/// Marker interface for queries (read operations with no side effects).
/// </summary>
public interface IQuery<TResult>;
