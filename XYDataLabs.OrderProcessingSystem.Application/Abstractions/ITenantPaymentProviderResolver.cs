using XYDataLabs.OrderProcessingSystem.Domain.Entities;

namespace XYDataLabs.OrderProcessingSystem.Application.Abstractions;

public interface ITenantPaymentProviderResolver
{
    PaymentProvider ResolveCurrentTenantProvider();

    PaymentProvider ResolveCurrentTenantProvider(string providerType);
}