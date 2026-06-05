using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class Phase_8_7_WebhookInbox : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<byte[]>(
                name: "RowVersion",
                table: "PaymentAttempts",
                type: "rowversion",
                rowVersion: true,
                nullable: false,
                defaultValue: new byte[0]);

            migrationBuilder.AlterColumn<DateTime>(
                name: "ProcessedUtc",
                table: "InboxMessages",
                type: "datetime2",
                nullable: true,
                oldClrType: typeof(DateTime),
                oldType: "datetime2");

            migrationBuilder.AddColumn<string>(
                name: "LastError",
                table: "InboxMessages",
                type: "nvarchar(1024)",
                maxLength: 1024,
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "LockExpiry",
                table: "InboxMessages",
                type: "datetime2",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Payload",
                table: "InboxMessages",
                type: "nvarchar(max)",
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<int>(
                name: "ProcessingAttempts",
                table: "InboxMessages",
                type: "int",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<string>(
                name: "ProviderEventId",
                table: "InboxMessages",
                type: "nvarchar(256)",
                maxLength: 256,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<int>(
                name: "SchemaVersion",
                table: "InboxMessages",
                type: "int",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<string>(
                name: "Source",
                table: "InboxMessages",
                type: "nvarchar(128)",
                maxLength: 128,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "Status",
                table: "InboxMessages",
                type: "nvarchar(32)",
                maxLength: 32,
                nullable: false,
                defaultValue: "");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "RowVersion",
                table: "PaymentAttempts");

            migrationBuilder.DropColumn(
                name: "LastError",
                table: "InboxMessages");

            migrationBuilder.DropColumn(
                name: "LockExpiry",
                table: "InboxMessages");

            migrationBuilder.DropColumn(
                name: "Payload",
                table: "InboxMessages");

            migrationBuilder.DropColumn(
                name: "ProcessingAttempts",
                table: "InboxMessages");

            migrationBuilder.DropColumn(
                name: "ProviderEventId",
                table: "InboxMessages");

            migrationBuilder.DropColumn(
                name: "SchemaVersion",
                table: "InboxMessages");

            migrationBuilder.DropColumn(
                name: "Source",
                table: "InboxMessages");

            migrationBuilder.DropColumn(
                name: "Status",
                table: "InboxMessages");

            migrationBuilder.AlterColumn<DateTime>(
                name: "ProcessedUtc",
                table: "InboxMessages",
                type: "datetime2",
                nullable: false,
                defaultValue: new DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeKind.Unspecified),
                oldClrType: typeof(DateTime),
                oldType: "datetime2",
                oldNullable: true);
        }
    }
}
