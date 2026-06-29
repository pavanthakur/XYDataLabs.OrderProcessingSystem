namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Abstractions;

/// <summary>
/// Represents a module-owned database migrator that can be executed during startup.
/// </summary>
public interface IModuleDatabaseMigrator
{
    /// <summary>
    /// Runs the migrations required for a single module.
    /// </summary>
    Task MigrateAsync(CancellationToken cancellationToken = default);
}
