using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace XYDataLabs.OrderProcessingSystem.Application.Utilities
{
    public class AppMasterData
    {
        private readonly IAppDbContext _dbContext;
        private IReadOnlyList<PaymentProvider> _paymentProviders = new List<PaymentProvider>().AsReadOnly();

        public AppMasterData(IAppDbContext dbContext)
        {
            _dbContext = dbContext;
            InitializeData();
        }

        private void InitializeData()
        {
            // Loads only the current tenant's payment providers via the request-scoped
            // DbContext (tenant query filter active). Each tenant sees only its own
            // providers, whether on shared pool or dedicated DB. No filter bypass needed.
            _paymentProviders = _dbContext.PaymentProviders
                .AsNoTracking()
                .ToList()
                .AsReadOnly();
        }

        public IReadOnlyList<PaymentProvider> PaymentProviders => _paymentProviders;

        public PaymentProvider? GetProviderByName(string name)
        {
            return _paymentProviders.FirstOrDefault(p => p.Name.Equals(name, StringComparison.OrdinalIgnoreCase));
        }

        public PaymentProvider? GetProviderByNameForTenant(string name, int tenantId)
        {
            return _paymentProviders.FirstOrDefault(p =>
                p.Name.Equals(name, StringComparison.OrdinalIgnoreCase) && p.TenantId == tenantId);
        }

        public PaymentProvider? GetProviderByTypeForTenant(string providerType, int tenantId)
        {
            return _paymentProviders.FirstOrDefault(p =>
                p.ProviderType.Equals(providerType, StringComparison.OrdinalIgnoreCase) && p.TenantId == tenantId);
        }

        public PaymentProvider? GetActiveProviderForTenant(int tenantId)
        {
            var activeProviders = _paymentProviders
                .Where(p => p.TenantId == tenantId && p.IsActive)
                .ToList();

            return activeProviders.Count switch
            {
                0 => null,
                1 => activeProviders[0],
                _ => throw new InvalidOperationException($"Multiple active payment providers are configured for tenant {tenantId}.")
            };
        }

        public void RefreshData()
        {
            InitializeData();
        }
    }
}