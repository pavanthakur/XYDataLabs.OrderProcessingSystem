using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Migrations;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Abstractions;

namespace XYDataLabs.OrderProcessingSystem.Architecture.Tests;

public sealed class ModuleSchemaAndMigratorTests
{
    [Fact]
    public void ModuleSchemaNames_Should_Define_All_Phase9_Module_Schemas()
    {
        ModuleSchemaNames.Orders.Should().Be("orders");
        ModuleSchemaNames.Inventory.Should().Be("inventory");
        ModuleSchemaNames.Notifications.Should().Be("notifications");
        ModuleSchemaNames.Payments.Should().Be("payments");
    }

    [Fact]
    public async Task ModuleDatabaseMigratorRunner_Should_Run_All_Registered_Migrators_In_Order()
    {
        var calls = new List<string>();
        var services = new ServiceCollection();
        services.AddSingleton<IModuleDatabaseMigrator>(_ => new RecordingMigrator("orders", calls));
        services.AddSingleton<IModuleDatabaseMigrator>(_ => new RecordingMigrator("inventory", calls));
        services.AddSingleton<IModuleDatabaseMigrator>(_ => new RecordingMigrator("notifications", calls));
        services.AddSingleton<IModuleDatabaseMigrator>(_ => new RecordingMigrator("payments", calls));

        using var provider = services.BuildServiceProvider();

        var runner = new ModuleDatabaseMigratorRunner(
            provider.GetRequiredService<IEnumerable<IModuleDatabaseMigrator>>(),
            NullLogger<ModuleDatabaseMigratorRunner>.Instance);

        await runner.RunAsync();

        calls.Should().Equal("orders", "inventory", "notifications", "payments");
    }

    private sealed class RecordingMigrator(string name, IList<string> calls) : IModuleDatabaseMigrator
    {
        public Task MigrateAsync(CancellationToken cancellationToken = default)
        {
            calls.Add(name);
            return Task.CompletedTask;
        }
    }
}
