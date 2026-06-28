using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;

namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Abstractions;

/// <summary>
/// Shared database context contract for feature and infrastructure boundaries.
/// Kept in SharedKernel so module feature projects can depend on the stable persistence seam
/// without reintroducing a dependency on Application.
/// </summary>
public interface IAppDbContext
{
    DbSet<AuditLog> AuditLogs { get; }
    DbSet<Customer> Customers { get; }
    DbSet<Product> Products { get; }
    DbSet<Order> Orders { get; }
    DbSet<OrderProduct> OrderProducts { get; }
    DbSet<BillingCustomer> BillingCustomers { get; }
    DbSet<BillingCustomerKeyInfo> BillingCustomerKeyInfos { get; }
    DbSet<CardTransaction> CardTransactions { get; }
    DbSet<PayinLog> PayinLogs { get; }
    DbSet<PayinLogDetails> PayinLogDetails { get; }
    DbSet<PaymentMethod> PaymentMethods { get; }
    DbSet<PaymentProvider> PaymentProviders { get; }
    DbSet<PaymentAttempt> PaymentAttempts { get; }
    DbSet<PaymentAttemptHistory> PaymentAttemptHistories { get; }
    DbSet<TransactionStatusHistory> TransactionStatusHistories { get; }
    DbSet<OutboxMessage> OutboxMessages { get; }
    DbSet<InboxMessage> InboxMessages { get; }

    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}
