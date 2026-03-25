using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure;
using Xunit;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios
{
    [Collection("SqlServer")]
    [Trait("Category", "Integration")]
    public class OrderProcessingScenarioTests : IAsyncLifetime
    {
        private readonly SqlServerFixture _fixture;
        private IntegrationTestWebAppFactory _factory = null!;
        private HttpClient _client = null!;
        private TestTenantContext _tenant = null!;
        private OrderScenarioSeed _scenarioSeed = null!;

        public OrderProcessingScenarioTests(SqlServerFixture fixture)
        {
            _fixture = fixture;
        }

        public async Task InitializeAsync()
        {
            _factory = new IntegrationTestWebAppFactory(_fixture.ConnectionString);
            _client = _factory.CreateClient();
            _tenant = await IntegrationTestData.CreateTenantAsync(_factory);
            _scenarioSeed = await IntegrationTestData.SeedOrderScenarioAsync(_factory, _tenant.TenantId);

            _client.DefaultRequestHeaders.Add(IntegrationTestWebAppFactory.TenantHeaderName, _tenant.TenantCode);
        }

        public async Task DisposeAsync()
        {
            _client.Dispose();
            await _factory.DisposeAsync();
        }

        [Fact]
        public async Task CreateCustomer_ReturnsCreated()
        {
            var request = new CreateCustomerRequestDto
            {
                Name = "Integration Test Customer",
                Email = $"integration-{Guid.NewGuid():N}@test.com"
            };

            var response = await _client.PostAsJsonAsync("/api/v1/Customer", request);

            response.StatusCode.Should().Be(HttpStatusCode.Created);
        }

        [Fact]
        public async Task GetAllCustomers_ReturnsOk()
        {
            var response = await _client.GetAsync("/api/v1/Customer/GetAllCustomers");

            response.StatusCode.Should().Be(HttpStatusCode.OK);
        }

        [Fact]
        public async Task CreateOrder_WithValidCustomer_ReturnsCreated()
        {
            var orderRequest = new CreateOrderRequestDto
            {
                CustomerId = _scenarioSeed.CustomerId,
                ProductIds = new List<int> { _scenarioSeed.ProductId }
            };

            var orderResponse = await _client.PostAsJsonAsync("/api/v1/Order", orderRequest);

            orderResponse.StatusCode.Should().Be(HttpStatusCode.Created);
        }

        [Fact]
        public async Task GetNonExistentCustomer_ReturnsNotFound()
        {
            var response = await _client.GetAsync("/api/v1/Customer/99999");

            response.StatusCode.Should().Be(HttpStatusCode.NotFound);
        }
    }

}
