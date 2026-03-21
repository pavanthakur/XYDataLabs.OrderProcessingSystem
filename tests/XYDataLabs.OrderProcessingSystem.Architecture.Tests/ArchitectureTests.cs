using System.Reflection;
using FluentAssertions;
using NetArchTest.Rules;

namespace XYDataLabs.OrderProcessingSystem.Architecture.Tests;

/// <summary>
/// Enforces Clean Architecture layer boundaries as defined in clean-architecture.instructions.md.
/// Dependency flow: Domain → Application → Infrastructure → API (SharedKernel is cross-cutting).
/// </summary>
public class ArchitectureTests
{
    // Assembly references for type scanning
    private static readonly Assembly DomainAssembly =
        typeof(Domain.Entities.Order).Assembly;

    private static readonly Assembly ApplicationAssembly =
        typeof(Application.StartupHelper).Assembly;

    private static readonly Assembly InfrastructureAssembly =
        typeof(Infrastructure.DataContext.OrderProcessingSystemDbContext).Assembly;

    private static readonly Assembly ApiAssembly =
        typeof(API.Controllers.OrderController).Assembly;

    private static readonly Assembly SharedKernelAssembly =
        typeof(SharedKernel.Results.Result<>).Assembly;

    // Namespace constants
    private const string DomainNamespace = "XYDataLabs.OrderProcessingSystem.Domain";
    private const string ApplicationNamespace = "XYDataLabs.OrderProcessingSystem.Application";
    private const string InfrastructureNamespace = "XYDataLabs.OrderProcessingSystem.Infrastructure";
    private const string ApiNamespace = "XYDataLabs.OrderProcessingSystem.API";

    [Fact]
    public void Domain_Should_Not_Depend_On_Application()
    {
        var result = Types.InAssembly(DomainAssembly)
            .ShouldNot()
            .HaveDependencyOn(ApplicationNamespace)
            .GetResult();

        result.IsSuccessful.Should().BeTrue(
            because: "Domain layer must have zero dependencies on Application layer");
    }

    [Fact]
    public void Domain_Should_Not_Depend_On_Infrastructure()
    {
        var result = Types.InAssembly(DomainAssembly)
            .ShouldNot()
            .HaveDependencyOn(InfrastructureNamespace)
            .GetResult();

        result.IsSuccessful.Should().BeTrue(
            because: "Domain layer must have zero dependencies on Infrastructure layer");
    }

    [Fact]
    public void Domain_Should_Not_Depend_On_API()
    {
        var result = Types.InAssembly(DomainAssembly)
            .ShouldNot()
            .HaveDependencyOn(ApiNamespace)
            .GetResult();

        result.IsSuccessful.Should().BeTrue(
            because: "Domain layer must have zero dependencies on API layer");
    }

    [Fact]
    public void Application_Should_Not_Depend_On_Infrastructure()
    {
        var result = Types.InAssembly(ApplicationAssembly)
            .ShouldNot()
            .HaveDependencyOn(InfrastructureNamespace)
            .GetResult();

        result.IsSuccessful.Should().BeTrue(
            because: "Application layer must never reference Infrastructure — use IAppDbContext abstraction");
    }

    [Fact]
    public void Application_Should_Not_Depend_On_API()
    {
        var result = Types.InAssembly(ApplicationAssembly)
            .ShouldNot()
            .HaveDependencyOn(ApiNamespace)
            .GetResult();

        result.IsSuccessful.Should().BeTrue(
            because: "Application layer must never reference API/Presentation layer");
    }

    [Fact]
    public void Infrastructure_Should_Not_Depend_On_API()
    {
        var result = Types.InAssembly(InfrastructureAssembly)
            .ShouldNot()
            .HaveDependencyOn(ApiNamespace)
            .GetResult();

        result.IsSuccessful.Should().BeTrue(
            because: "Infrastructure layer must never reference API/Presentation layer");
    }

    [Fact]
    public void SharedKernel_Should_Not_Depend_On_Domain()
    {
        var result = Types.InAssembly(SharedKernelAssembly)
            .ShouldNot()
            .HaveDependencyOn(DomainNamespace)
            .GetResult();

        result.IsSuccessful.Should().BeTrue(
            because: "SharedKernel is cross-cutting — must not depend on Domain business logic");
    }

    [Fact]
    public void SharedKernel_Should_Not_Depend_On_Application()
    {
        var result = Types.InAssembly(SharedKernelAssembly)
            .ShouldNot()
            .HaveDependencyOn(ApplicationNamespace)
            .GetResult();

        result.IsSuccessful.Should().BeTrue(
            because: "SharedKernel is cross-cutting — must not depend on Application layer");
    }

    [Fact]
    public void SharedKernel_Should_Not_Depend_On_Infrastructure()
    {
        var result = Types.InAssembly(SharedKernelAssembly)
            .ShouldNot()
            .HaveDependencyOn(InfrastructureNamespace)
            .GetResult();

        result.IsSuccessful.Should().BeTrue(
            because: "SharedKernel is cross-cutting — must not depend on Infrastructure layer");
    }

    [Fact]
    public void SharedKernel_Should_Not_Depend_On_API()
    {
        var result = Types.InAssembly(SharedKernelAssembly)
            .ShouldNot()
            .HaveDependencyOn(ApiNamespace)
            .GetResult();

        result.IsSuccessful.Should().BeTrue(
            because: "SharedKernel is cross-cutting — must not depend on API layer");
    }

    [Fact]
    public void Controllers_Should_Not_Depend_On_Infrastructure()
    {
        var result = Types.InAssembly(ApiAssembly)
            .That()
            .ResideInNamespace("XYDataLabs.OrderProcessingSystem.API.Controllers")
            .ShouldNot()
            .HaveDependencyOn(InfrastructureNamespace)
            .GetResult();

        result.IsSuccessful.Should().BeTrue(
            because: "Controllers must be thin — delegate to CQRS dispatcher or service interfaces, never reference Infrastructure directly");
    }
}
