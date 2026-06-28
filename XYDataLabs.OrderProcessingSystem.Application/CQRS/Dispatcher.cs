using Microsoft.Extensions.DependencyInjection;

namespace XYDataLabs.OrderProcessingSystem.Application.CQRS;

public sealed class Dispatcher : IDispatcher
{
    private readonly IServiceProvider _provider;

    public Dispatcher(IServiceProvider provider) => _provider = provider;

    public Task<TResult> SendAsync<TResult>(XYDataLabs.OrderProcessingSystem.SharedKernel.CQRS.ICommand<TResult> command, CancellationToken cancellationToken = default)
    {
        var handler = ResolveHandler(
            command.GetType(),
            typeof(ICommandHandler<,>),
            typeof(XYDataLabs.OrderProcessingSystem.SharedKernel.CQRS.ICommandHandler<,>),
            typeof(TResult));
        var method = handler.GetType().GetMethods()
            .Single(m => string.Equals(m.Name, "HandleAsync", StringComparison.Ordinal)
                && m.GetParameters().Length == 2);

        return BuildPipeline(command, () => (Task<TResult>)method.Invoke(handler, [command, cancellationToken])!, cancellationToken);
    }

    public Task<TResult> QueryAsync<TResult>(XYDataLabs.OrderProcessingSystem.SharedKernel.CQRS.IQuery<TResult> query, CancellationToken cancellationToken = default)
    {
        var handler = ResolveHandler(
            query.GetType(),
            typeof(IQueryHandler<,>),
            typeof(XYDataLabs.OrderProcessingSystem.SharedKernel.CQRS.IQueryHandler<,>),
            typeof(TResult));
        var method = handler.GetType().GetMethods()
            .Single(m => string.Equals(m.Name, "HandleAsync", StringComparison.Ordinal)
                && m.GetParameters().Length == 2);

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
            var handleMethod = capturedBehavior.GetType().GetMethods()
                .Single(m => string.Equals(m.Name, "HandleAsync", StringComparison.Ordinal)
                    && m.GetParameters().Length == 3);
            pipeline = () => (Task<TResult>)handleMethod.Invoke(capturedBehavior, [request, captured, cancellationToken])!;
        }

        return pipeline();
    }

    private object ResolveHandler(
        Type requestType,
        Type applicationHandlerOpenGeneric,
        Type sharedKernelHandlerOpenGeneric,
        Type resultType)
    {
        var applicationHandlerType = applicationHandlerOpenGeneric.MakeGenericType(requestType, resultType);
        var handler = _provider.GetService(applicationHandlerType);
        if (handler is not null)
        {
            return handler;
        }

        var sharedKernelHandlerType = sharedKernelHandlerOpenGeneric.MakeGenericType(requestType, resultType);
        handler = _provider.GetService(sharedKernelHandlerType);
        if (handler is not null)
        {
            return handler;
        }

        throw new InvalidOperationException(
            $"No service for type '{applicationHandlerType.FullName}' or '{sharedKernelHandlerType.FullName}' has been registered.");
    }
}
