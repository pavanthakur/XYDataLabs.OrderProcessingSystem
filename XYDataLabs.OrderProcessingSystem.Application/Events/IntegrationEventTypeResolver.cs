using System.Reflection;
using SharedIntegrationEvent = XYDataLabs.OrderProcessingSystem.Eventing.Abstractions.IIntegrationEvent;

namespace XYDataLabs.OrderProcessingSystem.Application.Events;

public interface IIntegrationEventTypeResolver
{
    Type? ResolveType(string eventType);
}

public class IntegrationEventTypeResolver : IIntegrationEventTypeResolver
{
    private readonly Dictionary<string, Type> _types;

    public IntegrationEventTypeResolver()
    {
        // Scan all loaded assemblies so module-specific integration events are visible too.
        _types = AppDomain.CurrentDomain.GetAssemblies()
            .SelectMany(assembly =>
            {
                try
                {
                    return assembly.GetTypes();
                }
                catch (ReflectionTypeLoadException ex)
                {
                    return ex.Types.Where(type => type is not null).Cast<Type>();
                }
            })
            .Where(t => !t.IsAbstract && !t.IsInterface && typeof(SharedIntegrationEvent).IsAssignableFrom(t))
            .ToDictionary(
                t => t.Name, // Example: "OrderCreatedV1"
                t => t);
    }

    public Type? ResolveType(string eventType)
    {
        _types.TryGetValue(eventType, out var type);
        return type;
    }
}
