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

        // Register both application-local CQRS interfaces and the shared-kernel variants.
        // Some feature assemblies implement the shared-kernel contracts directly.
        var handlerInterfaces = new[]
        {
            typeof(ICommandHandler<,>),
            typeof(IQueryHandler<,>),
            typeof(XYDataLabs.OrderProcessingSystem.SharedKernel.CQRS.ICommandHandler<,>),
            typeof(XYDataLabs.OrderProcessingSystem.SharedKernel.CQRS.IQueryHandler<,>)
        };

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
                else if (definition == typeof(IEventHandler<>))
                {
                    // Register the concrete handler implementation so it can be resolved by the activator
                    services.AddScoped(type);

                    // Register the decorator to fulfill the interface
                    var eventType = iface.GetGenericArguments()[0];
                    var decoratorType = typeof(IdempotentEventHandlerDecorator<>).MakeGenericType(eventType);
                    
                    services.AddScoped(iface, provider =>
                    {
                        var innerHandler = provider.GetRequiredService(type);
                        var idempotencyGuard = provider.GetRequiredService<IIdempotencyGuard>();
                        
                        var loggerType = typeof(Microsoft.Extensions.Logging.ILogger<>).MakeGenericType(decoratorType);
                        var logger = provider.GetRequiredService(loggerType);
                        
                        return Activator.CreateInstance(decoratorType, innerHandler, idempotencyGuard, logger)!;
                    });
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
