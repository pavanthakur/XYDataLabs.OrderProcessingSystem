using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;

namespace XYDataLabs.OrderProcessingSystem.Application.Abstractions;

/// <summary>
/// Abstraction over the application's database context.
/// Defined in Application so services depend on an interface, not the concrete EF Core DbContext.
/// Implemented by OrderProcessingSystemDbContext in Infrastructure.
/// </summary>
public interface IAppDbContext
{
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
    DbSet<TransactionStatusHistory> TransactionStatusHistories { get; }

    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}
