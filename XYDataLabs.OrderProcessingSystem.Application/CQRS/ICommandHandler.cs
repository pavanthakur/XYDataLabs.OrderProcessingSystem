namespace XYDataLabs.OrderProcessingSystem.Application.CQRS;

public interface ICommandHandler<in TCommand, TResult> : XYDataLabs.OrderProcessingSystem.SharedKernel.CQRS.ICommandHandler<TCommand, TResult>
    where TCommand : XYDataLabs.OrderProcessingSystem.SharedKernel.CQRS.ICommand<TResult>
{
}
