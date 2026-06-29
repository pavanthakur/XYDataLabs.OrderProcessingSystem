using Microsoft.Extensions.Logging;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Abstractions;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Migrations;

/// <summary>
/// Executes module database migrators sequentially during startup.
/// </summary>
public sealed class ModuleDatabaseMigratorRunner(
    IEnumerable<IModuleDatabaseMigrator> migrators,
    ILogger<ModuleDatabaseMigratorRunner> logger)
{
    public async Task RunAsync(CancellationToken cancellationToken = default)
    {
        foreach (var migrator in migrators)
        {
            logger.LogInformation("Running module database migrator {Migrator}", migrator.GetType().Name);
            await migrator.MigrateAsync(cancellationToken);
        }
    }
}
