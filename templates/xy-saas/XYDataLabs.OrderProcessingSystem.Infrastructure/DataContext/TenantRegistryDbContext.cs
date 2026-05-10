using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;

/// <summary>
/// Lightweight DbContext for tenant resolution. Uses the shared/admin connection string.
/// Has no ITenantProvider dependency and no query filters — breaks the circular dependency
/// where the business DbContext needs tenant context but tenant resolution needs the DB.
/// </summary>
public sealed class TenantRegistryDbContext : DbContext
{
    public TenantRegistryDbContext(DbContextOptions<TenantRegistryDbContext> options)
        : base(options)
    {
    }

    public DbSet<Tenant> Tenants { get; set; }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.Entity<Tenant>()
            .HasIndex(t => t.ExternalId)
            .IsUnique();

        modelBuilder.Entity<Tenant>()
            .HasIndex(t => t.Code)
            .IsUnique();
    }
}
