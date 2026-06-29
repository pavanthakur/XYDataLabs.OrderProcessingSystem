using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Abstractions;

namespace XYDataLabs.OrderProcessingSystem.Inventory.Infrastructure.Module;

public sealed class InventoryModuleMigrator(OrderProcessingSystemDbContext dbContext) : IModuleDatabaseMigrator
{
    public Task MigrateAsync(CancellationToken cancellationToken = default)
        => dbContext.Database.MigrateAsync(cancellationToken);
}
