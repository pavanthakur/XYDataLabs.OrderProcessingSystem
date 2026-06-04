using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddTenantPaymentProviderCode : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "PaymentProviderCode",
                table: "Tenants",
                type: "nvarchar(50)",
                maxLength: 50,
                nullable: true);

            // Seed canonical provider assignments for the three known tenants.
            // This is the authoritative registration that replaces DbInitializer.SeedDefaultProvider (Phase 8.6).
            // TenantA and TenantB share the pool DB; TenantC is dedicated.
            // All three rows must already exist (inserted by earlier migrations).
            migrationBuilder.Sql(@"
UPDATE [dbo].[Tenants] SET [PaymentProviderCode] = 'Razorpay' WHERE [Code] = 'TenantA' AND [PaymentProviderCode] IS NULL");

            migrationBuilder.Sql(@"
UPDATE [dbo].[Tenants] SET [PaymentProviderCode] = 'Razorpay' WHERE [Code] = 'TenantB' AND [PaymentProviderCode] IS NULL");

            migrationBuilder.Sql(@"
UPDATE [dbo].[Tenants] SET [PaymentProviderCode] = 'OpenPay'  WHERE [Code] = 'TenantC' AND [PaymentProviderCode] IS NULL");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "PaymentProviderCode",
                table: "Tenants");
        }
    }
}
