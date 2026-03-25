using System.Diagnostics;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Customers;

public static class CustomerActivitySource
{
    public const string Name = "OrderProcessing.Customers";
    public static readonly ActivitySource Source = new(Name);
}
