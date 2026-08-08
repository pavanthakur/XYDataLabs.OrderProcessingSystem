using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Events;
using XYDataLabs.OrderProcessingSystem.Orders.Contracts.Events;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

[Trait("Category", "Integration")]
public sealed class SequentialEventDispatchIntegrationTests
{
    [Fact]
    public async Task Publisher_Should_Run_OrderCreated_Handlers_Sequentially_Within_The_Ambient_Scope()
    {
        var services = new ServiceCollection();
        services.AddSingleton<SequentialDispatchProbe>();
        services.AddScoped<IEventHandler<OrderCreatedV1>, SequencedOrderCreatedHandlerA>();
        services.AddScoped<IEventHandler<OrderCreatedV1>, SequencedOrderCreatedHandlerB>();
        services.AddScoped<IEventPublisher, InMemoryEventPublisher>();

        await using var scope = services.BuildServiceProvider().CreateAsyncScope();

        var publisher = scope.ServiceProvider.GetRequiredService<IEventPublisher>();
        var probe = scope.ServiceProvider.GetRequiredService<SequentialDispatchProbe>();

        await publisher.PublishAsync(EventEnvelope.Create(
            nameof(OrderCreatedV1),
            schemaVersion: 1,
            occurredUtc: DateTime.UtcNow,
            payload: new OrderCreatedV1(1, DateTime.UtcNow, 25m, 2, Guid.NewGuid(), "MXN"),
            messageId: Guid.NewGuid()));

        probe.ExecutionOrder.Should().Equal("A-start", "A-end", "B-start", "B-end");
        probe.MaxConcurrency.Should().Be(1);
    }

    private sealed class SequentialDispatchProbe
    {
        private int _currentConcurrency;
        private int _maxConcurrency;

        public List<string> ExecutionOrder { get; } = new();
        public int MaxConcurrency => _maxConcurrency;

        public void MarkStarted(string handlerName)
        {
            ExecutionOrder.Add($"{handlerName}-start");
            var currentConcurrency = Interlocked.Increment(ref _currentConcurrency);
            var observed = _maxConcurrency;

            while (currentConcurrency > observed)
            {
                var original = Interlocked.CompareExchange(ref _maxConcurrency, currentConcurrency, observed);
                if (original == observed)
                {
                    break;
                }

                observed = original;
            }
        }

        public void MarkCompleted(string handlerName)
        {
            ExecutionOrder.Add($"{handlerName}-end");
            Interlocked.Decrement(ref _currentConcurrency);
        }
    }

    private abstract class SequencedOrderCreatedHandler : IEventHandler<OrderCreatedV1>
    {
        private readonly SequentialDispatchProbe _probe;
        private readonly string _handlerName;

        protected SequencedOrderCreatedHandler(SequentialDispatchProbe probe, string handlerName)
        {
            _probe = probe;
            _handlerName = handlerName;
        }

        public async Task HandleAsync(
            EventEnvelope envelope,
            OrderCreatedV1 integrationEvent,
            CancellationToken cancellationToken = default)
        {
            _probe.MarkStarted(_handlerName);

            try
            {
                await Task.Yield();
            }
            finally
            {
                _probe.MarkCompleted(_handlerName);
            }
        }
    }

    private sealed class SequencedOrderCreatedHandlerA(SequentialDispatchProbe probe)
        : SequencedOrderCreatedHandler(probe, "A");

    private sealed class SequencedOrderCreatedHandlerB(SequentialDispatchProbe probe)
        : SequencedOrderCreatedHandler(probe, "B");
}
