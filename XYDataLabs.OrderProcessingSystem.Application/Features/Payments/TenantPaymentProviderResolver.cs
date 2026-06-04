using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.Utilities;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Payments;

public sealed class TenantPaymentProviderResolver : ITenantPaymentProviderResolver
{
    private readonly AppMasterData _appMasterData;
    private readonly ITenantProvider _tenantProvider;
    private readonly ITenantRegistry _tenantRegistry;

    public TenantPaymentProviderResolver(
        AppMasterData appMasterData,
        ITenantProvider tenantProvider,
        ITenantRegistry tenantRegistry)
    {
        ArgumentNullException.ThrowIfNull(appMasterData);
        ArgumentNullException.ThrowIfNull(tenantProvider);
        ArgumentNullException.ThrowIfNull(tenantRegistry);

        _appMasterData = appMasterData;
        _tenantProvider = tenantProvider;
        _tenantRegistry = tenantRegistry;
    }

    public PaymentProvider ResolveCurrentTenantProvider()
    {
        var entry = _tenantRegistry.FindByCode(_tenantProvider.TenantCode)
            ?? throw new InvalidOperationException(
                $"Tenant '{_tenantProvider.TenantCode}' was not found in the Tenant Registry.");

        if (string.IsNullOrWhiteSpace(entry.PaymentProviderCode))
            throw new InvalidOperationException(
                $"Tenant '{_tenantProvider.TenantCode}' has no active payment provider configured in the Tenant Registry.");

        return _appMasterData.GetProviderByTypeForTenant(entry.PaymentProviderCode, _tenantProvider.TenantId)
            ?? throw new InvalidOperationException(
                $"Payment provider '{entry.PaymentProviderCode}' configured in the Tenant Registry was not found for tenant {_tenantProvider.TenantId}.");
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