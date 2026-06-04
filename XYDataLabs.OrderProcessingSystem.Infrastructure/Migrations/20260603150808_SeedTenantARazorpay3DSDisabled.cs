using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class SeedTenantARazorpay3DSDisabled : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
UPDATE pp
SET pp.Use3DSecure = 0
FROM [dbo].[PaymentProviders] pp
INNER JOIN [dbo].[Tenants] t ON t.Id = pp.TenantId
WHERE t.Code = 'TenantA' AND pp.ProviderType = 'Razorpay'");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
UPDATE pp
SET pp.Use3DSecure = 1
FROM [dbo].[PaymentProviders] pp
INNER JOIN [dbo].[Tenants] t ON t.Id = pp.TenantId
WHERE t.Code = 'TenantA' AND pp.ProviderType = 'Razorpay'");
        }
    }
}
