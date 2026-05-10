using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class SeedDedicatedTenantC : Migration
    {
        // TenantC is a Dedicated-tier tenant. Its ConnectionString is NULL at seed time
        // because dedicated DB provisioning is an environment-specific ops step. Until
        // ConnectionString is set, EntityFrameworkTenantResolver returns null (fail-loud)
        // and TenantMiddleware rejects requests with HTTP 400.

        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
IF NOT EXISTS (SELECT 1 FROM [dbo].[Tenants] WHERE [Code] = 'TenantC')
BEGIN
    INSERT INTO [dbo].[Tenants]
        ([ExternalId], [Code], [Name], [Status], [TenantTier], [ConnectionString], [CreatedBy], [CreatedDate])
    VALUES
        ('tnt_ext_tenant_c', 'TenantC', 'Tenant C (Dedicated)', 'Active', 'Dedicated', NULL, 1, GETUTCDATE())
END");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
DELETE FROM [dbo].[Tenants] WHERE [Code] = 'TenantC' AND [ExternalId] = 'tnt_ext_tenant_c'");
        }
    }
}
