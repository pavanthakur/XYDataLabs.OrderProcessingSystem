using FluentAssertions;
using FluentValidation;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using System.Text.Json;
using XYDataLabs.OrderProcessingSystem.API.Middleware;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

namespace XYDataLabs.OrderProcessingSystem.API.Tests.Middleware;

public class ErrorHandlingMiddlewareTests
{
    [Fact]
    public async Task InvokeAsync_UnhandledException_ReturnsProblemDetails()
    {
        var middleware = CreateSut(_ => throw new InvalidOperationException("boom"));
        var context = CreateHttpContext();

        await middleware.InvokeAsync(context);

        context.Response.StatusCode.Should().Be(StatusCodes.Status500InternalServerError);
        context.Response.ContentType.Should().Be("application/problem+json");

        var problem = await ReadProblemDetailsAsync(context);
        problem.Title.Should().Be("An unexpected error occurred.");
        problem.Extensions.Should().ContainKey("traceId");
    }

    [Fact]
    public async Task InvokeAsync_TenantContextRequiredException_ReturnsBadRequestProblemDetails()
    {
        var middleware = CreateSut(_ => throw new TenantContextRequiredException("CreateOrderCommand"));
        var context = CreateHttpContext();

        await middleware.InvokeAsync(context);

        context.Response.StatusCode.Should().Be(StatusCodes.Status400BadRequest);

        var problem = await ReadProblemDetailsAsync(context);
        problem.Title.Should().Be("Tenant context is required.");
        problem.Extensions.Should().ContainKey("requestName");
        problem.Extensions["requestName"]?.ToString().Should().Be("CreateOrderCommand");
    }

    [Fact]
    public async Task InvokeAsync_ValidationException_ReturnsValidationProblemDetails()
    {
        var failures = new[]
        {
            new FluentValidation.Results.ValidationFailure("Name", "Name is required.")
        };

        var middleware = CreateSut(_ => throw new ValidationException(failures));
        var context = CreateHttpContext();

        await middleware.InvokeAsync(context);

        context.Response.StatusCode.Should().Be(StatusCodes.Status400BadRequest);

        var validationProblem = await ReadValidationProblemDetailsAsync(context);
        validationProblem.Errors.Should().ContainKey("Name");
    }

    private static ErrorHandlingMiddleware CreateSut(RequestDelegate next)
    {
        return new ErrorHandlingMiddleware(next, NullLogger<ErrorHandlingMiddleware>.Instance);
    }

    private static DefaultHttpContext CreateHttpContext()
    {
        var context = new DefaultHttpContext();
        context.Response.Body = new MemoryStream();
        context.RequestServices = new ServiceCollection().BuildServiceProvider();
        context.Request.Path = "/api/v1/orders";
        return context;
    }

    private static async Task<ProblemDetails> ReadProblemDetailsAsync(DefaultHttpContext context)
    {
        context.Response.Body.Position = 0;
        return (await JsonSerializer.DeserializeAsync<ProblemDetails>(context.Response.Body, new JsonSerializerOptions(JsonSerializerDefaults.Web)))!;
    }

    private static async Task<ValidationProblemDetails> ReadValidationProblemDetailsAsync(DefaultHttpContext context)
    {
        context.Response.Body.Position = 0;
        return (await JsonSerializer.DeserializeAsync<ValidationProblemDetails>(context.Response.Body, new JsonSerializerOptions(JsonSerializerDefaults.Web)))!;
    }
}