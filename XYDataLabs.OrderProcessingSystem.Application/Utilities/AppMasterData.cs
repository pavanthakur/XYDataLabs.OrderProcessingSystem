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

        public void RefreshData()
        {
            InitializeData();
        }
    }
}