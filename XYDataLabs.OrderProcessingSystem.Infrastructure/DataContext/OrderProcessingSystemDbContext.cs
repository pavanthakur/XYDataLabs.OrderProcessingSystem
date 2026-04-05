using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Domain.Identifiers;
using XYDataLabs.OrderProcessingSystem.Domain.ValueObjects;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;
using System.Diagnostics;
using System.Text.Json;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext
{
    public class OrderProcessingSystemDbContext : DbContext, IAppDbContext
    {
        private static readonly JsonSerializerOptions AuditJsonSerializerOptions = new(JsonSerializerDefaults.Web);
        private static readonly HashSet<string> ExcludedAuditPropertyNames = new(StringComparer.OrdinalIgnoreCase)
        {
            nameof(BaseAuditableEntity.TenantId),
            nameof(BaseAuditableEntity.CreatedBy),
            nameof(BaseAuditableEntity.CreatedDate),
            nameof(BaseAuditableEntity.UpdatedBy),
            nameof(BaseAuditableEntity.UpdatedDate),
            nameof(BaseAuditableCreateEntity.TenantId),
            nameof(BaseAuditableCreateEntity.CreatedBy),
            nameof(BaseAuditableCreateEntity.CreatedDate),
            nameof(AuditLog.Id),
            nameof(AuditLog.EntityName),
            nameof(AuditLog.EntityId),
            nameof(AuditLog.Operation),
            nameof(AuditLog.TraceId),
            nameof(AuditLog.CorrelationId),
            nameof(AuditLog.OldValues),
            nameof(AuditLog.NewValues),
            nameof(CardTransaction.CreditCardOwnerName),
            nameof(CardTransaction.MaskedCardNumber),
            nameof(PayinLog.LastFourCardNbr),
            nameof(PayinLog.CardOwnerName),
            nameof(PaymentMethod.Token),
            "PostInfo",
            "RespInfo",
            "AdditionalInfo"
        };

        private readonly ITenantProvider? _tenantProvider;
        private bool _isSavingAuditLogs;

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
        public virtual DbSet<AuditLog> AuditLogs { get; set; }
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
            ArgumentNullException.ThrowIfNull(optionsBuilder);

            if (!optionsBuilder.IsConfigured)
            {
                optionsBuilder.UseSqlServer("OrderProcessingSystemDbConnection");
            }
        }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            ArgumentNullException.ThrowIfNull(modelBuilder);

            var customerIdConverter = new ValueConverter<CustomerId, int>(id => id.Value, value => new CustomerId(value));
            var orderIdConverter = new ValueConverter<OrderId, int>(id => id.Value, value => new OrderId(value));
            var productIdConverter = new ValueConverter<ProductId, int>(id => id.Value, value => new ProductId(value));
            var moneyConverter = new ValueConverter<Money, decimal>(money => money.Value, value => Money.From(value));

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

            modelBuilder.Entity<Customer>()
                .Property(customer => customer.CustomerId)
                .HasConversion(customerIdConverter)
                .ValueGeneratedOnAdd();

            modelBuilder.Entity<Product>()
                .Property(product => product.ProductId)
                .HasConversion(productIdConverter)
                .ValueGeneratedOnAdd();

            modelBuilder.Entity<Product>()
                .Property(product => product.Price)
                .HasConversion(moneyConverter)
                .HasColumnType("decimal(18,2)");

            modelBuilder.Entity<Order>()
                .Property(order => order.OrderId)
                .HasConversion(orderIdConverter)
                .ValueGeneratedOnAdd();

            modelBuilder.Entity<Order>()
                .Property(order => order.CustomerId)
                .HasConversion(customerIdConverter);

            modelBuilder.Entity<Order>()
                .Property(order => order.TotalPrice)
                .HasConversion(moneyConverter)
                .HasColumnType("decimal(18,2)");

            modelBuilder.Entity<OrderProduct>()
                .Property(orderProduct => orderProduct.OrderId)
                .HasConversion(orderIdConverter);

            modelBuilder.Entity<OrderProduct>()
                .Property(orderProduct => orderProduct.ProductId)
                .HasConversion(productIdConverter);

            modelBuilder.Entity<OrderProduct>()
                .HasOne(op => op.Order)
                .WithMany(o => o.OrderProducts)
                .HasForeignKey(op => op.OrderId);

            modelBuilder.Entity<OrderProduct>()
                .HasOne(op => op.Product)
                .WithMany(p => p.OrderProducts)
                .HasForeignKey(op => op.ProductId);

            modelBuilder.Entity<Order>()
                .Property(order => order.Status)
                .HasConversion<string>()
                .HasMaxLength(32)
                .HasDefaultValue(OrderStatus.Created);

            modelBuilder.Entity<Order>()
                .Property(order => order.RowVersion)
                .IsRowVersion();

            modelBuilder.Entity<Order>()
                .HasIndex(order => new { order.TenantId, order.CustomerId, order.Status });

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

            modelBuilder.Entity<AuditLog>()
                .HasIndex(auditLog => new { auditLog.TenantId, auditLog.EntityName, auditLog.EntityId });

            modelBuilder.Entity<AuditLog>()
                .HasIndex(auditLog => auditLog.CreatedDate);

            modelBuilder.Entity<PaymentMethod>()
                .HasIndex(pm => pm.Token)
                .IsUnique();

            modelBuilder.Entity<AuditLog>()
                .Property(auditLog => auditLog.EntityName)
                .HasMaxLength(128);

            modelBuilder.Entity<AuditLog>()
                .Property(auditLog => auditLog.EntityId)
                .HasMaxLength(64);

            modelBuilder.Entity<AuditLog>()
                .Property(auditLog => auditLog.Operation)
                .HasMaxLength(16);

            modelBuilder.Entity<AuditLog>()
                .Property(auditLog => auditLog.TraceId)
                .HasMaxLength(64);

            modelBuilder.Entity<AuditLog>()
                .Property(auditLog => auditLog.CorrelationId)
                .HasMaxLength(128);

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

            ConfigureTenantOwnership<AuditLog>(modelBuilder);
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
            if (_isSavingAuditLogs)
            {
                return base.SaveChanges();
            }

            StampTenantOnAddedEntities();

            var pendingAuditLogs = CreatePendingAuditLogs();
            var startedTransaction = Database.CurrentTransaction is null;
            using var transaction = startedTransaction ? Database.BeginTransaction() : null;

            var result = base.SaveChanges();
            PersistAuditLogs(pendingAuditLogs);

            transaction?.Commit();
            return result;
        }

        public override async Task<int> SaveChangesAsync(CancellationToken cancellationToken = default)
        {
            if (_isSavingAuditLogs)
            {
                return await base.SaveChangesAsync(cancellationToken);
            }

            StampTenantOnAddedEntities();

            var pendingAuditLogs = CreatePendingAuditLogs();
            var startedTransaction = Database.CurrentTransaction is null;
            await using var transaction = startedTransaction ? await Database.BeginTransactionAsync(cancellationToken) : null;

            var result = await base.SaveChangesAsync(cancellationToken);
            await PersistAuditLogsAsync(pendingAuditLogs, cancellationToken);

            if (transaction is not null)
            {
                await transaction.CommitAsync(cancellationToken);
            }

            return result;
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

        private List<PendingAuditLog> CreatePendingAuditLogs()
        {
            if (_tenantProvider is null || !_tenantProvider.HasTenantContext)
            {
                return new List<PendingAuditLog>();
            }

            var tenantId = _tenantProvider.TenantId;
            if (tenantId <= 0)
            {
                return new List<PendingAuditLog>();
            }

            var pendingAuditLogs = new List<PendingAuditLog>();

            foreach (var entry in ChangeTracker.Entries())
            {
                if (!ShouldAuditEntry(entry))
                {
                    continue;
                }

                var operation = entry.State switch
                {
                    EntityState.Added => "Created",
                    EntityState.Modified => "Updated",
                    EntityState.Deleted => "Deleted",
                    _ => string.Empty
                };

                if (string.IsNullOrWhiteSpace(operation))
                {
                    continue;
                }

                Dictionary<string, object?>? oldValues = null;
                Dictionary<string, object?>? newValues = null;

                if (entry.State == EntityState.Modified)
                {
                    oldValues = GetPropertyValues(entry, useOriginalValues: true, changedPropertiesOnly: true);
                    newValues = GetPropertyValues(entry, useOriginalValues: false, changedPropertiesOnly: true);

                    if (oldValues.Count == 0 && newValues.Count == 0)
                    {
                        continue;
                    }
                }
                else if (entry.State == EntityState.Deleted)
                {
                    oldValues = GetPropertyValues(entry, useOriginalValues: true, changedPropertiesOnly: false);
                }

                pendingAuditLogs.Add(new PendingAuditLog(
                    entry,
                    tenantId,
                    entry.Metadata.ClrType.Name,
                    entry.State == EntityState.Added ? null : GetEntityIdentifier(entry),
                    operation,
                    oldValues,
                    newValues));
            }

            return pendingAuditLogs;
        }

        private void PersistAuditLogs(List<PendingAuditLog> pendingAuditLogs)
        {
            if (pendingAuditLogs.Count == 0)
            {
                return;
            }

            var auditLogs = MaterializeAuditLogs(pendingAuditLogs);
            if (auditLogs.Count == 0)
            {
                return;
            }

            _isSavingAuditLogs = true;
            try
            {
                AuditLogs.AddRange(auditLogs);
                base.SaveChanges();
            }
            finally
            {
                _isSavingAuditLogs = false;
            }
        }

        private async Task PersistAuditLogsAsync(List<PendingAuditLog> pendingAuditLogs, CancellationToken cancellationToken)
        {
            if (pendingAuditLogs.Count == 0)
            {
                return;
            }

            var auditLogs = MaterializeAuditLogs(pendingAuditLogs);
            if (auditLogs.Count == 0)
            {
                return;
            }

            _isSavingAuditLogs = true;
            try
            {
                AuditLogs.AddRange(auditLogs);
                await base.SaveChangesAsync(cancellationToken);
            }
            finally
            {
                _isSavingAuditLogs = false;
            }
        }

        private List<AuditLog> MaterializeAuditLogs(List<PendingAuditLog> pendingAuditLogs)
        {
            var createdAt = DateTime.UtcNow;
            var traceId = Activity.Current?.TraceId.ToString();
            var correlationId = Activity.Current?.Id;
            var auditLogs = new List<AuditLog>(pendingAuditLogs.Count);

            foreach (var pendingAuditLog in pendingAuditLogs)
            {
                if (pendingAuditLog.Operation == "Created")
                {
                    pendingAuditLog.NewValues = GetPropertyValues(pendingAuditLog.Entry, useOriginalValues: false, changedPropertiesOnly: false);
                }

                var entityId = pendingAuditLog.EntityId;
                if (string.IsNullOrWhiteSpace(entityId) && pendingAuditLog.Entry.State != EntityState.Detached)
                {
                    entityId = GetEntityIdentifier(pendingAuditLog.Entry);
                }

                if (string.IsNullOrWhiteSpace(entityId))
                {
                    continue;
                }

                auditLogs.Add(new AuditLog
                {
                    TenantId = pendingAuditLog.TenantId,
                    EntityName = pendingAuditLog.EntityName,
                    EntityId = entityId,
                    Operation = pendingAuditLog.Operation,
                    TraceId = traceId,
                    CorrelationId = correlationId,
                    OldValues = SerializeAuditValues(pendingAuditLog.OldValues),
                    NewValues = SerializeAuditValues(pendingAuditLog.NewValues),
                    CreatedDate = createdAt
                });
            }

            return auditLogs;
        }

        private static bool ShouldAuditEntry(EntityEntry entry)
        {
            if (entry.Entity is AuditLog)
            {
                return false;
            }

            if (entry.State is not EntityState.Added and not EntityState.Modified and not EntityState.Deleted)
            {
                return false;
            }

            return entry.Entity is BaseAuditableEntity or BaseAuditableCreateEntity;
        }

        private static Dictionary<string, object?> GetPropertyValues(EntityEntry entry, bool useOriginalValues, bool changedPropertiesOnly)
        {
            var propertyValues = new Dictionary<string, object?>(StringComparer.Ordinal);

            foreach (var property in entry.Properties)
            {
                if (ShouldSkipAuditProperty(property, changedPropertiesOnly))
                {
                    continue;
                }

                var value = useOriginalValues
                    ? property.OriginalValue
                    : property.CurrentValue;

                propertyValues[property.Metadata.Name] = value;
            }

            return propertyValues;
        }

        private static bool ShouldSkipAuditProperty(PropertyEntry property, bool changedPropertiesOnly)
        {
            if (property.Metadata.IsShadowProperty() || property.Metadata.IsPrimaryKey())
            {
                return true;
            }

            if (changedPropertiesOnly && !property.IsModified)
            {
                return true;
            }

            if (property.Metadata.IsForeignKey())
            {
                return false;
            }

            if (!IsSupportedAuditType(property.Metadata.ClrType))
            {
                return true;
            }

            return ExcludedAuditPropertyNames.Contains(property.Metadata.Name);
        }

        private static bool IsSupportedAuditType(Type clrType)
        {
            var actualType = Nullable.GetUnderlyingType(clrType) ?? clrType;

            return actualType.IsPrimitive
                || actualType.IsEnum
                || actualType == typeof(string)
                || actualType == typeof(decimal)
                || actualType == typeof(DateTime)
                || actualType == typeof(DateTimeOffset)
                || actualType == typeof(Guid)
                || actualType == typeof(TimeSpan)
                || actualType == typeof(bool);
        }

        private static string? SerializeAuditValues(Dictionary<string, object?>? values)
        {
            if (values is null || values.Count == 0)
            {
                return null;
            }

            return JsonSerializer.Serialize(values, AuditJsonSerializerOptions);
        }

        private static string GetEntityIdentifier(EntityEntry entry)
        {
            var primaryKey = entry.Metadata.FindPrimaryKey();
            if (primaryKey is null)
            {
                return string.Empty;
            }

            var parts = primaryKey.Properties
                .Select(property => $"{property.Name}={entry.Property(property.Name).CurrentValue}")
                .ToArray();

            return string.Join("|", parts);
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

        private sealed class PendingAuditLog
        {
            public PendingAuditLog(
                EntityEntry entry,
                int tenantId,
                string entityName,
                string? entityId,
                string operation,
                Dictionary<string, object?>? oldValues,
                Dictionary<string, object?>? newValues)
            {
                Entry = entry;
                TenantId = tenantId;
                EntityName = entityName;
                EntityId = entityId;
                Operation = operation;
                OldValues = oldValues;
                NewValues = newValues;
            }

            public EntityEntry Entry { get; }

            public int TenantId { get; }

            public string EntityName { get; }

            public string? EntityId { get; }

            public string Operation { get; }

            public Dictionary<string, object?>? OldValues { get; }

            public Dictionary<string, object?>? NewValues { get; set; }
        }
    }
}