using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;
using Microsoft.Extensions.Configuration;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext
{
    /// <summary>
    /// Design-time factory for EF Core tooling (dotnet ef migrations add/remove/script).
    /// It prefers explicit runtime overrides so scripted local bootstrap can target Docker SQL,
    /// while retaining a localdb fallback for ordinary migration authoring.
    /// </summary>
    public class DesignTimeDbContextFactory : IDesignTimeDbContextFactory<OrderProcessingSystemDbContext>
    {
        public OrderProcessingSystemDbContext CreateDbContext(string[] args)
        {
            var configuration = new ConfigurationBuilder()
                .AddEnvironmentVariables()
                .Build();

            var connectionString =
                configuration["ConnectionStrings__OrderProcessingSystemDbConnection"] ??
                configuration["ConnectionStrings:OrderProcessingSystemDbConnection"] ??
                "Server=(localdb)\\mssqllocaldb;Database=OrderProcessingSystem_DesignTime;Trusted_Connection=True;";

            var optionsBuilder = new DbContextOptionsBuilder<OrderProcessingSystemDbContext>();
            optionsBuilder.UseSqlServer(connectionString);

            return new OrderProcessingSystemDbContext(optionsBuilder.Options);
        }
    }
}
