using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.Utilities;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Payments;

public sealed class TenantPaymentProviderResolver : ITenantPaymentProviderResolver
{
    private readonly AppMasterData _appMasterData;
    private readonly ITenantProvider _tenantProvider;

    public TenantPaymentProviderResolver(AppMasterData appMasterData, ITenantProvider tenantProvider)
    {
        ArgumentNullException.ThrowIfNull(appMasterData);
        ArgumentNullException.ThrowIfNull(tenantProvider);

        _appMasterData = appMasterData;
        _tenantProvider = tenantProvider;
    }

    public PaymentProvider ResolveCurrentTenantProvider()
    {
        return _appMasterData.GetActiveProviderForTenant(_tenantProvider.TenantId)
            ?? throw new InvalidOperationException($"No active payment provider is configured for tenant {_tenantProvider.TenantId}.");
    }

    public PaymentProvider ResolveCurrentTenantProvider(string providerType)
    {
        if (string.IsNullOrWhiteSpace(providerType))
        {
            throw new ArgumentException("Provider type is required.", nameof(providerType));
        }

        return _appMasterData.GetProviderByTypeForTenant(providerType, _tenantProvider.TenantId)
            ?? throw new InvalidOperationException(
                $"Payment provider type '{providerType}' is not configured for tenant {_tenantProvider.TenantId}.");
    }
}