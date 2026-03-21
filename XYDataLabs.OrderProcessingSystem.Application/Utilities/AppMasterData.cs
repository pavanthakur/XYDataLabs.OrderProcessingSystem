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
            //TODO : Add caching mechanism to avoid multiple db calls
            // Load payment providers with their methods
            _paymentProviders = _dbContext.PaymentProviders
                .IgnoreQueryFilters()
                .AsNoTracking()
                .ToList()
                .AsReadOnly();
        }

        public IReadOnlyList<PaymentProvider> PaymentProviders => _paymentProviders;

        public PaymentProvider? GetProviderByName(string name)
        {
            return _paymentProviders.FirstOrDefault(p => p.Name.Equals(name, StringComparison.OrdinalIgnoreCase));
        }

        public void RefreshData()
        {
            InitializeData();
        }
    }
}