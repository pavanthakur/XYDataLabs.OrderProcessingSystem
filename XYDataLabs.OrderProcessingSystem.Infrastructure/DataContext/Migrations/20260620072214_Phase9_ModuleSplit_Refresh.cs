using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext.Migrations
{
    /// <inheritdoc />
    public partial class Phase9_ModuleSplit_Refresh : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.EnsureSchema(
                name: "notifications");

            migrationBuilder.EnsureSchema(
                name: "payments");

            migrationBuilder.EnsureSchema(
                name: "orders");

            migrationBuilder.EnsureSchema(
                name: "inventory");

            migrationBuilder.RenameTable(
                name: "TransactionStatusHistories",
                newName: "TransactionStatusHistories",
                newSchema: "payments");

            migrationBuilder.RenameTable(
                name: "Products",
                newName: "Products",
                newSchema: "inventory");

            migrationBuilder.RenameTable(
                name: "PaymentProviders",
                newName: "PaymentProviders",
                newSchema: "payments");

            migrationBuilder.RenameTable(
                name: "PaymentMethods",
                newName: "PaymentMethods",
                newSchema: "payments");

            migrationBuilder.RenameTable(
                name: "PaymentAttempts",
                newName: "PaymentAttempts",
                newSchema: "payments");

            migrationBuilder.RenameTable(
                name: "PaymentAttemptHistories",
                newName: "PaymentAttemptHistories",
                newSchema: "payments");

            migrationBuilder.RenameTable(
                name: "PayinLogs",
                newName: "PayinLogs",
                newSchema: "payments");

            migrationBuilder.RenameTable(
                name: "PayinLogDetails",
                newName: "PayinLogDetails",
                newSchema: "payments");

            migrationBuilder.RenameTable(
                name: "OutboxMessages",
                newName: "OutboxMessages",
                newSchema: "notifications");

            migrationBuilder.RenameTable(
                name: "Orders",
                newName: "Orders",
                newSchema: "orders");

            migrationBuilder.RenameTable(
                name: "OrderProducts",
                newName: "OrderProducts",
                newSchema: "orders");

            migrationBuilder.RenameTable(
                name: "InboxMessages",
                newName: "InboxMessages",
                newSchema: "notifications");

            migrationBuilder.RenameTable(
                name: "Customers",
                newName: "Customers",
                newSchema: "orders");

            migrationBuilder.RenameTable(
                name: "CardTransactions",
                newName: "CardTransactions",
                newSchema: "payments");

            migrationBuilder.RenameTable(
                name: "BillingCustomers",
                newName: "BillingCustomers",
                newSchema: "payments");

            migrationBuilder.RenameTable(
                name: "BillingCustomerKeyInfos",
                newName: "BillingCustomerKeyInfos",
                newSchema: "payments");

            migrationBuilder.RenameTable(
                name: "AuditLogs",
                newName: "AuditLogs",
                newSchema: "notifications");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.RenameTable(
                name: "TransactionStatusHistories",
                schema: "payments",
                newName: "TransactionStatusHistories");

            migrationBuilder.RenameTable(
                name: "Products",
                schema: "inventory",
                newName: "Products");

            migrationBuilder.RenameTable(
                name: "PaymentProviders",
                schema: "payments",
                newName: "PaymentProviders");

            migrationBuilder.RenameTable(
                name: "PaymentMethods",
                schema: "payments",
                newName: "PaymentMethods");

            migrationBuilder.RenameTable(
                name: "PaymentAttempts",
                schema: "payments",
                newName: "PaymentAttempts");

            migrationBuilder.RenameTable(
                name: "PaymentAttemptHistories",
                schema: "payments",
                newName: "PaymentAttemptHistories");

            migrationBuilder.RenameTable(
                name: "PayinLogs",
                schema: "payments",
                newName: "PayinLogs");

            migrationBuilder.RenameTable(
                name: "PayinLogDetails",
                schema: "payments",
                newName: "PayinLogDetails");

            migrationBuilder.RenameTable(
                name: "OutboxMessages",
                schema: "notifications",
                newName: "OutboxMessages");

            migrationBuilder.RenameTable(
                name: "Orders",
                schema: "orders",
                newName: "Orders");

            migrationBuilder.RenameTable(
                name: "OrderProducts",
                schema: "orders",
                newName: "OrderProducts");

            migrationBuilder.RenameTable(
                name: "InboxMessages",
                schema: "notifications",
                newName: "InboxMessages");

            migrationBuilder.RenameTable(
                name: "Customers",
                schema: "orders",
                newName: "Customers");

            migrationBuilder.RenameTable(
                name: "CardTransactions",
                schema: "payments",
                newName: "CardTransactions");

            migrationBuilder.RenameTable(
                name: "BillingCustomers",
                schema: "payments",
                newName: "BillingCustomers");

            migrationBuilder.RenameTable(
                name: "BillingCustomerKeyInfos",
                schema: "payments",
                newName: "BillingCustomerKeyInfos");

            migrationBuilder.RenameTable(
                name: "AuditLogs",
                schema: "notifications",
                newName: "AuditLogs");
        }
    }
}
