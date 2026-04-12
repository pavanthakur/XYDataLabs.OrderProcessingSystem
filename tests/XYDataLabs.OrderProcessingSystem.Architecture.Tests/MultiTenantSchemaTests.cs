using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

namespace XYDataLabs.OrderProcessingSystem.Architecture.Tests;

public class MultiTenantSchemaTests
{
    [Fact]
    public void TenantOwned_Payment_Entities_Should_Define_Required_Composite_Indexes()
    {
        using var context = CreateDbContext();
        var model = context.Model;

        HasIndex(model.FindEntityType(typeof(AuditLog)), nameof(AuditLog.TenantId), nameof(AuditLog.EntityName), nameof(AuditLog.EntityId)).Should().BeTrue();
        HasIndex(model.FindEntityType(typeof(AuditLog)), nameof(AuditLog.CreatedDate)).Should().BeTrue();
        HasIndex(model.FindEntityType(typeof(Order)), nameof(Order.TenantId), nameof(Order.CustomerId), nameof(Order.Status)).Should().BeTrue();
        HasIndex(model.FindEntityType(typeof(CardTransaction)), nameof(CardTransaction.TenantId), nameof(CardTransaction.CustomerOrderId)).Should().BeTrue();
        HasIndex(model.FindEntityType(typeof(CardTransaction)), nameof(CardTransaction.TenantId), nameof(CardTransaction.AttemptOrderId)).Should().BeTrue();
        HasIndex(model.FindEntityType(typeof(PayinLog)), nameof(PayinLog.TenantId), nameof(PayinLog.AttemptOrderId)).Should().BeTrue();
        HasIndex(model.FindEntityType(typeof(TransactionStatusHistory)), nameof(TransactionStatusHistory.TenantId), nameof(TransactionStatusHistory.AttemptOrderId)).Should().BeTrue();
    }

    [Fact]
    public void Order_Should_Use_RowVersion_Concurrency_Token()
    {
        using var context = CreateDbContext();
        var orderEntity = context.Model.FindEntityType(typeof(Order));

        orderEntity.Should().NotBeNull();

        var rowVersionProperty = orderEntity!.FindProperty(nameof(Order.RowVersion));
        rowVersionProperty.Should().NotBeNull();
        rowVersionProperty!.IsConcurrencyToken.Should().BeTrue();
        rowVersionProperty.ValueGenerated.Should().Be(ValueGenerated.OnAddOrUpdate);

        var statusProperty = orderEntity.FindProperty(nameof(Order.Status));
        statusProperty.Should().NotBeNull();
        statusProperty!.GetMaxLength().Should().Be(32);
        statusProperty.IsNullable.Should().BeFalse();
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

        context.Model.FindEntityType(typeof(AuditLog))!.GetQueryFilter().Should().NotBeNull();
        context.Model.FindEntityType(typeof(CardTransaction))!.GetQueryFilter().Should().NotBeNull();
        context.Model.FindEntityType(typeof(PayinLog))!.GetQueryFilter().Should().NotBeNull();
        context.Model.FindEntityType(typeof(TransactionStatusHistory))!.GetQueryFilter().Should().NotBeNull();
    }

    [Fact]
    public void AuditLog_Query_Should_Contain_Tenant_Filter_Predicate()
    {
        using var context = CreateDbContext(new TestTenantProvider(42, "TenantA"));

        var sql = context.AuditLogs
            .Where(item => item.EntityName == "Customer")
            .ToQueryString();

        sql.Should().MatchRegex("WHERE[\\s\\S]*TenantId[\\s\\S]*=[\\s\\S]*");
    }

