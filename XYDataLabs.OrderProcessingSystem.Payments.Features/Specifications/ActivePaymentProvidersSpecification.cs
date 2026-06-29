using System.Linq.Expressions;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Specifications;

namespace XYDataLabs.OrderProcessingSystem.Payments.Features.Specifications;

public sealed class ActivePaymentProvidersSpecification : Specification<PaymentProvider>
{
    private readonly bool _includeProductionProviders;

    public ActivePaymentProvidersSpecification(bool includeProductionProviders)
    {
        _includeProductionProviders = includeProductionProviders;
    }

    public override Expression<Func<PaymentProvider, bool>> Criteria
        => provider => provider.IsActive && (_includeProductionProviders || !provider.IsProduction);
}
