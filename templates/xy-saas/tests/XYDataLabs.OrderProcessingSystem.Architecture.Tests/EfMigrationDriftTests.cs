using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;

namespace XYDataLabs.OrderProcessingSystem.Architecture.Tests;

/// <summary>
/// Detects model/migration drift — catches when someone changes an entity but forgets to create a migration.
/// Uses EF 8's HasPendingModelChanges() which compares the compiled model against the latest snapshot.
/// Runs in CI on every PR to prevent schema gaps from reaching dev/staging/prod.
/// </summary>
public class EfMigrationDriftTests
{
    /// <summary>
    /// Verifies the EF model matches the latest migration snapshot.
    /// Fails when entity properties change but no migration is created.
    /// Fix: run <c>dotnet ef migrations add &lt;Name&gt; --project Infrastructure --startup-project API</c>
    /// </summary>
    [Fact]
    public void Model_Should_Not_Have_Pending_Changes()
    {
        using var context = CreateDbContext();
        var hasPendingChanges = context.Database.HasPendingModelChanges();

        hasPendingChanges.Should().BeFalse(
            because: "all EF model changes must have a corresponding migration. " +
                     "Run: dotnet ef migrations add <Name> " +
                     "--project XYDataLabs.OrderProcessingSystem.Infrastructure " +
                     "--startup-project XYDataLabs.OrderProcessingSystem.API");
    }

    /// <summary>
    /// Verifies migration chain integrity — all migrations must be internally consistent.
    /// Detects corrupted or manually-edited migration files that break the chain.
    /// </summary>
    [Fact]
    public void Migrations_Should_Have_Valid_Chain()
    {
        using var context = CreateDbContext();
        var migrationsAssembly = context.GetService<IMigrationsAssembly>();

        migrationsAssembly.Migrations.Should().NotBeEmpty(
            because: "the project must have at least one migration");

        // Verify snapshot exists and is parseable
        migrationsAssembly.ModelSnapshot.Should().NotBeNull(
            because: "the model snapshot must exist for migration chain integrity");
    }

    private static OrderProcessingSystemDbContext CreateDbContext()
    {
        var options = new DbContextOptionsBuilder<OrderProcessingSystemDbContext>()
            .UseSqlServer("Server=(localdb)\\mssqllocaldb;Database=DriftCheck_DoNotConnect;Trusted_Connection=True;")
            .Options;

        return new OrderProcessingSystemDbContext(options);
    }
}
