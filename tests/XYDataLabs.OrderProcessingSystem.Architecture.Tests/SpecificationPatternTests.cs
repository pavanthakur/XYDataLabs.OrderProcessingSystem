using FluentAssertions;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Specifications;

namespace XYDataLabs.OrderProcessingSystem.Architecture.Tests;

public sealed class SpecificationPatternTests
{
    [Fact]
    public void SharedKernel_Should_Expose_Specification_Primitives_For_All_Modules()
    {
        typeof(ISpecification<>).Assembly.Should().NotBeNull();
        typeof(Specification<>).IsAbstract.Should().BeTrue();
    }
}
