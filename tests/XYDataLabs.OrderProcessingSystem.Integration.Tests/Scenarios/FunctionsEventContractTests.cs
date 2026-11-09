using FluentAssertions;
using XYDataLabs.OrderProcessingSystem.Functions;
using XYDataLabs.OrderProcessingSystem.Orders.Contracts.Events;
using XYDataLabs.OrderProcessingSystem.Payments.Contracts.Events;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

public sealed class FunctionsEventContractTests
{
    [Fact]
    public void FunctionsReplay_ExplicitlyLoadsEverySupportedContract()
    {
        var resolver=FunctionEventContracts.CreateResolver();
        foreach(var contract in new[]{typeof(OrderCreatedV1),typeof(PaymentAttemptSucceededV1),typeof(PaymentAttemptFailedV1)})
            resolver.ResolveType(contract.Name).Should().Be(contract);
        resolver.ResolveType("UnknownEvent").Should().BeNull();
    }
}
