using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Orders.Features.Events;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Events;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

[Trait("Category", "Integration")]
public sealed class ParallelEventDispatchIntegrationTests
{
    [Fact]
    public async Task Publisher_Should_Run_OrderCreated_Handlers_In_Parallel_Without_Blocking_Each_Other()
    {
        var services = new ServiceCollection();
        services.AddSingleton<ParallelDispatchProbe>();
        services.AddScoped<IEventHandler<OrderCreatedV1>, CoordinatedOrderCreatedHandlerA>();
        services.AddScoped<IEventHandler<OrderCreatedV1>, CoordinatedOrderCreatedHandlerB>();
        services.AddScoped<IEventPublisher, InMemoryEventPublisher>();

        await using var scope = services.BuildServiceProvider().CreateAsyncScope();

        var publisher = scope.ServiceProvider.GetRequiredService<IEventPublisher>();
        var probe = scope.ServiceProvider.GetRequiredService<ParallelDispatchProbe>();

        var publishTask = publisher.PublishAsync(EventEnvelope.Create(
            nameof(OrderCreatedV1),
            schemaVersion: 1,
            occurredUtc: DateTime.UtcNow,
            payload: new OrderCreatedV1(1, DateTime.UtcNow, 25m, 2),
            messageId: Guid.NewGuid()));

        var bothStarted = await Task.WhenAny(probe.BothHandlersStarted.Task, Task.Delay(TimeSpan.FromSeconds(5)));
        bothStarted.Should().BeSameAs(probe.BothHandlersStarted.Task);

        probe.ReleaseHandlers.TrySetResult();
        await publishTask;

        probe.StartedHandlers.Should().Be(2);
        probe.CompletedHandlers.Should().Be(2);
        probe.MaxConcurrency.Should().BeGreaterThanOrEqualTo(2);
    }

    private sealed class ParallelDispatchProbe
    {
        private int _currentConcurrency;
        private int _maxConcurrency;
        private int _startedHandlers;
        private int _completedHandlers;

        public TaskCompletionSource BothHandlersStarted { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public TaskCompletionSource ReleaseHandlers { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);

        public int StartedHandlers => _startedHandlers;
        public int CompletedHandlers => _completedHandlers;
        public int MaxConcurrency => _maxConcurrency;

        public void MarkStarted()
        {
            var startedHandlers = Interlocked.Increment(ref _startedHandlers);
            var currentConcurrency = Interlocked.Increment(ref _currentConcurrency);

            UpdateMaxConcurrency(currentConcurrency);

            if (startedHandlers == 2)
            {
                BothHandlersStarted.TrySetResult();
            }
        }

        public void MarkCompleted()
        {
            Interlocked.Increment(ref _completedHandlers);
            Interlocked.Decrement(ref _currentConcurrency);
        }

        private void UpdateMaxConcurrency(int currentConcurrency)
        {
            var observed = _maxConcurrency;
            while (currentConcurrency > observed)
            {
                var original = Interlocked.CompareExchange(ref _maxConcurrency, currentConcurrency, observed);
                if (original == observed)
                {
                    return;
                }

                observed = original;
            }
        }
    }

    private abstract class CoordinatedOrderCreatedHandler : IEventHandler<OrderCreatedV1>
    {
        private readonly ParallelDispatchProbe _probe;

        protected CoordinatedOrderCreatedHandler(ParallelDispatchProbe probe)
        {
            _probe = probe;
        }

        public async Task HandleAsync(
            EventEnvelope envelope,
            OrderCreatedV1 integrationEvent,
            CancellationToken cancellationToken = default)
        {
            _probe.MarkStarted();

            try
            {
                await _probe.ReleaseHandlers.Task.WaitAsync(cancellationToken);
            }
            finally
            {
                _probe.MarkCompleted();
            }
        }
    }

    private sealed class CoordinatedOrderCreatedHandlerA(ParallelDispatchProbe probe)
        : CoordinatedOrderCreatedHandler(probe);

    private sealed class CoordinatedOrderCreatedHandlerB(ParallelDispatchProbe probe)
        : CoordinatedOrderCreatedHandler(probe);
}
