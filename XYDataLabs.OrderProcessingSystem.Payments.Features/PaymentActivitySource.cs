using System.Diagnostics;

namespace XYDataLabs.OrderProcessingSystem.Payments.Features;

public static class PaymentActivitySource
{
    public const string Name = "OrderProcessing.Payments";
    public static readonly ActivitySource Source = new(Name);
}
