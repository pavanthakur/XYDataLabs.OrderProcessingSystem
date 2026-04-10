using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using Moq;
using Xunit;
using XYDataLabs.OrderProcessingSystem.API.Controllers;
using XYDataLabs.OrderProcessingSystem.API.Models;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;

namespace XYDataLabs.OrderProcessingSystem.API.Tests.Controllers;

public class PaymentsControllerTests
{
    private readonly PaymentsController _controller;

    public PaymentsControllerTests()
    {
        _controller = new PaymentsController(
            Mock.Of<IDispatcher>(),
            Mock.Of<ILogger<PaymentsController>>());
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
            TenantCode = "TenantA",
            PaymentId = "pay_123",
            PaymentStatus = "completed"
        });

        Assert.IsType<NoContentResult>(result);
    }
}