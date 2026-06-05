using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class Fixup_RazorpayCheckoutMode_AllTenants : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // Set Use3DSecure = false for every Razorpay PaymentProvider row across all tenants.
            // Razorpay S2S JSON v2 (Use3DSecure = true / direct_card_form) requires the merchant account
            // to have S2S activation enabled — this is NOT enabled on our sandbox account and requires a
            // Razorpay support ticket. The provider_checkout path (Use3DSecure = false) uses the hosted
            // Razorpay Checkout JS popup which handles 3DS internally (SAQ A, no PCI scope) and works
            // without any account-level activation.
            // This migration is idempotent — running it multiple times has no side effect.
            // Applies to both the shared-pool DB and all dedicated tenant DBs (EF Core runs all
            // pending migrations on each DB at startup via DbInitializer.InitializeDedicatedTenants).
            migrationBuilder.Sql(@"
UPDATE [dbo].[PaymentProviders]
SET Use3DSecure = 0
WHERE ProviderType = 'Razorpay'");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            // Restore TenantA to false (was already fixed in SeedTenantARazorpay3DSDisabled).
            // Restore TenantB and TenantC to true (the previous default — not actually desirable,
            // but this correctly reverses the Up() change for rollback purposes).
            migrationBuilder.Sql(@"
UPDATE pp
SET pp.Use3DSecure = 1
FROM [dbo].[PaymentProviders] pp
INNER JOIN [dbo].[Tenants] t ON t.Id = pp.TenantId
WHERE t.Code IN ('TenantB', 'TenantC') AND pp.ProviderType = 'Razorpay'");
        }
    }
}