    [Fact]
    public void CustomerFacing_Payment_Types_Should_Not_Expose_Internal_Identifiers()
    {
        var customerFacingTypes = new[]
        {
            typeof(CustomerWithCardPaymentRequestDto),
            typeof(PaymentDto),
            typeof(PaymentStatusDetailsDto)
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

    // ------------------------------------------------------------------ Tenant tier model guards

    [Fact]
    public void TenantTierConstants_Should_Define_SharedPool_And_Dedicated()
    {
        TenantTierConstants.SharedPool.Should().Be("SharedPool");
        TenantTierConstants.Dedicated.Should().Be("Dedicated");
    }

    [Fact]
    public void TenantTier_Default_Should_Be_SharedPool()
    {
        var tenant = new Tenant();
        tenant.TenantTier.Should().Be(TenantTierConstants.SharedPool,
            because: "new tenants default to SharedPool tier");
    }

    // ------------------------------------------------------------------ Dynamic guardrail tests (1.1–1.5 + FC4)

    [Fact]
    public void All_TenantOwned_Entities_Should_Inherit_AuditBase()
    {
        var auditBaseTypes = new[]
        {
            typeof(BaseAuditableEntity),
            typeof(BaseAuditableCreateEntity)
        };

        foreach (var entityType in GetAllTenantOwnedEntityTypes())
        {
            auditBaseTypes.Should().Contain(
                baseType => entityType.IsSubclassOf(baseType),
                because: $"{entityType.Name} is exposed via IAppDbContext and must inherit BaseAuditableEntity or BaseAuditableCreateEntity to guarantee TenantId + audit columns");
        }
    }

    [Fact]
    public void All_TenantOwned_Entities_Should_Have_Global_Query_Filter()
    {
        using var context = CreateDbContext();

        foreach (var entityType in GetAllTenantOwnedEntityTypes())
        {
            var efEntity = context.Model.FindEntityType(entityType);
            efEntity.Should().NotBeNull(because: $"{entityType.Name} must be mapped in OrderProcessingSystemDbContext");
            efEntity!.GetQueryFilter().Should().NotBeNull(
                because: $"{entityType.Name} is tenant-owned and must have a global query filter via ConfigureTenantOwnership");
        }
    }

    [Fact]
    public void All_TenantOwned_Entities_Should_Have_FK_To_Tenants()
    {
        using var context = CreateDbContext();
        var tenantEntity = context.Model.FindEntityType(typeof(Tenant));
        tenantEntity.Should().NotBeNull();

        foreach (var entityType in GetAllTenantOwnedEntityTypes())
        {
            var efEntity = context.Model.FindEntityType(entityType);
            efEntity.Should().NotBeNull();

            var fkToTenants = efEntity!.GetForeignKeys()
                .Any(fk => fk.PrincipalEntityType == tenantEntity &&
                           fk.Properties.Any(p => p.Name == "TenantId"));

            fkToTenants.Should().BeTrue(
                because: $"{entityType.Name} must have a foreign key from TenantId to Tenants(Id) via ConfigureTenantOwnership");
        }
    }

    [Fact]
    public void IAppDbContext_DbSets_Must_Match_OrderProcessingSystemDbContext_Minus_Tenant()
    {
        using var context = CreateDbContext();

        var interfaceDbSetTypes = typeof(IAppDbContext)
            .GetProperties()
            .Where(p => p.PropertyType.IsGenericType &&
                        p.PropertyType.GetGenericTypeDefinition() == typeof(DbSet<>))
            .Select(p => p.PropertyType.GetGenericArguments()[0])
            .OrderBy(t => t.Name)
            .ToList();

        var concreteDbSetTypes = typeof(OrderProcessingSystemDbContext)
            .GetProperties()
            .Where(p => p.PropertyType.IsGenericType &&
                        p.PropertyType.GetGenericTypeDefinition() == typeof(DbSet<>))
            .Select(p => p.PropertyType.GetGenericArguments()[0])
            .Where(t => t != typeof(Tenant))
            .OrderBy(t => t.Name)
            .ToList();

        interfaceDbSetTypes.Should().BeEquivalentTo(concreteDbSetTypes,
            because: "IAppDbContext must expose every DbSet from OrderProcessingSystemDbContext except Tenant (which is a system entity per ADR-007)");
    }

    [Fact]
    public void IAppDbContext_Should_Not_Expose_Tenant_DbSet()
    {
        var tenantDbSet = typeof(IAppDbContext)
            .GetProperties()
            .Where(p => p.PropertyType.IsGenericType &&
                        p.PropertyType.GetGenericTypeDefinition() == typeof(DbSet<>))
            .Any(p => p.PropertyType.GetGenericArguments()[0] == typeof(Tenant));

        tenantDbSet.Should().BeFalse(
            because: "IAppDbContext must NOT expose DbSet<Tenant> — tenant queries go through ITenantRegistry, not the application DbContext (ADR-007)");
    }

    [Fact]
    public void ITenantProvider_Must_Expose_Hybrid_Routing_Properties()
    {
        // This test guards the ADR-007 hybrid routing contract.
        // If ITenantProvider does not yet have these properties,
        // add them before proceeding with dedicated-DB tenant provisioning.
        var providerType = typeof(ITenantProvider);

        var missingProperties = new List<string>();

        if (providerType.GetProperty("HasTenantContext") == null)
            missingProperties.Add("HasTenantContext (bool) — required for guard checks in non-request paths");
        if (providerType.GetProperty("TenantId") == null)
            missingProperties.Add("TenantId (int) — required for query filter and FK stamping");
        if (providerType.GetProperty("TenantCode") == null)
            missingProperties.Add("TenantCode (string) — required for header resolution");
        if (providerType.GetProperty("TenantExternalId") == null)
            missingProperties.Add("TenantExternalId (string) — required for external API/webhook identity");
        if (providerType.GetProperty("ConnectionString") == null)
            missingProperties.Add("ConnectionString (string?) — required for hybrid DB routing");
        if (providerType.GetProperty("IsSharedPool") == null)
            missingProperties.Add("IsSharedPool (bool) — required for tier-aware query filter application");

        missingProperties.Should().BeEmpty(
            because: "ITenantProvider must expose hybrid routing properties per ADR-007. " +
                     "Add missing properties before provisioning any Dedicated-tier tenant.");
    }

    /// <summary>
    /// Returns all CLR types exposed as DbSet&lt;T&gt; on IAppDbContext.
    /// These are tenant-owned business entities (Tenant itself is excluded by design).
    /// </summary>
    private static IEnumerable<Type> GetAllTenantOwnedEntityTypes()
    {
        return typeof(IAppDbContext)
            .GetProperties()
            .Where(p => p.PropertyType.IsGenericType &&
                        p.PropertyType.GetGenericTypeDefinition() == typeof(DbSet<>))
            .Select(p => p.PropertyType.GetGenericArguments()[0]);
    }

    private static bool HasIndex(IEntityType? entityType, params string[] propertyNames)
    {
        entityType.Should().NotBeNull();

        return entityType!
            .GetIndexes()
            .Any(index => index.Properties.Select(property => property.Name).SequenceEqual(propertyNames));
    }

    private static OrderProcessingSystemDbContext CreateDbContext(ITenantProvider? tenantProvider = null)
    {
        var options = new DbContextOptionsBuilder<OrderProcessingSystemDbContext>()
            .UseSqlServer("Server=(localdb)\\mssqllocaldb;Database=SchemaTests_DoNotConnect;Trusted_Connection=True;")
            .Options;

        return tenantProvider is null
            ? new OrderProcessingSystemDbContext(options)
            : new OrderProcessingSystemDbContext(options, tenantProvider);
    }

    private sealed class TestTenantProvider : ITenantProvider
    {
        public TestTenantProvider(int tenantId, string tenantCode)
        {
            TenantId = tenantId;
            TenantCode = tenantCode;
        }

        public bool HasTenantContext => true;

        public int TenantId { get; }

        public string TenantCode { get; }

        public string TenantExternalId => $"ext-{TenantCode}";

        public string? ConnectionString => null;

        public bool IsSharedPool => true;
    }
}