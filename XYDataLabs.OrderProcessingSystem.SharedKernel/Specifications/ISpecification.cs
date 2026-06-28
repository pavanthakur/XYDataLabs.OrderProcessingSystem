using System.Linq.Expressions;

namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Specifications;

public interface ISpecification<T>
{
    Expression<Func<T, bool>> Criteria { get; }
}
