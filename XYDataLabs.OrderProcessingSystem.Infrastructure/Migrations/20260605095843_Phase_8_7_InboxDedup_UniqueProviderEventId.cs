using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class Phase_8_7_InboxDedup_UniqueProviderEventId : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateIndex(
                name: "IX_InboxMessages_TenantId_ProviderEventId",
                table: "InboxMessages",
                columns: new[] { "TenantId", "ProviderEventId" },
                unique: true,
                filter: "[ProviderEventId] IS NOT NULL AND [ProviderEventId] <> ''");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_InboxMessages_TenantId_ProviderEventId",
                table: "InboxMessages");
        }
    }
}
