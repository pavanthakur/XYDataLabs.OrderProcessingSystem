using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddOpenpayPaymentTables : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "PaymentProviders",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    Name = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: false),
                    APIUrl = table.Column<string>(type: "nvarchar(255)", maxLength: 255, nullable: false),
                    IsProduction = table.Column<bool>(type: "bit", nullable: false),
                    IsActive = table.Column<bool>(type: "bit", nullable: false),
                    CreatedBy = table.Column<int>(type: "int", nullable: true),
                    CreatedDate = table.Column<DateTime>(type: "datetime2", nullable: true),
                    UpdatedBy = table.Column<int>(type: "int", nullable: true),
                    UpdatedDate = table.Column<DateTime>(type: "datetime2", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PaymentProviders", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "PaymentMethods",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    PaymentProviderId = table.Column<int>(type: "int", nullable: false),
                    Token = table.Column<string>(type: "nvarchar(450)", nullable: false),
                    Status = table.Column<bool>(type: "bit", nullable: false),
                    CreatedBy = table.Column<int>(type: "int", nullable: true),
                    CreatedDate = table.Column<DateTime>(type: "datetime2", nullable: true),
                    UpdatedBy = table.Column<int>(type: "int", nullable: true),
                    UpdatedDate = table.Column<DateTime>(type: "datetime2", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PaymentMethods", x => x.Id);
                    table.ForeignKey(
                        name: "FK_PaymentMethods_PaymentProviders_PaymentProviderId",
                        column: x => x.PaymentProviderId,
                        principalTable: "PaymentProviders",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "BillingCustomers",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    TwoLetterIsoCode = table.Column<string>(type: "nvarchar(2)", maxLength: 2, nullable: false),
                    Name = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    Email = table.Column<string>(type: "nvarchar(450)", nullable: false),
                    PhoneNumber = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    APICustomerId = table.Column<string>(type: "nvarchar(450)", nullable: false),
                    PaymentMethodId = table.Column<int>(type: "int", nullable: false),
                    CreatedBy = table.Column<int>(type: "int", nullable: true),
                    CreatedDate = table.Column<DateTime>(type: "datetime2", nullable: true),
                    UpdatedBy = table.Column<int>(type: "int", nullable: true),
                    UpdatedDate = table.Column<DateTime>(type: "datetime2", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_BillingCustomers", x => x.Id);
                    table.ForeignKey(
                        name: "FK_BillingCustomers_PaymentMethods_PaymentMethodId",
                        column: x => x.PaymentMethodId,
                        principalTable: "PaymentMethods",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "PayinLogs",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    ReferenceNo = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: true),
                    PaymentMethodId = table.Column<int>(type: "int", nullable: true),
                    PaymentMethodName = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: true),
                    PayinType = table.Column<int>(type: "int", nullable: true),
                    APINO1 = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: true),
                    APINO2 = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: true),
                    Amount = table.Column<decimal>(type: "decimal(18,4)", nullable: true),
                    AmountFromAPI = table.Column<decimal>(type: "decimal(18,4)", nullable: true),
                    LastFourCardNbr = table.Column<string>(type: "nvarchar(4)", maxLength: 4, nullable: true),
                    CardOwnerName = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true),
                    Currency = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: true),
                    Result = table.Column<int>(type: "int", nullable: true),
                    CreatedBy = table.Column<int>(type: "int", nullable: true),
                    CreatedDate = table.Column<DateTime>(type: "datetime2", nullable: true),
                    UpdatedBy = table.Column<int>(type: "int", nullable: true),
                    UpdatedDate = table.Column<DateTime>(type: "datetime2", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PayinLogs", x => x.Id);
                    table.ForeignKey(
                        name: "FK_PayinLogs_PaymentMethods_PaymentMethodId",
                        column: x => x.PaymentMethodId,
                        principalTable: "PaymentMethods",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "BillingCustomerKeyInfos",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    BillingCustomerId = table.Column<int>(type: "int", nullable: false),
                    KeyName = table.Column<string>(type: "nvarchar(255)", maxLength: 255, nullable: false),
                    KeyValue = table.Column<string>(type: "nvarchar(255)", maxLength: 255, nullable: false),
                    CreatedBy = table.Column<int>(type: "int", nullable: true),
                    CreatedDate = table.Column<DateTime>(type: "datetime2", nullable: true),
                    UpdatedBy = table.Column<int>(type: "int", nullable: true),
                    UpdatedDate = table.Column<DateTime>(type: "datetime2", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_BillingCustomerKeyInfos", x => x.Id);
                    table.ForeignKey(
                        name: "FK_BillingCustomerKeyInfos_BillingCustomers_BillingCustomerId",
                        column: x => x.BillingCustomerId,
                        principalTable: "BillingCustomers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "CardTransactions",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    CustomerId = table.Column<int>(type: "int", nullable: false),
                    TransactionCustomerId = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    TransactionId = table.Column<string>(type: "nvarchar(450)", nullable: false),
                    PaymentMethod = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    TransactionType = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    OrderId = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    TransactionStatus = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    TransactionReferenceId = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    TransactionDate = table.Column<DateTime>(type: "datetime2", nullable: true),
                    CurrencyCode = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    CreditCardOwnerName = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    CreditCardExpireYear = table.Column<int>(type: "int", nullable: false),
                    CreditCardExpireMonth = table.Column<int>(type: "int", nullable: false),
                    CreditCardCvv2 = table.Column<string>(type: "nvarchar(255)", maxLength: 255, nullable: false),
                    Description = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    Amount = table.Column<decimal>(type: "decimal(18,2)", nullable: false),
                    CreditCardNumber = table.Column<string>(type: "nvarchar(255)", maxLength: 255, nullable: false),
                    IsTransactionSuccess = table.Column<bool>(type: "bit", nullable: false),
                    RedirectUrl = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    TransactionMessage = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    CreatedBy = table.Column<int>(type: "int", nullable: true),
                    CreatedDate = table.Column<DateTime>(type: "datetime2", nullable: true),
                    UpdatedBy = table.Column<int>(type: "int", nullable: true),
                    UpdatedDate = table.Column<DateTime>(type: "datetime2", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_CardTransactions", x => x.Id);
                    table.ForeignKey(
                        name: "FK_CardTransactions_BillingCustomers_CustomerId",
                        column: x => x.CustomerId,
                        principalTable: "BillingCustomers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "PayinLogDetails",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    PostInfo = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    RespInfo = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    AdditionalInfo = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    PayinLogId = table.Column<int>(type: "int", nullable: false),
                    CreatedBy = table.Column<int>(type: "int", nullable: true),
                    CreatedDate = table.Column<DateTime>(type: "datetime2", nullable: true),
                    UpdatedBy = table.Column<int>(type: "int", nullable: true),
                    UpdatedDate = table.Column<DateTime>(type: "datetime2", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PayinLogDetails", x => x.Id);
                    table.ForeignKey(
                        name: "FK_PayinLogDetails_PayinLogs_PayinLogId",
                        column: x => x.PayinLogId,
                        principalTable: "PayinLogs",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "TransactionStatusHistories",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    TransactionId = table.Column<int>(type: "int", nullable: false),
                    Status = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: false),
                    Notes = table.Column<string>(type: "nvarchar(255)", maxLength: 255, nullable: true),
                    CreatedBy = table.Column<int>(type: "int", nullable: true),
                    CreatedDate = table.Column<DateTime>(type: "datetime2", nullable: true),
                    UpdatedBy = table.Column<int>(type: "int", nullable: true),
                    UpdatedDate = table.Column<DateTime>(type: "datetime2", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_TransactionStatusHistories", x => x.Id);
                    table.ForeignKey(
                        name: "FK_TransactionStatusHistories_CardTransactions_TransactionId",
                        column: x => x.TransactionId,
                        principalTable: "CardTransactions",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_BillingCustomerKeyInfos_BillingCustomerId",
                table: "BillingCustomerKeyInfos",
                column: "BillingCustomerId");

            migrationBuilder.CreateIndex(
                name: "IX_BillingCustomers_APICustomerId",
                table: "BillingCustomers",
                column: "APICustomerId");

            migrationBuilder.CreateIndex(
                name: "IX_BillingCustomers_Email",
                table: "BillingCustomers",
                column: "Email");

            migrationBuilder.CreateIndex(
                name: "IX_BillingCustomers_PaymentMethodId",
                table: "BillingCustomers",
                column: "PaymentMethodId");

            migrationBuilder.CreateIndex(
                name: "IX_CardTransactions_CustomerId",
                table: "CardTransactions",
                column: "CustomerId");

            migrationBuilder.CreateIndex(
                name: "IX_CardTransactions_TransactionDate",
                table: "CardTransactions",
                column: "TransactionDate");

            migrationBuilder.CreateIndex(
                name: "IX_CardTransactions_TransactionId",
                table: "CardTransactions",
                column: "TransactionId");

            migrationBuilder.CreateIndex(
                name: "IX_PayinLogDetails_PayinLogId",
                table: "PayinLogDetails",
                column: "PayinLogId");

            migrationBuilder.CreateIndex(
                name: "IX_PayinLogs_PaymentMethodId",
                table: "PayinLogs",
                column: "PaymentMethodId");

            migrationBuilder.CreateIndex(
                name: "IX_PayinLogs_ReferenceNo",
                table: "PayinLogs",
                column: "ReferenceNo");

            migrationBuilder.CreateIndex(
                name: "IX_PaymentMethods_PaymentProviderId",
                table: "PaymentMethods",
                column: "PaymentProviderId");

            migrationBuilder.CreateIndex(
                name: "IX_PaymentMethods_Token",
                table: "PaymentMethods",
                column: "Token",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_TransactionStatusHistories_TransactionId",
                table: "TransactionStatusHistories",
                column: "TransactionId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "BillingCustomerKeyInfos");

            migrationBuilder.DropTable(
                name: "PayinLogDetails");

            migrationBuilder.DropTable(
                name: "TransactionStatusHistories");

            migrationBuilder.DropTable(
                name: "PayinLogs");

            migrationBuilder.DropTable(
                name: "CardTransactions");

            migrationBuilder.DropTable(
                name: "BillingCustomers");

            migrationBuilder.DropTable(
                name: "PaymentMethods");

            migrationBuilder.DropTable(
                name: "PaymentProviders");
        }
    }
}
