namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;

public interface IPaymentProviderAdapter
{
    string ProviderType { get; }
}