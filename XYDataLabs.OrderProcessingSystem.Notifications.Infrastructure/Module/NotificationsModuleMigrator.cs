using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Abstractions;

namespace XYDataLabs.OrderProcessingSystem.Notifications.Infrastructure.Module;

public sealed class NotificationsModuleMigrator(OrderProcessingSystemDbContext dbContext) : IModuleDatabaseMigrator
{
    public Task MigrateAsync(CancellationToken cancellationToken = default)
        => dbContext.Database.MigrateAsync(cancellationToken);
}
