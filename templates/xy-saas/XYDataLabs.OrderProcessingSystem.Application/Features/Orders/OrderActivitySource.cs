using System.Diagnostics;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Orders;

public static class OrderActivitySource
{
    public const string Name = "OrderProcessing.Orders";
    public static readonly ActivitySource Source = new(Name);
}
