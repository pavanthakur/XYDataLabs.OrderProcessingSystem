using System.Diagnostics;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Payments;

public static class PaymentActivitySource
{
    public const string Name = "OrderProcessing.Payments";
    public static readonly ActivitySource Source = new(Name);
}
