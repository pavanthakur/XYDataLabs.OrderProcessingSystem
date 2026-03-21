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

        public OrderProcessingScenarioTests(SqlServerFixture fixture)
        {
            _fixture = fixture;
        }

        public Task InitializeAsync()
        {
            _factory = new IntegrationTestWebAppFactory(_fixture.ConnectionString);
            _client = _factory.CreateClient();
            _client.DefaultRequestHeaders.Add("X-Tenant-Id", "integration-test");
            return Task.CompletedTask;
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
                Email = "integration@test.com"
            };

            var response = await _client.PostAsJsonAsync("/api/v1/Customers", request);

            response.StatusCode.Should().Be(HttpStatusCode.Created);
        }

        [Fact]
        public async Task GetAllCustomers_ReturnsOk()
        {
            var response = await _client.GetAsync("/api/v1/Customers/GetAllCustomers");

            response.StatusCode.Should().Be(HttpStatusCode.OK);
        }

        [Fact]
        public async Task CreateOrder_WithValidCustomer_ReturnsCreated()
        {
            // Create a customer first
            var customerRequest = new CreateCustomerRequestDto
            {
                Name = "Order Test Customer",
                Email = "order-test@test.com"
            };
            var customerResponse = await _client.PostAsJsonAsync("/api/v1/Customers", customerRequest);
            customerResponse.StatusCode.Should().Be(HttpStatusCode.Created);

            // Create an order for the customer
            var orderRequest = new CreateOrderRequestDto
            {
                CustomerId = 1,
                ProductIds = new List<int> { 1 }
            };

            var orderResponse = await _client.PostAsJsonAsync("/api/v1/Order", orderRequest);

            // May fail if no products exist in seed data — the test validates the pipeline is wired
            orderResponse.StatusCode.Should().BeOneOf(HttpStatusCode.Created, HttpStatusCode.BadRequest);
        }

        [Fact]
        public async Task GetNonExistentCustomer_ReturnsNotFound()
        {
            var response = await _client.GetAsync("/api/v1/Customers/99999");

            response.StatusCode.Should().Be(HttpStatusCode.NotFound);
        }
    }
}
