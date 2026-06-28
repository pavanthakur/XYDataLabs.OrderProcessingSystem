using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Events;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Webhooks;

namespace XYDataLabs.OrderProcessingSystem.Architecture.Tests;

public sealed class WorkerCancellationTests
{
    [Fact]
    public async Task Background_Workers_Should_Exit_Immediately_When_The_Stop_Token_Is_Already_Canceled()
    {
        using var serviceProvider = new ServiceCollection().BuildServiceProvider();

        await AssertWorkerStopsAsync(new OutboxPublisherWorker(serviceProvider, NullLogger<OutboxPublisherWorker>.Instance));
        await AssertWorkerStopsAsync(new PaymentReconciliationWorker(serviceProvider, NullLogger<PaymentReconciliationWorker>.Instance));
        await AssertWorkerStopsAsync(new InboxProcessorWorker(serviceProvider, NullLogger<InboxProcessorWorker>.Instance));
    }

    private static async Task AssertWorkerStopsAsync(object worker)
    {
        using var cts = new CancellationTokenSource();
        cts.Cancel();

        var method = worker.GetType().GetMethod("ExecuteAsync", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic);
        method.Should().NotBeNull();

        var task = (Task)method!.Invoke(worker, [cts.Token])!;

        await FluentActions.Awaiting(() => task).Should().CompleteWithinAsync(TimeSpan.FromSeconds(2));
    }
}
