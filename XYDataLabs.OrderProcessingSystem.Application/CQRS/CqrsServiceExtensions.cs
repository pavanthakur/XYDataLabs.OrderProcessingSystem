using System.Reflection;
using Microsoft.Extensions.DependencyInjection;
using XYDataLabs.OrderProcessingSystem.Application.CQRS.Behaviors;
using XYDataLabs.OrderProcessingSystem.Application.Events;

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

        foreach (var type in assembly.GetTypes().Where(t => t is { IsAbstract: false, IsInterface: false } && typeof(IDomainEventToIntegrationEventMapper).IsAssignableFrom(t)))
        {
            services.AddSingleton(typeof(IDomainEventToIntegrationEventMapper), type);

            foreach (var iface in type.GetInterfaces())
            {
                if (!iface.IsGenericType) continue;

                if (iface.GetGenericTypeDefinition() == typeof(IDomainEventToIntegrationEventMapper<,>))
                {
                    services.AddSingleton(iface, type);
                }
            }
        }

        services.AddSingleton<IIntegrationEventMapperRegistry, IntegrationEventMapperRegistry>();

        // Register open-generic pipeline behaviors (order: tenant validation → caching → logging → validation)
        services.AddScoped(typeof(IPipelineBehavior<,>), typeof(TenantValidationBehavior<,>));
        services.AddScoped(typeof(IPipelineBehavior<,>), typeof(CachingBehavior<,>));
        services.AddScoped(typeof(IPipelineBehavior<,>), typeof(LoggingBehavior<,>));
        services.AddScoped(typeof(IPipelineBehavior<,>), typeof(ValidationBehavior<,>));

        // Register dispatcher
        services.AddScoped<IDispatcher, Dispatcher>();

        return services;
    }
}
