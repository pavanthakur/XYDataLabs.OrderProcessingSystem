using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class SeedBaselineTenants : Migration
    {
        // These are the two tenants that DbInitializer.GetStartupSeedTenants() requires at
        // every app startup. Previously only DbInitializer inserted them (runtime-only); now
        // they live in the migration so a fresh DB bootstrapped via pipeline is ready before
        // the API starts. IF NOT EXISTS guards make this safe to re-apply against existing DBs
        // that already have these rows (e.g. existing Azure dev environment).

        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
IF NOT EXISTS (SELECT 1 FROM [dbo].[Tenants] WHERE [Code] = 'TenantA')
BEGIN
    INSERT INTO [dbo].[Tenants]
        ([ExternalId], [Code], [Name], [Status], [TenantTier], [ConnectionString], [CreatedBy], [CreatedDate])
    VALUES
        ('tnt_ext_tenant_a', 'TenantA', 'Tenant A', 'Active', 'SharedPool', NULL, 1, GETUTCDATE())
END");

            migrationBuilder.Sql(@"
IF NOT EXISTS (SELECT 1 FROM [dbo].[Tenants] WHERE [Code] = 'TenantB')
BEGIN
    INSERT INTO [dbo].[Tenants]
        ([ExternalId], [Code], [Name], [Status], [TenantTier], [ConnectionString], [CreatedBy], [CreatedDate])
    VALUES
        ('tnt_ext_tenant_b', 'TenantB', 'Tenant B', 'Active', 'SharedPool', NULL, 1, GETUTCDATE())
END");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            // Only remove rows that match exactly what Up() inserted — does not touch tenant
            // rows that were modified after initial creation (e.g. name or status changes).
            migrationBuilder.Sql(@"
DELETE FROM [dbo].[Tenants] WHERE [Code] = 'TenantA' AND [ExternalId] = 'tnt_ext_tenant_a'");

            migrationBuilder.Sql(@"
DELETE FROM [dbo].[Tenants] WHERE [Code] = 'TenantB' AND [ExternalId] = 'tnt_ext_tenant_b'");
        }
    }
}
