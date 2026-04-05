using FluentAssertions;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Domain.Identifiers;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Validator;
using XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

[Collection("SqlServer")]
[Trait("Category", "Integration")]
public sealed class OrderValidatorTests : IAsyncLifetime
{
    private readonly SqlServerFixture _fixture;
    private IntegrationTestWebAppFactory _factory = null!;
    private TestTenantContext _tenant = null!;

    public OrderValidatorTests(SqlServerFixture fixture)
    {
        _fixture = fixture;
    }

    public async Task InitializeAsync()
    {
        _factory = new IntegrationTestWebAppFactory(_fixture.ConnectionString);
        _tenant = await IntegrationTestData.CreateTenantAsync(_factory);
    }

    public async Task DisposeAsync()
    {
        await _factory.DisposeAsync();
    }

    [Fact]
    public async Task ValidateAsync_Should_Fail_When_TotalPriceValue_Is_Not_Greater_Than_Zero()
    {
        await _factory.ExecuteDbContextAsync(async dbContext =>
        {
            var validator = new OrderValidator(dbContext);
            var order = (Order)Activator.CreateInstance(typeof(Order), nonPublic: true)!;

            var validationResult = await validator.ValidateAsync(order);

            validationResult.IsValid.Should().BeFalse();
            validationResult.Errors.Should().ContainSingle(error =>
                error.PropertyName == "TotalPrice.Value"
                && error.ErrorMessage == "Order total must be greater than zero.");
        });
    }

    [Fact]
    public async Task ValidateAsync_Should_Pass_When_TotalPriceValue_Is_Positive()
    {
        var seed = await IntegrationTestData.SeedOrderScenarioAsync(_factory, _tenant.TenantId);

        await _factory.ExecuteDbContextAsync(async dbContext =>
        {
            var customer = await dbContext.Customers.FindAsync([new CustomerId(seed.CustomerId)]);
            var product = await dbContext.Products.FindAsync([new ProductId(seed.ProductId)]);

            customer.Should().NotBeNull();
            product.Should().NotBeNull();

            var orderResult = Order.Create(customer!.CustomerId, new[] { product! }, DateTime.UtcNow);
            orderResult.IsSuccess.Should().BeTrue();
            orderResult.Value.Should().NotBeNull();

            var validator = new OrderValidator(dbContext);
            var validationResult = await validator.ValidateAsync(orderResult.Value!);

            validationResult.IsValid.Should().BeTrue();
        });
    }
}