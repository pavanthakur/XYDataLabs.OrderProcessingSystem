namespace XYDataLabs.OrderProcessingSystem.Application.CQRS;

public interface IQueryHandler<in TQuery, TResult> : XYDataLabs.OrderProcessingSystem.SharedKernel.CQRS.IQueryHandler<TQuery, TResult>
    where TQuery : XYDataLabs.OrderProcessingSystem.SharedKernel.CQRS.IQuery<TResult>
{
}
