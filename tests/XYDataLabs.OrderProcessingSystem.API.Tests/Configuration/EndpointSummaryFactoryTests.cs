using FluentAssertions;
using XYDataLabs.OrderProcessingSystem.API.Responses;

namespace XYDataLabs.OrderProcessingSystem.API.Tests.Configuration;

public sealed class EndpointSummaryFactoryTests
{
    [Fact]
    public void BuildHealthSummary_IncludesAcceptedHostAndSummary()
    {
        var result = EndpointSummaryFactory.BuildHealthSummary("orderprocessing-gate-dev.bluebay-335bed8c.centralindia.azurecontainerapps.io");

        result["service"].Should().Be("XYDataLabs.OrderProcessingSystem.Gateway");
        result["status"].Should().Be("healthy");
        result["acceptedHost"].Should().Be("orderprocessing-gate-dev.bluebay-335bed8c.centralindia.azurecontainerapps.io");
        result["summary"].Should().Be("Accepted host: orderprocessing-gate-dev.bluebay-335bed8c.centralindia.azurecontainerapps.io");
        result["routes"].Should().NotBeNull();
    }

    [Fact]
    public void BuildSwaggerUnavailableSummary_IncludesAcceptedHostAndSwaggerLocation()
    {
        var result = EndpointSummaryFactory.BuildSwaggerUnavailableSummary(
            "Production",
            "orderprocessing-api-dev.bluebay-335bed8c.centralindia.azurecontainerapps.io",
            "https://orderprocessing-api-dev.bluebay-335bed8c.centralindia.azurecontainerapps.io/swagger");

        result["environment"].Should().Be("Production");
        result["acceptedHost"].Should().Be("orderprocessing-api-dev.bluebay-335bed8c.centralindia.azurecontainerapps.io");
        result["summary"].Should().Be("Accepted host: orderprocessing-api-dev.bluebay-335bed8c.centralindia.azurecontainerapps.io");
        result["swaggerAvailableAt"].Should().Be("https://orderprocessing-api-dev.bluebay-335bed8c.centralindia.azurecontainerapps.io/swagger");
    }
}
