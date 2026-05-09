using Microsoft.Extensions.DependencyInjection;
using XYDataLabs.OrderProcessingSystem.Application.Events;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Events;

public class InMemoryEventPublisher : IEventPublisher
{
    private readonly IServiceProvider _serviceProvider;

    public InMemoryEventPublisher(IServiceProvider serviceProvider)
    {
        _serviceProvider = serviceProvider;
    }

    public async Task PublishAsync(EventEnvelope eventEnvelope, CancellationToken cancellationToken = default)
    {
        var payloadType = eventEnvelope.Payload.GetType();
        
        // Dynamically build the Generic interface type: IEventHandler<TPayload>
        var handlerType = typeof(IEventHandler<>).MakeGenericType(payloadType);
        
        // Resolve all registered handlers for this specific event type
        var handlers = _serviceProvider.GetServices(handlerType);

        if (!handlers.Any())
        {
            // If no handlers registered, simply return (events can be fire-and-forget)
            return;
        }

        // Dynamically extract the HandleAsync method
        var handleMethod = handlerType.GetMethod("HandleAsync");

        if (handleMethod == null)
            throw new InvalidOperationException($"Method 'HandleAsync' not found on {handlerType.Name}.");

        // Invoke all handlers concurrently
        var tasks = handlers.Select(handler =>
        {
            var task = handleMethod.Invoke(handler, new[] { eventEnvelope.Payload, cancellationToken }) as Task;
            return task ?? Task.CompletedTask;
        });

        await Task.WhenAll(tasks);
    }
}
