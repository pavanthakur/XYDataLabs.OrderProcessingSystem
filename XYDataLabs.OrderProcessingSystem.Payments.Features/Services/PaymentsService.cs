using XYDataLabs.OrderProcessingSystem.Payments.API;

namespace XYDataLabs.OrderProcessingSystem.Payments.Features.Services
{
    public sealed class PaymentsService : IPaymentsModuleApi
    {
        public Task<bool> AuthorizePaymentAsync(string orderId, decimal amount)
        {
            ArgumentException.ThrowIfNullOrWhiteSpace(orderId);
            ArgumentOutOfRangeException.ThrowIfNegativeOrZero(amount);
            return Task.FromResult(true);
        }

        public Task<bool> CapturePaymentAsync(string paymentId, decimal amount)
        {
            ArgumentException.ThrowIfNullOrWhiteSpace(paymentId);
            ArgumentOutOfRangeException.ThrowIfNegativeOrZero(amount);
            return Task.FromResult(true);
        }
    }
}

