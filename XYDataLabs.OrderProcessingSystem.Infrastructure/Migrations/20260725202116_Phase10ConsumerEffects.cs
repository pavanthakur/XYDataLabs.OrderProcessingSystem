using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class Phase10ConsumerEffects : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<Guid>(
                name: "OrderReferenceId",
                schema: "orders",
                table: "Orders",
                type: "uniqueidentifier",
                nullable: false,
                defaultValueSql: "NEWSEQUENTIALID()");

            migrationBuilder.CreateTable(
                name: "ConsumerInboxMessages",
                schema: "operations",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    TenantId = table.Column<int>(type: "int", nullable: false),
                    ConsumerName = table.Column<string>(type: "nvarchar(128)", maxLength: 128, nullable: false),
                    MessageId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    EventType = table.Column<string>(type: "nvarchar(256)", maxLength: 256, nullable: false),
                    CorrelationId = table.Column<string>(type: "nvarchar(128)", maxLength: 128, nullable: true),
                    ReceivedUtc = table.Column<DateTime>(type: "datetime2", nullable: false),
                    ProcessedUtc = table.Column<DateTime>(type: "datetime2", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ConsumerInboxMessages", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "InventoryReservations",
                schema: "inventory",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    TenantId = table.Column<int>(type: "int", nullable: false),
                    OrderReferenceId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    ProductCount = table.Column<int>(type: "int", nullable: false),
                    ReservedUtc = table.Column<DateTime>(type: "datetime2", nullable: false),
                    CorrelationId = table.Column<string>(type: "nvarchar(128)", maxLength: 128, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_InventoryReservations", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "NotificationDeliveries",
                schema: "notifications",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    TenantId = table.Column<int>(type: "int", nullable: false),
                    OrderReferenceId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    NotificationType = table.Column<string>(type: "nvarchar(128)", maxLength: 128, nullable: false),
                    Sink = table.Column<string>(type: "nvarchar(128)", maxLength: 128, nullable: false),
                    AcceptedUtc = table.Column<DateTime>(type: "datetime2", nullable: false),
                    CorrelationId = table.Column<string>(type: "nvarchar(128)", maxLength: 128, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_NotificationDeliveries", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_Orders_TenantId_OrderReferenceId",
                schema: "orders",
                table: "Orders",
                columns: new[] { "TenantId", "OrderReferenceId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_ConsumerInboxMessages_TenantId_ConsumerName_MessageId",
                schema: "operations",
                table: "ConsumerInboxMessages",
                columns: new[] { "TenantId", "ConsumerName", "MessageId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_InventoryReservations_TenantId_OrderReferenceId",
                schema: "inventory",
                table: "InventoryReservations",
                columns: new[] { "TenantId", "OrderReferenceId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_NotificationDeliveries_TenantId_OrderReferenceId_NotificationType",
                schema: "notifications",
                table: "NotificationDeliveries",
                columns: new[] { "TenantId", "OrderReferenceId", "NotificationType" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "ConsumerInboxMessages",
                schema: "operations");

            migrationBuilder.DropTable(
                name: "InventoryReservations",
                schema: "inventory");

            migrationBuilder.DropTable(
                name: "NotificationDeliveries",
                schema: "notifications");

            migrationBuilder.DropIndex(
                name: "IX_Orders_TenantId_OrderReferenceId",
                schema: "orders",
                table: "Orders");

            migrationBuilder.DropColumn(
                name: "OrderReferenceId",
                schema: "orders",
                table: "Orders");
        }
    }
}
