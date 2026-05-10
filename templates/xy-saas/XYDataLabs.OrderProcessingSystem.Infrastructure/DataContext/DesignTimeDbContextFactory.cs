using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext
{
    /// <summary>
    /// Design-time factory for EF Core tooling (dotnet ef migrations add/remove/script).
    /// Decouples migration generation from full Program.cs startup — uses a fixed localdb
    /// connection that will never actually be connected to during design-time operations.
    /// </summary>
    public class DesignTimeDbContextFactory : IDesignTimeDbContextFactory<OrderProcessingSystemDbContext>
    {
        public OrderProcessingSystemDbContext CreateDbContext(string[] args)
        {
            var optionsBuilder = new DbContextOptionsBuilder<OrderProcessingSystemDbContext>();
            optionsBuilder.UseSqlServer(
                "Server=(localdb)\\mssqllocaldb;Database=OrderProcessingSystem_DesignTime;Trusted_Connection=True;");

            return new OrderProcessingSystemDbContext(optionsBuilder.Options);
        }
    }
}
