using System.Reflection;
using Microsoft.Extensions.DependencyInjection;
using XYDataLabs.OrderProcessingSystem.Application.CQRS.Behaviors;

namespace XYDataLabs.OrderProcessingSystem.Application.CQRS;

public static class CqrsServiceExtensions
{
    /// <summary>
    /// Registers all CQRS handlers, pipeline behaviors, and the dispatcher from the calling assembly.
    /// </summary>
    public static IServiceCollection AddCqrs(this IServiceCollection services, Assembly? assembly = null)
    {
        assembly ??= Assembly.GetCallingAssembly();

        // Register all ICommandHandler<,> and IQueryHandler<,> implementations
        var handlerInterfaces = new[] { typeof(ICommandHandler<,>), typeof(IQueryHandler<,>) };

        foreach (var type in assembly.GetTypes().Where(t => t is { IsAbstract: false, IsInterface: false }))
        {
            foreach (var iface in type.GetInterfaces())
            {
                if (!iface.IsGenericType) continue;
                var definition = iface.GetGenericTypeDefinition();

                if (handlerInterfaces.Contains(definition))
                {
                    services.AddScoped(iface, type);
                }
            }
        }

        // Register open-generic pipeline behaviors (order matters: logging wraps validation)
        services.AddScoped(typeof(IPipelineBehavior<,>), typeof(LoggingBehavior<,>));
        services.AddScoped(typeof(IPipelineBehavior<,>), typeof(ValidationBehavior<,>));

        // Register dispatcher
        services.AddScoped<IDispatcher, Dispatcher>();

        return services;
    }
}
