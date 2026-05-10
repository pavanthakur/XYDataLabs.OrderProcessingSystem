using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using Moq;
using Xunit;
using XYDataLabs.OrderProcessingSystem.API.Controllers;
using XYDataLabs.OrderProcessingSystem.API.Models;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

namespace XYDataLabs.OrderProcessingSystem.API.Tests.Controllers;

public class PaymentsControllerTests
{
    private readonly PaymentsController _controller;

    public PaymentsControllerTests()
    {
        var tenantProvider = new Mock<ITenantProvider>();
        tenantProvider.SetupGet(provider => provider.HasTenantContext).Returns(true);
        tenantProvider.SetupGet(provider => provider.TenantCode).Returns("TenantA");

        _controller = new PaymentsController(
            Mock.Of<IDispatcher>(),
            Mock.Of<ILogger<PaymentsController>>(),
            tenantProvider.Object);
    }

    [Fact]
    public void LogPaymentClientEvent_ReturnsBadRequest_WhenEventNameMissing()
    {
        var result = _controller.LogPaymentClientEvent(new PaymentClientEventRequest());

        Assert.IsType<BadRequestResult>(result);
    }

    [Fact]
    public void LogPaymentClientEvent_ReturnsNoContent_WhenPayloadValid()
    {
        var result = _controller.LogPaymentClientEvent(new PaymentClientEventRequest
        {
            EventName = "ui_payment_completed",
            PaymentId = "pay_123",
            PaymentStatus = "completed"
        });

        Assert.IsType<NoContentResult>(result);
    }
}