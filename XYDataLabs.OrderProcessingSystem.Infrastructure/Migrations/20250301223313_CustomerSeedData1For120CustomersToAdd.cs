using Bogus;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class CustomerSeedData3For120CustomersToAdd : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // Generate the customer data
            var faker = new Faker<Customer>()
                .RuleFor(c => c.Name, f => f.Name.FullName())
                .RuleFor(c => c.Email, f => f.Internet.Email());

            var customers = faker.Generate(120);

            // Insert the data using SQL
            foreach (var customer in customers)
            {
                migrationBuilder.InsertData(
                    table: "Customers",
                    columns: new[] { "Name", "Email" },
                    values: new object[] { customer.Name, customer.Email }
                );
            }
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            // Optional: Remove the seeded data if needed
            migrationBuilder.Sql("DELETE FROM Customers WHERE CustomerId <= 125");
        }
    }
}
