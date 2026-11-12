using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.Configuration;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.Infrastructure.SeedData;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

namespace XYDataLabs.OrderProcessingSystem.Application.Tests;

public sealed class Phase10BootstrapPreservationTests
{
    [Fact]
    public void MissingOnlyInitializationPreservesExistingTenantAndProviderStateWithoutSql()
    {
        var options = new DbContextOptionsBuilder<OrderProcessingSystemDbContext>()
            .UseInMemoryDatabase($"phase10-seed-{Guid.NewGuid():N}")
            .ConfigureWarnings(warnings => warnings.Ignore(InMemoryEventId.TransactionIgnoredWarning))
            .Options;
        using var context = new OrderProcessingSystemDbContext(options, new NoTenantProvider());
        var tenants = new[]
        {
            new Tenant { ExternalId = "external-a", Code = "TenantA", Name = "Operator A", Status = "Active", TenantTier = "SharedPool", PaymentProviderCode = "Razorpay" },
            new Tenant { ExternalId = "external-b", Code = "TenantB", Name = "Operator B", Status = "Active", TenantTier = "SharedPool", PaymentProviderCode = "Razorpay" },
            new Tenant { ExternalId = "external-extra", Code = "Clinic-West-47", Name = "Operator Clinic", Status = "Active", TenantTier = "SharedPool", PaymentProviderCode = "OpenPay" },
            new Tenant { ExternalId = "external-inactive", Code = "Dormant-West", Name = "Dormant Tenant", Status = "Inactive", TenantTier = "SharedPool", PaymentProviderCode = "OpenPay" },
        };
        context.Tenants.AddRange(tenants);
        context.SaveChanges();

        foreach (var tenant in tenants)
        {
            foreach (var (provider, active, threeDs) in new[] { ("Razorpay", tenant.PaymentProviderCode == "Razorpay", true), ("OpenPay", tenant.PaymentProviderCode == "OpenPay", false) })
            {
                context.PaymentProviders.Add(new PaymentProvider
                {
                    Name = $"Operator {provider}",
                    APIUrl = $"https://operator.invalid/{provider}",
                    ProviderType = provider,
                    IsActive = active,
                    IsProduction = false,
                    Use3DSecure = threeDs,
                    MerchantId = $"merchant-{tenant.Code}-{provider}",
                    PublicKey = $"public-{tenant.Code}-{provider}",
                    PrivateKeyConfigurationKey = $"operator:{tenant.Code}:{provider}",
                    TenantId = tenant.Id,
                    CreatedBy = 9,
                    CreatedDate = new DateTime(2025, 1, 1, 0, 0, 0, DateTimeKind.Utc),
                });
            }
        }
        context.SaveChanges();

        var tenantSnapshots = context.Tenants.AsNoTracking().ToDictionary(tenant => tenant.Code, tenant => new
        {
            tenant.Id, tenant.ExternalId, tenant.Name, tenant.Status, tenant.TenantTier, tenant.PaymentProviderCode,
        });
        var providerSnapshots = context.PaymentProviders.AsNoTracking().ToDictionary(
            provider => $"{provider.TenantId}|{provider.ProviderType}",
            provider => new
            {
                provider.Id, provider.Name, provider.APIUrl, provider.IsActive, provider.IsProduction,
                provider.Use3DSecure, provider.MerchantId, provider.PublicKey, provider.PrivateKeyConfigurationKey,
            });
        var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["Phase10:SeedAllActiveTenants"] = "true",
            ["Phase10:PreserveExistingSeedData"] = "true",
            ["OpenPay:MerchantId"] = "replacement-openpay-merchant",
            ["OpenPay:PublicKey"] = "replacement-openpay-public",
            ["Razorpay:MerchantId"] = "replacement-razorpay-merchant",
        }).Build();

        DbInitializer.InitializeSharedPool(context, config, applyMigrations: false, seedOrders: false);
        DbInitializer.InitializeSharedPool(context, config, applyMigrations: false, seedOrders: false);

        var tenantsAfter = context.Tenants.AsNoTracking().ToDictionary(tenant => tenant.Code);
        tenantsAfter.Keys.Should().BeEquivalentTo(tenantSnapshots.Keys);
        foreach (var (code, snapshot) in tenantSnapshots)
        {
            var actual = tenantsAfter[code];
            actual.Id.Should().Be(snapshot.Id);
            actual.ExternalId.Should().Be(snapshot.ExternalId);
            actual.Name.Should().Be(snapshot.Name);
            actual.Status.Should().Be(snapshot.Status);
            actual.TenantTier.Should().Be(snapshot.TenantTier);
            actual.PaymentProviderCode.Should().Be(snapshot.PaymentProviderCode);
        }

        var providersAfter = context.PaymentProviders.AsNoTracking().ToDictionary(
            provider => $"{provider.TenantId}|{provider.ProviderType}");
        providersAfter.Keys.Should().BeEquivalentTo(providerSnapshots.Keys);
        foreach (var (key, snapshot) in providerSnapshots)
        {
            var actual = providersAfter[key];
            actual.Id.Should().Be(snapshot.Id);
            actual.Name.Should().Be(snapshot.Name);
            actual.APIUrl.Should().Be(snapshot.APIUrl);
            actual.IsActive.Should().Be(snapshot.IsActive);
            actual.IsProduction.Should().Be(snapshot.IsProduction);
            actual.Use3DSecure.Should().Be(snapshot.Use3DSecure);
            actual.MerchantId.Should().Be(snapshot.MerchantId);
            actual.PublicKey.Should().Be(snapshot.PublicKey);
            actual.PrivateKeyConfigurationKey.Should().Be(snapshot.PrivateKeyConfigurationKey);
        }
    }

    private sealed class NoTenantProvider : ITenantProvider
    {
        public bool HasTenantContext => false;
        public int TenantId => 0;
        public string TenantCode => string.Empty;
        public string TenantExternalId => string.Empty;
        public string? ConnectionString => null;
        public bool IsSharedPool => true;
    }
}
