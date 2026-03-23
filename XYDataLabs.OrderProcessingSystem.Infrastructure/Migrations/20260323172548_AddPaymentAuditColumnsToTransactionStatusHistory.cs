using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddPaymentAuditColumnsToTransactionStatusHistory : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "IsThreeDSecureEnabled",
                table: "TransactionStatusHistories",
                type: "bit",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<string>(
                name: "TransactionReferenceId",
                table: "TransactionStatusHistories",
                type: "nvarchar(64)",
                maxLength: 64,
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_TransactionStatusHistories_TenantId_TransactionReferenceId",
                table: "TransactionStatusHistories",
                columns: new[] { "TenantId", "TransactionReferenceId" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_TransactionStatusHistories_TenantId_TransactionReferenceId",
                table: "TransactionStatusHistories");

            migrationBuilder.DropColumn(
                name: "IsThreeDSecureEnabled",
                table: "TransactionStatusHistories");

            migrationBuilder.DropColumn(
                name: "TransactionReferenceId",
                table: "TransactionStatusHistories");
        }
    }
}
