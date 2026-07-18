using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class Phase10SeedPaymentProviderBaseline : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // Phase 10 split services do not run the monolith startup seeder.
            // Keep the payment-provider baseline in migrations so fresh Azure SQL,
            // TenantC dedicated SQL, and local Docker SQL all share the same contract.
            migrationBuilder.Sql(@"
DECLARE @IsTenantCDedicatedDb bit =
    CASE WHEN DB_NAME() LIKE '%TenantC%' THEN 1 ELSE 0 END;

DECLARE @ProviderSeed TABLE
(
    TenantCode nvarchar(50) NOT NULL,
    ProviderName nvarchar(100) NOT NULL,
    ApiUrl nvarchar(255) NOT NULL,
    ProviderType nvarchar(50) NOT NULL,
    Use3DSecure bit NOT NULL,
    IsActive bit NOT NULL
);

INSERT INTO @ProviderSeed
    (TenantCode, ProviderName, ApiUrl, ProviderType, Use3DSecure, IsActive)
VALUES
    ('TenantA', 'Razorpay', 'https://api.razorpay.com/v1', 'Razorpay', 0, 0),
    ('TenantB', 'Razorpay', 'https://api.razorpay.com/v1', 'Razorpay', 0, 0),
    ('TenantA', 'OpenPay', 'https://sandbox-api.openpay.mx/v1', 'OpenPay', 1, 0),
    ('TenantB', 'OpenPay', 'https://sandbox-api.openpay.mx/v1', 'OpenPay', 1, 0),
    ('TenantC', 'OpenPay', 'https://sandbox-api.openpay.mx/v1', 'OpenPay', 1, 0),
    ('TenantC', 'Razorpay', 'https://api.razorpay.com/v1', 'Razorpay', 0, 0);

INSERT INTO [payments].[PaymentProviders]
    ([Name],
     [APIUrl],
     [IsProduction],
     [IsActive],
     [ProviderType],
     [MerchantId],
     [PublicKey],
     [PrivateKeyConfigurationKey],
     [Use3DSecure],
     [TenantId],
     [CreatedBy],
     [CreatedDate])
SELECT
    seed.ProviderName,
    seed.ApiUrl,
    0,
    seed.IsActive,
    seed.ProviderType,
    NULL,
    NULL,
    CONCAT('PaymentProviders:', seed.TenantCode, ':', seed.ProviderType, ':PrivateKey'),
    seed.Use3DSecure,
    tenant.Id,
    1,
    GETUTCDATE()
FROM @ProviderSeed seed
INNER JOIN [dbo].[Tenants] tenant ON tenant.Code = seed.TenantCode
WHERE
    (
        (@IsTenantCDedicatedDb = 0 AND seed.TenantCode IN ('TenantA', 'TenantB'))
        OR
        (@IsTenantCDedicatedDb = 1 AND seed.TenantCode = 'TenantC')
    )
    AND NOT EXISTS
    (
        SELECT 1
        FROM [payments].[PaymentProviders] existing
        WHERE existing.TenantId = tenant.Id
          AND existing.ProviderType = seed.ProviderType
    );
");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
DELETE provider
FROM [payments].[PaymentProviders] provider
INNER JOIN [dbo].[Tenants] tenant ON tenant.Id = provider.TenantId
WHERE tenant.Code IN ('TenantA', 'TenantB', 'TenantC')
  AND provider.ProviderType IN ('OpenPay', 'Razorpay')
  AND provider.MerchantId IS NULL
  AND provider.PublicKey IS NULL
  AND provider.CreatedBy = 1;
");

        }
    }
}
