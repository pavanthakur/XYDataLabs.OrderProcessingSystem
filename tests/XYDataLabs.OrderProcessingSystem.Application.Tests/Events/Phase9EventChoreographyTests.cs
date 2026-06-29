using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Inventory.Features.Events;
using XYDataLabs.OrderProcessingSystem.Notifications.Features.Events;
using XYDataLabs.OrderProcessingSystem.Orders.Features.Events;
using XYDataLabs.OrderProcessingSystem.Orders.Features.Module;
using XYDataLabs.OrderProcessingSystem.Inventory.Features.Module;
using XYDataLabs.OrderProcessingSystem.Notifications.Features.Module;
using XYDataLabs.OrderProcessingSystem.Payments.Features.Module;

namespace XYDataLabs.OrderProcessingSystem.Application.Tests.Events;

public sealed class Phase9EventChoreographyTests
{
    [Fact]
    public async Task OrderCreated_Should_Trigger_Inventory_Then_Notification_Handlers()
    {
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddSingleton<IIdempotencyGuard, NoOpIdempotencyGuard>();
        services.AddScoped<RecordingEventPublisher>();
        services.AddScoped<IEventPublisher>(sp => sp.GetRequiredService<RecordingEventPublisher>());
        services.AddCqrs(typeof(XYDataLabs.OrderProcessingSystem.Application.StartupHelper).Assembly);
        services.AddCqrs(typeof(OrdersModuleRegistration).Assembly);
        services.AddCqrs(typeof(InventoryModuleRegistration).Assembly);
        services.AddCqrs(typeof(NotificationsModuleRegistration).Assembly);
        services.AddCqrs(typeof(PaymentsModuleRegistration).Assembly);

        await using var serviceProvider = services.BuildServiceProvider(validateScopes: true);
        using var scope = serviceProvider.CreateScope();
        var publisher = scope.ServiceProvider.GetRequiredService<RecordingEventPublisher>();

        var envelope = EventEnvelope.Create(
            nameof(OrderCreatedV1),
            schemaVersion: 1,
            occurredUtc: DateTime.UtcNow,
            payload: new OrderCreatedV1(42, DateTime.UtcNow, 99.95m, 3),
            messageId: Guid.Parse("11111111-1111-1111-1111-111111111111"),
            correlationId: "corr-9-20",
            tenantId: 42);

        await publisher.PublishAsync(envelope);

        publisher.RecordedEventTypes.Should().Equal(
            nameof(OrderCreatedV1),
            nameof(InventoryReservedV1),
            nameof(NotificationRequestedV1));
    }

    private sealed class RecordingEventPublisher : IEventPublisher
    {
        private readonly IServiceProvider _serviceProvider;
        private readonly List<string> _recordedEventTypes = new();

        public RecordingEventPublisher(IServiceProvider serviceProvider)
        {
            _serviceProvider = serviceProvider;
        }

        public IReadOnlyList<string> RecordedEventTypes => _recordedEventTypes;

        public async Task PublishAsync(EventEnvelope eventEnvelope, CancellationToken cancellationToken = default)
        {
            _recordedEventTypes.Add(eventEnvelope.EventType);

            var payloadType = eventEnvelope.Payload.GetType();
            var handlerType = typeof(IEventHandler<>).MakeGenericType(payloadType);
            var handlers = _serviceProvider.GetServices(handlerType);

            if (!handlers.Any())
            {
                return;
            }

            var handleMethod = handlerType.GetMethod(nameof(IEventHandler<IIntegrationEvent>.HandleAsync));
            handleMethod.Should().NotBeNull();

            var tasks = handlers.Select(handler =>
            {
                var task = handleMethod!.Invoke(handler, new object[] { eventEnvelope, eventEnvelope.Payload, cancellationToken }) as Task;
                return task ?? Task.CompletedTask;
            });

            await Task.WhenAll(tasks);
        }
    }

    private sealed class NoOpIdempotencyGuard : IIdempotencyGuard
    {
        public Task<bool> HasProcessedAsync(Guid messageId, CancellationToken cancellationToken = default)
            => Task.FromResult(false);

        public Task MarkProcessedAsync(Guid messageId, CancellationToken cancellationToken = default)
            => Task.CompletedTask;
    }
}
