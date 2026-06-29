using System.Linq.Expressions;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Specifications;

namespace XYDataLabs.OrderProcessingSystem.Orders.Features.Specifications;

public sealed class CustomerHasOpenOrderSpecification : Specification<Customer>
{
    public override Expression<Func<Customer, bool>> Criteria => customer => customer.Orders.Any(order => !order.IsClosed);
}
