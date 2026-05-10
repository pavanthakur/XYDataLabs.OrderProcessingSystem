using System.Reflection;

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
        // Scan the Application assembly for anything implementing IIntegrationEvent
        _types = Assembly.GetExecutingAssembly().GetTypes()
            .Where(t => !t.IsAbstract && !t.IsInterface && typeof(IIntegrationEvent).IsAssignableFrom(t))
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
