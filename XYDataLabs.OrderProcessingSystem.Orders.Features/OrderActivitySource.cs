using System.Diagnostics;

namespace XYDataLabs.OrderProcessingSystem.Orders.Features;

public static class OrderActivitySource
{
    public const string Name = "OrderProcessing.Orders";
    public static readonly ActivitySource Source = new(Name);
}
