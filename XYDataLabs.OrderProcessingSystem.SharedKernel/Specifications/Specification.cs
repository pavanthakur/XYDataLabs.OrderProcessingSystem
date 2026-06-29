using System.Linq.Expressions;

namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Specifications;

public abstract class Specification<T> : ISpecification<T>
{
    public abstract Expression<Func<T, bool>> Criteria { get; }
}
