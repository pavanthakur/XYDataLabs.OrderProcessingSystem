using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext
{
    public class OrderProcessingSystemDbContext : DbContext
    {
        public OrderProcessingSystemDbContext()
        {
        }

        public OrderProcessingSystemDbContext(DbContextOptions<OrderProcessingSystemDbContext> options)
        : base(options)
        {
        }

        // Existing DbSets
        public virtual DbSet<Customer> Customers { get; set; }
        public virtual DbSet<Product> Products { get; set; }
        public virtual DbSet<Order> Orders { get; set; }
        public virtual DbSet<OrderProduct> OrderProducts { get; set; }

        // New Payment-related DbSets
        public virtual DbSet<BillingCustomer> BillingCustomers { get; set; }
        public virtual DbSet<BillingCustomerKeyInfo> BillingCustomerKeyInfos { get; set; }
        public virtual DbSet<CardTransaction> CardTransactions { get; set; }
        public virtual DbSet<PayinLog> PayinLogs { get; set; }
        public virtual DbSet<PayinLogDetails> PayinLogDetails { get; set; }
        public virtual DbSet<PaymentMethod> PaymentMethods { get; set; }
        public virtual DbSet<PaymentProvider> PaymentProviders { get; set; }
        public virtual DbSet<TransactionStatusHistory> TransactionStatusHistories { get; set; }

        protected override void OnConfiguring(DbContextOptionsBuilder optionsBuilder)
        {
            if (!optionsBuilder.IsConfigured)
            {
                optionsBuilder.UseSqlServer("OrderProcessingSystemDbConnection");
            }
        }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            base.OnModelCreating(modelBuilder);

            // Configure many-to-many relationship
            modelBuilder.Entity<OrderProduct>()
                .HasKey(op => new { op.OrderId, op.ProductId });

            modelBuilder.Entity<OrderProduct>()
                .HasOne(op => op.Order)
                .WithMany(o => o.OrderProducts)
                .HasForeignKey(op => op.OrderId);

            modelBuilder.Entity<OrderProduct>()
                .HasOne(op => op.Product)
                .WithMany(p => p.OrderProducts)
                .HasForeignKey(op => op.ProductId);

            // New Payment-related configurations
            modelBuilder.Entity<BillingCustomer>()
                .HasOne(bc => bc.PaymentMethod)
                .WithMany(pm => pm.BillingCustomers)
                .HasForeignKey(bc => bc.PaymentMethodId)
                .OnDelete(DeleteBehavior.Restrict);

            modelBuilder.Entity<BillingCustomerKeyInfo>()
                .HasOne(bcki => bcki.BillingCustomer)
                .WithMany(bc => bc.KeyInfos)
                .HasForeignKey(bcki => bcki.BillingCustomerId)
                .OnDelete(DeleteBehavior.Cascade);

            modelBuilder.Entity<CardTransaction>()
                .HasOne(ct => ct.Customer)
                .WithMany(bc => bc.CardTransactions)
                .HasForeignKey(ct => ct.CustomerId)
                .OnDelete(DeleteBehavior.Restrict);

            modelBuilder.Entity<TransactionStatusHistory>()
                .HasOne(tsh => tsh.Transaction)
                .WithMany(ct => ct.StatusHistory)
                .HasForeignKey(tsh => tsh.TransactionId)
                .OnDelete(DeleteBehavior.Cascade);

            modelBuilder.Entity<PayinLog>()
                .HasOne(pl => pl.PaymentMethod)
                .WithMany(pm => pm.PayinLogs)
                .HasForeignKey(pl => pl.PaymentMethodId)
                .OnDelete(DeleteBehavior.Restrict);

            modelBuilder.Entity<PayinLogDetails>()
                .HasOne(pld => pld.PayinLog)
                .WithMany(pl => pl.PayinLogDetails)
                .HasForeignKey(pld => pld.PayinLogId)
                .OnDelete(DeleteBehavior.Cascade);

            // Configure indexes for better query performance
            modelBuilder.Entity<BillingCustomer>()
                .HasIndex(bc => bc.Email);

            modelBuilder.Entity<BillingCustomer>()
                .HasIndex(bc => bc.APICustomerId);

            modelBuilder.Entity<CardTransaction>()
                .HasIndex(ct => ct.TransactionId);

            modelBuilder.Entity<CardTransaction>()
                .HasIndex(ct => ct.TransactionDate);

            modelBuilder.Entity<PayinLog>()
                .HasIndex(pl => pl.ReferenceNo);

            modelBuilder.Entity<PaymentMethod>()
                .HasIndex(pm => pm.Token)
                .IsUnique();

            // Configure sensitive data columns with encryption
            modelBuilder.Entity<CardTransaction>()
                .Property(ct => ct.CreditCardNumber)
                .HasMaxLength(255); // Encrypted value will be longer

            modelBuilder.Entity<CardTransaction>()
                .Property(ct => ct.CreditCardCvv2)
                .HasMaxLength(255); // Encrypted value will be longer
        }
    }
}