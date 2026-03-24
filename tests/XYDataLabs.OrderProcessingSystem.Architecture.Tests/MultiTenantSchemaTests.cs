using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.UI.Models;

namespace XYDataLabs.OrderProcessingSystem.Architecture.Tests;

public class MultiTenantSchemaTests
{
    [Fact]
    public void TenantOwned_Payment_Entities_Should_Define_Required_Composite_Indexes()
    {
        using var context = CreateDbContext();
        var model = context.Model;

        HasIndex(model.FindEntityType(typeof(CardTransaction)), nameof(CardTransaction.TenantId), nameof(CardTransaction.CustomerOrderId)).Should().BeTrue();
        HasIndex(model.FindEntityType(typeof(CardTransaction)), nameof(CardTransaction.TenantId), nameof(CardTransaction.AttemptOrderId)).Should().BeTrue();
        HasIndex(model.FindEntityType(typeof(PayinLog)), nameof(PayinLog.TenantId), nameof(PayinLog.AttemptOrderId)).Should().BeTrue();
        HasIndex(model.FindEntityType(typeof(TransactionStatusHistory)), nameof(TransactionStatusHistory.TenantId), nameof(TransactionStatusHistory.AttemptOrderId)).Should().BeTrue();
    }

    [Fact]
    public void Tenants_Table_Should_Not_Have_Global_Query_Filter()
    {
        using var context = CreateDbContext();
        var tenantEntity = context.Model.FindEntityType(typeof(Tenant));

        tenantEntity.Should().NotBeNull();
        tenantEntity!.GetQueryFilter().Should().BeNull(
            because: "tenant resolution must query the Tenants table without bootstrapping through an ambient tenant filter");
    }

    [Fact]
    public void TenantOwned_Entities_Should_Have_Global_Query_Filters()
    {
        using var context = CreateDbContext();

        context.Model.FindEntityType(typeof(CardTransaction))!.GetQueryFilter().Should().NotBeNull();
        context.Model.FindEntityType(typeof(PayinLog))!.GetQueryFilter().Should().NotBeNull();
        context.Model.FindEntityType(typeof(TransactionStatusHistory))!.GetQueryFilter().Should().NotBeNull();
    }

    [Fact]
    public void CustomerFacing_Payment_Types_Should_Not_Expose_Internal_Identifiers()
    {
        var customerFacingTypes = new[]
        {
            typeof(CustomerWithCardPaymentRequestDto),
            typeof(PaymentDto),
            typeof(PaymentStatusDetailsDto),
            typeof(PaymentCallbackViewModel)
        };

        var bannedPropertyNames = new[]
        {
            "OrderId",
            "AttemptOrderId",
            "PaymentTraceId",
            "TenantId",
            "ReferenceNo",
            "APINO1",
            "APINO2"
        };

        foreach (var type in customerFacingTypes)
        {
            var exposedBannedProperties = type
                .GetProperties()
                .Select(property => property.Name)
                .Where(propertyName => bannedPropertyNames.Contains(propertyName, StringComparer.Ordinal))
                .ToArray();

            exposedBannedProperties.Should().BeEmpty(
                because: $"{type.Name} must expose only customer-safe payment identifiers");
        }

        typeof(CustomerWithCardPaymentRequestDto).GetProperty(nameof(CustomerWithCardPaymentRequestDto.CustomerOrderId)).Should().NotBeNull();
        typeof(PaymentDto).GetProperty(nameof(PaymentDto.CustomerOrderId)).Should().NotBeNull();
        typeof(PaymentStatusDetailsDto).GetProperty(nameof(PaymentStatusDetailsDto.CustomerOrderId)).Should().NotBeNull();
    }

    [Fact]
    public void Technical_Payment_Reconciliation_Request_Should_Use_AttemptOrderId_Only()
    {
        typeof(PaymentStatusLookupRequestDto).GetProperty(nameof(PaymentStatusLookupRequestDto.AttemptOrderId)).Should().NotBeNull();
        typeof(PaymentStatusLookupRequestDto).GetProperty("OrderId").Should().BeNull();
    }

    [Fact]
    public void Tenant_Should_Have_TenantTier_Column()
    {
        using var context = CreateDbContext();
        var tenantEntity = context.Model.FindEntityType(typeof(Tenant));

        tenantEntity.Should().NotBeNull();
        var property = tenantEntity!.FindProperty(nameof(Tenant.TenantTier));
        property.Should().NotBeNull(because: "the Tenant entity must have a TenantTier column for hybrid multitenancy");
        property!.IsNullable.Should().BeFalse(because: "TenantTier is required");
        property.GetMaxLength().Should().Be(20);
    }

