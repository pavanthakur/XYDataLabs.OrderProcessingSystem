using FluentAssertions;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Inventory.Features.Specifications;
using XYDataLabs.OrderProcessingSystem.Notifications.Features.Specifications;
using XYDataLabs.OrderProcessingSystem.Payments.Features.Specifications;

namespace XYDataLabs.OrderProcessingSystem.Architecture.Tests;

public sealed class SpecificationStandardizationTests
{
    [Fact]
    public void Module_Specifications_Should_Be_Available_Across_The_Split_Modules()
    {
        var inventorySpec = new ProductsByIdsSpecification([1, 2, 3]);
        inventorySpec.Criteria.Compile().Invoke(new Product { ProductId = 2 }).Should().BeTrue();

        var notificationSpec = new PendingInboxMessagesSpecification();
        notificationSpec.Criteria.Compile().Invoke(new InboxMessage { Status = InboxMessageStatus.Received }).Should().BeTrue();

        var paymentSpec = new ActivePaymentProvidersSpecification(includeProductionProviders: false);
        paymentSpec.Criteria.Compile().Invoke(new PaymentProvider { IsActive = true, IsProduction = false }).Should().BeTrue();
    }
}
