using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class RemoveRawCardData_PCI : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "CreditCardCvv2",
                table: "CardTransactions");

            migrationBuilder.DropColumn(
                name: "CreditCardNumber",
                table: "CardTransactions");

            migrationBuilder.AddColumn<string>(
                name: "MaskedCardNumber",
                table: "CardTransactions",
                type: "nvarchar(19)",
                maxLength: 19,
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "MaskedCardNumber",
                table: "CardTransactions");

            migrationBuilder.AddColumn<string>(
                name: "CreditCardCvv2",
                table: "CardTransactions",
                type: "nvarchar(255)",
                maxLength: 255,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "CreditCardNumber",
                table: "CardTransactions",
                type: "nvarchar(255)",
                maxLength: 255,
                nullable: false,
                defaultValue: "");
        }
    }
}
