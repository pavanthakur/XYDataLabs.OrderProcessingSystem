using System.Reflection;
using FluentAssertions;
using Microsoft.AspNetCore.Mvc;
using NetArchTest.Rules;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

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

    // ------------------------------------------------------------------ Guardrail tests (1.6, 1.7, FC3)

    [Fact]
    public void IgnoreQueryFilters_Usage_Must_Be_In_Allow_List_Only()
    {
        // Allow-list: files that are APPROVED to call IgnoreQueryFilters.
        // Any new usage must be reviewed for tenant-safety and added here explicitly.
        // AppMasterData was removed in ADR-009 — it now respects the scoped tenant query filter.
        var allowList = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
        };

        var solutionRoot = FindSolutionRoot();
        var sourceDirectories = new[]
        {
            Path.Combine(solutionRoot, "XYDataLabs.OrderProcessingSystem.Application"),
            Path.Combine(solutionRoot, "XYDataLabs.OrderProcessingSystem.Infrastructure"),
            Path.Combine(solutionRoot, "XYDataLabs.OrderProcessingSystem.API"),
            Path.Combine(solutionRoot, "XYDataLabs.OrderProcessingSystem.SharedKernel"),
            Path.Combine(solutionRoot, "XYDataLabs.OrderProcessingSystem.Domain"),
            Path.Combine(solutionRoot, "XYDataLabs.OpenPayAdapter"),
        };

        var violations = new List<string>();

        foreach (var dir in sourceDirectories.Where(Directory.Exists))
        {
            foreach (var file in Directory.EnumerateFiles(dir, "*.cs", SearchOption.AllDirectories))
            {
                var fileName = Path.GetFileName(file);
                if (allowList.Contains(fileName))
                    continue;

                var content = File.ReadAllText(file);
                if (content.Contains("IgnoreQueryFilters", StringComparison.Ordinal))
                {
                    violations.Add(Path.GetRelativePath(solutionRoot, file));
                }
            }
        }

        violations.Should().BeEmpty(
            because: "IgnoreQueryFilters bypasses tenant isolation — every usage must be reviewed and added to the allow-list in this test");
    }

    [Fact]
    public void All_CQRS_Handlers_Must_Return_Result_T()
    {
        var resultOpenType = typeof(Result<>);

        // Use direct reflection instead of NetArchTest for open generic matching
        // (NetArchTest's ImplementInterface is unreliable with open generic interfaces)
        var handlerTypes = ApplicationAssembly.GetTypes()
            .Where(t => t.IsClass && !t.IsAbstract)
            .Where(t => t.GetInterfaces().Any(i =>
                i.IsGenericType &&
                (i.GetGenericTypeDefinition() == typeof(Application.CQRS.ICommandHandler<,>) ||
                 i.GetGenericTypeDefinition() == typeof(Application.CQRS.IQueryHandler<,>))))
            .ToList();

        handlerTypes.Should().NotBeEmpty(
            because: "the Application assembly must contain at least one CQRS handler");

        foreach (var handlerType in handlerTypes)
        {
            var handlerInterfaces = handlerType.GetInterfaces()
                .Where(i => i.IsGenericType &&
                           (i.GetGenericTypeDefinition() == typeof(Application.CQRS.ICommandHandler<,>) ||
                            i.GetGenericTypeDefinition() == typeof(Application.CQRS.IQueryHandler<,>)));

            foreach (var iface in handlerInterfaces)
            {
                var resultTypeArg = iface.GetGenericArguments().Last();
                var isResultT = resultTypeArg.IsGenericType &&
                                resultTypeArg.GetGenericTypeDefinition() == resultOpenType;

                isResultT.Should().BeTrue(
                    because: $"{handlerType.Name} must return Result<T> — " +
                             $"currently returns {resultTypeArg.Name}");
            }
        }
    }

    [Fact]
    public void Controllers_Should_Not_Accept_TenantId_Or_TenantCode_Parameters()
    {
        // Tenant context comes from X-Tenant-Code header via middleware.
        // Controllers must never accept TenantId/TenantCode as action parameters or in request DTOs.
        var bannedParameterNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "TenantId", "TenantCode", "TenantExternalId"
        };

        var controllerTypes = ApiAssembly.GetTypes()
            .Where(t => t.IsSubclassOf(typeof(ControllerBase)) && !t.IsAbstract)
            .ToList();

        var violations = new List<string>();

        foreach (var controller in controllerTypes)
        {
            foreach (var method in controller.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly))
            {
                // Check direct action parameters
                foreach (var param in method.GetParameters())
                {
                    if (bannedParameterNames.Contains(param.Name ?? ""))
                    {
                        violations.Add($"{controller.Name}.{method.Name} has parameter '{param.Name}'");
                    }

                    // Check properties of complex request DTO parameters (skip primitives and framework types)
                    if (param.ParameterType.IsClass &&
                        param.ParameterType.Namespace?.StartsWith("XYDataLabs", StringComparison.Ordinal) == true)
                    {
                        foreach (var prop in param.ParameterType.GetProperties())
                        {
                            if (bannedParameterNames.Contains(prop.Name))
                            {
                                violations.Add($"{controller.Name}.{method.Name} DTO '{param.ParameterType.Name}' has property '{prop.Name}'");
                            }
                        }
                    }
                }
            }
        }

        violations.Should().BeEmpty(
            because: "tenant context is resolved from X-Tenant-Code header via middleware — controllers must never accept TenantId, TenantCode, or TenantExternalId as parameters or in request DTOs");
    }

    private static string FindSolutionRoot()
    {
        var dir = AppContext.BaseDirectory;
        while (dir != null)
        {
            if (Directory.GetFiles(dir, "*.sln").Length > 0)
                return dir;
            dir = Directory.GetParent(dir)?.FullName;
        }

        throw new InvalidOperationException("Could not find solution root directory");
    }
}
