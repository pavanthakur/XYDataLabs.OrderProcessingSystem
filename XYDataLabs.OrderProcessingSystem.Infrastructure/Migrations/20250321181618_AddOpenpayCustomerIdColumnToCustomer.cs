using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddOpenpayCustomerIdColumnToCustomer : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "OpenpayCustomerId",
                table: "Customers",
                type: "nvarchar(max)",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "OpenpayCustomerId",
                table: "Customers");
        }
    }
}
