using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;
using Microsoft.EntityFrameworkCore;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext
{
    public class OrderProcessingSystemDbContext : DbContext, IAppDbContext
    {
        private readonly ITenantProvider? _tenantProvider;

        public OrderProcessingSystemDbContext()
        {
        }

        public OrderProcessingSystemDbContext(DbContextOptions<OrderProcessingSystemDbContext> options)
        : base(options)
        {
        }

        public OrderProcessingSystemDbContext(
            DbContextOptions<OrderProcessingSystemDbContext> options,
            ITenantProvider tenantProvider)
        : base(options)
        {
            _tenantProvider = tenantProvider;
        }

        public virtual DbSet<Tenant> Tenants { get; set; }

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

            modelBuilder.Entity<Tenant>()
                .HasIndex(item => item.ExternalId)
                .IsUnique();

            modelBuilder.Entity<Tenant>()
                .HasIndex(item => item.Code)
                .IsUnique();

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
                .HasOne(ct => ct.BillingCustomer)
                .WithMany(bc => bc.CardTransactions)
                .HasForeignKey(ct => ct.BillingCustomerId)
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
                .HasIndex(ct => ct.PaymentTraceId);

            modelBuilder.Entity<CardTransaction>()
                .HasIndex(ct => new { ct.TenantId, ct.CustomerOrderId });

            modelBuilder.Entity<CardTransaction>()
                .HasIndex(ct => new { ct.TenantId, ct.AttemptOrderId });

            modelBuilder.Entity<CardTransaction>()
                .HasIndex(ct => ct.TransactionDate);

            modelBuilder.Entity<PayinLog>()
                .HasIndex(pl => new { pl.TenantId, pl.AttemptOrderId });

            modelBuilder.Entity<PayinLog>()
                .HasIndex(pl => pl.CustomerOrderId);

            modelBuilder.Entity<PayinLog>()
                .HasIndex(pl => pl.PaymentTraceId);

            modelBuilder.Entity<TransactionStatusHistory>()
                .HasIndex(tsh => new { tsh.TenantId, tsh.AttemptOrderId });

            modelBuilder.Entity<TransactionStatusHistory>()
                .HasIndex(tsh => new { tsh.TenantId, tsh.TransactionReferenceId });

            modelBuilder.Entity<PaymentMethod>()
                .HasIndex(pm => pm.Token)
                .IsUnique();

            modelBuilder.Entity<CardTransaction>()
                .Property(ct => ct.MaskedCardNumber)
                .HasMaxLength(19);

            modelBuilder.Entity<CardTransaction>()
                .Property(ct => ct.PaymentTraceId)
                .HasMaxLength(64);

            modelBuilder.Entity<CardTransaction>()
                .Property(ct => ct.CustomerOrderId)
                .HasMaxLength(128);

            modelBuilder.Entity<CardTransaction>()
                .Property(ct => ct.AttemptOrderId)
                .HasMaxLength(128);

            modelBuilder.Entity<CardTransaction>()
                .Property(ct => ct.ThreeDSecureStage)
                .HasMaxLength(64);

            modelBuilder.Entity<PayinLog>()
                .Property(pl => pl.PaymentTraceId)
                .HasMaxLength(64);

            modelBuilder.Entity<PayinLog>()
                .Property(pl => pl.CustomerOrderId)
                .HasMaxLength(128);

            modelBuilder.Entity<PayinLog>()
                .Property(pl => pl.AttemptOrderId)
                .HasMaxLength(128);

            modelBuilder.Entity<PayinLog>()
                .Property(pl => pl.ThreeDSecureStage)
                .HasMaxLength(64);

            modelBuilder.Entity<PayinLogDetails>()
                .Property(pld => pld.PaymentTraceId)
                .HasMaxLength(64);

            modelBuilder.Entity<PayinLogDetails>()
                .Property(pld => pld.ThreeDSecureStage)
                .HasMaxLength(64);

            modelBuilder.Entity<TransactionStatusHistory>()
                .Property(tsh => tsh.PaymentTraceId)
                .HasMaxLength(64);

            modelBuilder.Entity<TransactionStatusHistory>()
                .Property(tsh => tsh.ThreeDSecureStage)
                .HasMaxLength(64);

            modelBuilder.Entity<TransactionStatusHistory>()
                .Property(tsh => tsh.AttemptOrderId)
                .HasMaxLength(128);

            ConfigureTenantOwnership<Customer>(modelBuilder);
            ConfigureTenantOwnership<Order>(modelBuilder);
            ConfigureTenantOwnership<Product>(modelBuilder);
            ConfigureTenantOwnership<BillingCustomer>(modelBuilder);
            ConfigureTenantOwnership<BillingCustomerKeyInfo>(modelBuilder);
            ConfigureTenantOwnership<CardTransaction>(modelBuilder);
            ConfigureTenantOwnership<PayinLog>(modelBuilder);
            ConfigureTenantOwnership<PayinLogDetails>(modelBuilder);
            ConfigureTenantOwnership<PaymentMethod>(modelBuilder);
            ConfigureTenantOwnership<PaymentProvider>(modelBuilder);
            ConfigureTenantOwnership<TransactionStatusHistory>(modelBuilder);
            ConfigureTenantOwnership<OrderProduct>(modelBuilder);
        }

        public override int SaveChanges()
        {
            StampTenantOnAddedEntities();
            return base.SaveChanges();
        }

        public override async Task<int> SaveChangesAsync(CancellationToken cancellationToken = default)
        {
            StampTenantOnAddedEntities();
            return await base.SaveChangesAsync(cancellationToken);
        }

        private void StampTenantOnAddedEntities()
        {
            if (_tenantProvider is null || !_tenantProvider.HasTenantContext)
                return;

            var tenantId = _tenantProvider.TenantId;

            foreach (var entry in ChangeTracker.Entries())
            {
                if (entry.State == EntityState.Added)
                {
                    if (entry.Entity is BaseAuditableEntity auditable)
                    {
                        auditable.TenantId = tenantId;
                    }
                    else if (entry.Entity is BaseAuditableCreateEntity auditableCreate)
                    {
                        auditableCreate.TenantId = tenantId;
                    }
                }
            }
        }

        private void ConfigureTenantOwnership<TEntity>(ModelBuilder modelBuilder)
            where TEntity : class
        {
            modelBuilder.Entity<TEntity>()
                .HasOne<Tenant>()
                .WithMany()
                .HasForeignKey("TenantId")
                .OnDelete(DeleteBehavior.Restrict);

            modelBuilder.Entity<TEntity>()
                .HasQueryFilter(BuildTenantFilterExpression<TEntity>());
        }

        private System.Linq.Expressions.Expression<Func<TEntity, bool>> BuildTenantFilterExpression<TEntity>()
            where TEntity : class
        {
            return entity => _tenantProvider == null || !_tenantProvider.HasTenantContext || EF.Property<int>(entity, "TenantId") == _tenantProvider.TenantId;
        }
    }
}