using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;

namespace XYDataLabs.OrderProcessingSystem.Architecture.Tests;

public sealed class ModuleSchemaMappingTests
{
    [Fact]
    public void EfModel_Should_Map_Module_Tables_To_Their_Owned_Schemas()
    {
        var options = new DbContextOptionsBuilder<OrderProcessingSystemDbContext>()
            .UseSqlServer("Server=(localdb)\\mssqllocaldb;Database=Phase9SchemaProof;Trusted_Connection=True;TrustServerCertificate=True")
            .Options;

        using var context = new OrderProcessingSystemDbContext(options);

        context.Model.FindEntityType(typeof(Order))!.GetSchema().Should().Be("orders");
        context.Model.FindEntityType(typeof(Customer))!.GetSchema().Should().Be("orders");
        context.Model.FindEntityType(typeof(Product))!.GetSchema().Should().Be("inventory");
    }
}
