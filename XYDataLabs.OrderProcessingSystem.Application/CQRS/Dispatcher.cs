using Microsoft.Extensions.DependencyInjection;

namespace XYDataLabs.OrderProcessingSystem.Application.CQRS;

public sealed class Dispatcher : IDispatcher
{
    private readonly IServiceProvider _provider;

    public Dispatcher(IServiceProvider provider) => _provider = provider;

    public Task<TResult> SendAsync<TResult>(ICommand<TResult> command, CancellationToken cancellationToken = default)
    {
        var handlerType = typeof(ICommandHandler<,>).MakeGenericType(command.GetType(), typeof(TResult));
        var handler = _provider.GetRequiredService(handlerType);
        var method = handlerType.GetMethod(nameof(ICommandHandler<ICommand<TResult>, TResult>.HandleAsync))!;

        return BuildPipeline(command, () => (Task<TResult>)method.Invoke(handler, [command, cancellationToken])!, cancellationToken);
    }

    public Task<TResult> QueryAsync<TResult>(IQuery<TResult> query, CancellationToken cancellationToken = default)
    {
        var handlerType = typeof(IQueryHandler<,>).MakeGenericType(query.GetType(), typeof(TResult));
        var handler = _provider.GetRequiredService(handlerType);
        var method = handlerType.GetMethod(nameof(IQueryHandler<IQuery<TResult>, TResult>.HandleAsync))!;

        return BuildPipeline(query, () => (Task<TResult>)method.Invoke(handler, [query, cancellationToken])!, cancellationToken);
    }

    private Task<TResult> BuildPipeline<TResult>(object request, Func<Task<TResult>> handler, CancellationToken cancellationToken)
    {
        var behaviorType = typeof(IPipelineBehavior<,>).MakeGenericType(request.GetType(), typeof(TResult));
        var behaviors = (IEnumerable<object>)_provider.GetServices(behaviorType);

        // Chain behaviors: outermost registered first
        var pipeline = handler;
        foreach (var behavior in behaviors.Reverse())
        {
            var captured = pipeline;
            var capturedBehavior = behavior;
            var handleMethod = behaviorType.GetMethod(nameof(IPipelineBehavior<object, TResult>.HandleAsync))!;
            pipeline = () => (Task<TResult>)handleMethod.Invoke(capturedBehavior, [request, captured, cancellationToken])!;
        }

        return pipeline();
    }
}
