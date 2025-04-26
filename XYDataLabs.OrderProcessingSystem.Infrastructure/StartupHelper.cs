using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.Infrastructure.SeedData;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure
{
    public static class StartupHelper
    {
        public static void InjectInfrastructureDependencies(this IHostApplicationBuilder builder)
        {
            builder.Services.AddDbContext<OrderProcessingSystemDbContext>(options =>
            {
                options.UseSqlServer(builder.Configuration.GetConnectionString("OrderProcessingSystemDbConnection"));
            });

            //Note : Comment this when running Add-Migration Command from Package Manager Console. Then uncomment after migration file is generated
            // Auto migration setup
            //Step1: Comment below code
            //Step2: set start project as XYDataLabs.OrderProcessingSystem.Infrastructure
            //Step2: Add-Migration AddOpenpayCustomerIdColumnToCustomer
            //Step3: set start project as XYDataLabs.OrderProcessingSystem.Application
            //Step4: Update-Database
            //Step5: Uncomment below code
            using (var serviceProvider = builder.Services.BuildServiceProvider())
            {
                var dbContext = serviceProvider.GetRequiredService<OrderProcessingSystemDbContext>();
                dbContext.Database.Migrate();
                DbInitializer.Initialize(dbContext);
            }
        }
    }
}