    [Fact]
    public void Tenant_Should_Have_ConnectionString_Column()
    {
        using var context = CreateDbContext();
        var tenantEntity = context.Model.FindEntityType(typeof(Tenant));

        tenantEntity.Should().NotBeNull();
        var property = tenantEntity!.FindProperty(nameof(Tenant.ConnectionString));
        property.Should().NotBeNull(because: "the Tenant entity must have a ConnectionString column for dedicated database routing");
        property!.IsNullable.Should().BeTrue(because: "ConnectionString is null for SharedPool tenants");
        property.GetMaxLength().Should().Be(500);
    }

    [Fact]
    public void TenantRegistryDbContext_Tenant_Should_Not_Have_Global_Query_Filter()
    {
        var options = new DbContextOptionsBuilder<TenantRegistryDbContext>()
            .UseSqlServer("Server=(localdb)\\mssqllocaldb;Database=SchemaTests_DoNotConnect;Trusted_Connection=True;")
            .Options;

        using var registryContext = new TenantRegistryDbContext(options);
        var tenantEntity = registryContext.Model.FindEntityType(typeof(Tenant));

        tenantEntity.Should().NotBeNull();
        tenantEntity!.GetQueryFilter().Should().BeNull(
            because: "TenantRegistryDbContext must not apply query filters — it is used for pre-auth tenant resolution");
    }

    [Fact]
    public void CardTransaction_Should_Not_Store_Raw_Card_Data()
    {
        var cardTransactionType = typeof(CardTransaction);

        cardTransactionType.GetProperty("CreditCardNumber").Should().BeNull(
            because: "raw PAN must never be stored — use MaskedCardNumber (BIN + last 4) instead");

        cardTransactionType.GetProperty("CreditCardCvv2").Should().BeNull(
            because: "CVV2 must never be persisted per PCI DSS 3.2");

        cardTransactionType.GetProperty(nameof(CardTransaction.MaskedCardNumber)).Should().NotBeNull(
            because: "CardTransaction must store only the masked card number for audit purposes");
    }

    // ------------------------------------------------------------------ Fix 1 regression guard

    [Fact]
    public void CardTransaction_FK_To_BillingCustomers_Should_Be_Named_BillingCustomerId()
    {
        // Regression guard for fix 1: the FK was renamed from CustomerId to BillingCustomerId.
        // A future refactor must not silently reintroduce the old column name.
        var type = typeof(CardTransaction);

        type.GetProperty("BillingCustomerId").Should().NotBeNull(
            because: "CardTransaction.BillingCustomerId is the FK to BillingCustomers (renamed from CustomerId in fix 1)");

        type.GetProperty("CustomerId").Should().BeNull(
            because: "the old CustomerId property was renamed BillingCustomerId; re-adding it would create " +
                     "a confusing ambiguity and break DB join queries");
    }

    // ------------------------------------------------------------------ Fix 2 regression guard

    [Fact]
    public void Customer_Should_Not_Have_OpenpayCustomerId_Property()
    {
        // Regression guard for fix 2: OpenpayCustomerId was never populated in any code path
        // and was removed as a dead column. Its re-addition would create a misleading empty column
        // and would require a new migration.
        typeof(Customer).GetProperty("OpenpayCustomerId").Should().BeNull(
            because: "OpenpayCustomerId was a dead column on Customer that was removed in fix 2; " +
                     "OpenPay customer IDs are stored on BillingCustomer.APICustomerId instead");
    }

    private static bool HasIndex(IEntityType? entityType, params string[] propertyNames)
    {
        entityType.Should().NotBeNull();

        return entityType!
            .GetIndexes()
            .Any(index => index.Properties.Select(property => property.Name).SequenceEqual(propertyNames));
    }

    private static OrderProcessingSystemDbContext CreateDbContext()
    {
        var options = new DbContextOptionsBuilder<OrderProcessingSystemDbContext>()
            .UseSqlServer("Server=(localdb)\\mssqllocaldb;Database=SchemaTests_DoNotConnect;Trusted_Connection=True;")
            .Options;

        return new OrderProcessingSystemDbContext(options);
    }
}