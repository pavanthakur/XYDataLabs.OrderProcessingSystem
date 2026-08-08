using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class Phase10DlqOperations : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.EnsureSchema(
                name: "operations");

            migrationBuilder.CreateTable(
                name: "DlqQuarantineRecords",
                schema: "operations",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    SourceMessageId = table.Column<string>(type: "nvarchar(128)", maxLength: 128, nullable: false),
                    TenantId = table.Column<int>(type: "int", nullable: true),
                    EventType = table.Column<string>(type: "nvarchar(256)", maxLength: 256, nullable: true),
                    ContentType = table.Column<string>(type: "nvarchar(128)", maxLength: 128, nullable: true),
                    Body = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    ApplicationPropertiesJson = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    CorrelationId = table.Column<string>(type: "nvarchar(128)", maxLength: 128, nullable: true),
                    Subject = table.Column<string>(type: "nvarchar(256)", maxLength: 256, nullable: true),
                    FailureReason = table.Column<string>(type: "nvarchar(256)", maxLength: 256, nullable: false),
                    FailureDescription = table.Column<string>(type: "nvarchar(2048)", maxLength: 2048, nullable: true),
                    ReplayAttemptCount = table.Column<int>(type: "int", nullable: false),
                    State = table.Column<string>(type: "nvarchar(32)", maxLength: 32, nullable: false),
                    CreatedUtc = table.Column<DateTime>(type: "datetime2", nullable: false),
                    ApprovedUtc = table.Column<DateTime>(type: "datetime2", nullable: true),
                    ApprovedBy = table.Column<string>(type: "nvarchar(256)", maxLength: 256, nullable: true),
                    ReplayedUtc = table.Column<DateTime>(type: "datetime2", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_DlqQuarantineRecords", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "DlqReplayRequests",
                schema: "operations",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    QuarantineId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    ApprovedBy = table.Column<string>(type: "nvarchar(256)", maxLength: 256, nullable: false),
                    ApprovedUtc = table.Column<DateTime>(type: "datetime2", nullable: false),
                    PublishedUtc = table.Column<DateTime>(type: "datetime2", nullable: true),
                    ProcessedUtc = table.Column<DateTime>(type: "datetime2", nullable: true),
                    LastError = table.Column<string>(type: "nvarchar(2048)", maxLength: 2048, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_DlqReplayRequests", x => x.Id);
                    table.ForeignKey(
                        name: "FK_DlqReplayRequests_DlqQuarantineRecords_QuarantineId",
                        column: x => x.QuarantineId,
                        principalSchema: "operations",
                        principalTable: "DlqQuarantineRecords",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_DlqQuarantineRecords_SourceMessageId",
                schema: "operations",
                table: "DlqQuarantineRecords",
                column: "SourceMessageId",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_DlqReplayRequests_QuarantineId",
                schema: "operations",
                table: "DlqReplayRequests",
                column: "QuarantineId",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "DlqReplayRequests",
                schema: "operations");

            migrationBuilder.DropTable(
                name: "DlqQuarantineRecords",
                schema: "operations");
        }
    }
}
