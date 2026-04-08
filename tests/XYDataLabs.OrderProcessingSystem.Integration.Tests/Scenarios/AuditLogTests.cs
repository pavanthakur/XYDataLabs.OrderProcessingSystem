using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

[Collection("SqlServer")]
[Trait("Category", "Integration")]
public sealed class AuditLogTests : IAsyncLifetime
{
    private readonly SqlServerFixture _fixture;
    private IntegrationTestWebAppFactory _factory = null!;

    public AuditLogTests(SqlServerFixture fixture)
    {
        _fixture = fixture;
    }

    public Task InitializeAsync()
    {
        _factory = new IntegrationTestWebAppFactory(_fixture.ConnectionString);
        _ = _factory.CreateClient();
        return Task.CompletedTask;
    }

    public async Task DisposeAsync()
    {
        await _factory.DisposeAsync();
    }

    [Fact]
    public async Task TenantScoped_DbContext_Should_Create_Update_Delete_Audit_Entries()
    {
        var tenant = await IntegrationTestData.CreateTenantAsync(_factory);

        var entityId = await _factory.ExecuteTenantDbContextAsync(
            tenant.ToTenantContext(),
            async dbContext =>
            {
                var customer = new Customer
                {
                    Name = "Audit Customer",
                    Email = $"audit-{Guid.NewGuid():N}@test.com",
                    TenantId = tenant.TenantId,
                    CreatedBy = 1,
                    CreatedDate = DateTime.UtcNow
                };

                dbContext.Customers.Add(customer);
                await dbContext.SaveChangesAsync();

                customer.Name = "Audit Customer Updated";
                customer.UpdatedBy = 2;
                customer.UpdatedDate = DateTime.UtcNow;
                await dbContext.SaveChangesAsync();

                dbContext.Customers.Remove(customer);
                await dbContext.SaveChangesAsync();

                return $"CustomerId={customer.CustomerId}";
            });

        var auditLogs = await _factory.ExecuteTenantDbContextAsync(
            tenant.ToTenantContext(),
            dbContext => dbContext.AuditLogs
                .Where(auditLog => auditLog.EntityName == "Customer" && auditLog.EntityId == entityId)
                .OrderBy(auditLog => auditLog.Id)
                .ToListAsync());

        auditLogs.Should().HaveCount(3);
        auditLogs.Select(item => item.Operation).Should().ContainInOrder("Created", "Updated", "Deleted");
        auditLogs[0].NewValues.Should().Contain("Audit Customer");
        auditLogs[1].OldValues.Should().Contain("Audit Customer");
        auditLogs[1].NewValues.Should().Contain("Audit Customer Updated");
        auditLogs[2].OldValues.Should().Contain("Audit Customer Updated");
    }

    [Fact]
    public async Task AuditLogs_Should_Be_Tenant_Isolated_In_SharedPool()
    {
        var tenantA = await IntegrationTestData.CreateTenantAsync(_factory);
        var tenantB = await IntegrationTestData.CreateTenantAsync(_factory);

        var tenantAEntityId = await CreateCustomerForTenantAsync(tenantA, "audit-tenant-a");
        var tenantBEntityId = await CreateCustomerForTenantAsync(tenantB, "audit-tenant-b");

        var tenantAAuditIds = await _factory.ExecuteTenantDbContextAsync(
            tenantA.ToTenantContext(),
            dbContext => dbContext.AuditLogs
                .Where(auditLog => auditLog.EntityName == "Customer")
                .Select(auditLog => auditLog.EntityId)
                .ToListAsync());

        var tenantBAuditIds = await _factory.ExecuteTenantDbContextAsync(
            tenantB.ToTenantContext(),
            dbContext => dbContext.AuditLogs
                .Where(auditLog => auditLog.EntityName == "Customer")
                .Select(auditLog => auditLog.EntityId)
                .ToListAsync());

        tenantAAuditIds.Should().Contain(tenantAEntityId);
        tenantAAuditIds.Should().NotContain(tenantBEntityId);
        tenantBAuditIds.Should().Contain(tenantBEntityId);
        tenantBAuditIds.Should().NotContain(tenantAEntityId);
    }

    private async Task<string> CreateCustomerForTenantAsync(TestTenantContext tenant, string marker)
    {
        return await _factory.ExecuteTenantDbContextAsync(
            tenant.ToTenantContext(),
            async dbContext =>
            {
                var customer = new Customer
                {
                    Name = $"Customer {marker}",
                    Email = $"{marker}-{Guid.NewGuid():N}@test.com",
                    TenantId = tenant.TenantId,
                    CreatedBy = 1,
                    CreatedDate = DateTime.UtcNow
                };

                dbContext.Customers.Add(customer);
                await dbContext.SaveChangesAsync();
                return $"CustomerId={customer.CustomerId}";
            });
    }
}