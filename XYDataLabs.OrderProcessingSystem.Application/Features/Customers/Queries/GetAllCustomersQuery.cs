using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Customers.Queries;

// Includes mutable order/payment state. Read authoritative data until this query
// has tenant-scoped invalidation for all customer, order and payment mutations.
public sealed record GetAllCustomersQuery : IQuery<Result<IEnumerable<CustomerDto>>>;
