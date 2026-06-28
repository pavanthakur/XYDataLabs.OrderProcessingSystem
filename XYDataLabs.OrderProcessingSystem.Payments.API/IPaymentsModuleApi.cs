namespace XYDataLabs.OrderProcessingSystem.Payments.API;

public interface IPaymentsModuleApi
{
    Task<bool> AuthorizePaymentAsync(string orderId, decimal amount);

    Task<bool> CapturePaymentAsync(string paymentId, decimal amount);
}

