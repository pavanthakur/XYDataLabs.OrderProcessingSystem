using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Orders.Contracts.Events;
using XYDataLabs.OrderProcessingSystem.Payments.Contracts.Events;

namespace XYDataLabs.OrderProcessingSystem.Functions;

public static class FunctionEventContracts
{
    // Cold Functions workers may not have loaded contract assemblies yet.
    // Explicit assemblies make replay independent of incidental prior requests.
    public static IIntegrationEventTypeResolver CreateResolver() => IntegrationEventTypeResolver.FromAssemblies(
        typeof(OrderCreatedV1).Assembly,typeof(PaymentAttemptSucceededV1).Assembly);
}
