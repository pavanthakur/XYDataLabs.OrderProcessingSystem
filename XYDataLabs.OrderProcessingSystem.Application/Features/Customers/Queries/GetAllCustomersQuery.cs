using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Customers.Queries;

public sealed record GetAllCustomersQuery : IQuery<Result<IEnumerable<CustomerDto>>>, ICacheable
{
    public string CacheKey => "customers:all";
    public TimeSpan? Expiration => TimeSpan.FromMinutes(5);
}
