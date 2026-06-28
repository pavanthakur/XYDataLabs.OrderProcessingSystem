namespace XYDataLabs.OrderProcessingSystem.Application.CQRS;

public interface IDispatcher
{
    Task<TResult> SendAsync<TResult>(XYDataLabs.OrderProcessingSystem.SharedKernel.CQRS.ICommand<TResult> command, CancellationToken cancellationToken = default);
    Task<TResult> QueryAsync<TResult>(XYDataLabs.OrderProcessingSystem.SharedKernel.CQRS.IQuery<TResult> query, CancellationToken cancellationToken = default);
}
