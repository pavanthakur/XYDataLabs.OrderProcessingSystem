using Microsoft.AspNetCore.Mvc;
using Moq;
using XYDataLabs.OrderProcessingSystem.API.Controllers;
using XYDataLabs.OrderProcessingSystem.Notifications.API;

namespace XYDataLabs.OrderProcessingSystem.API.Tests.Controllers;

public sealed class NotificationsControllerTests
{
    private readonly Mock<INotificationsModuleApi> _notificationsService = new();
    private readonly NotificationsController _controller;

    public NotificationsControllerTests()
    {
        _controller = new NotificationsController(_notificationsService.Object);
    }

    [Fact]
    public async Task SendOrderConfirmationAsync_ReturnsNoContent()
    {
        var result = await _controller.SendOrderConfirmationAsync(
            new NotificationsController.SendOrderConfirmationRequest("ORD-1", "Pavan"),
            CancellationToken.None);

        Assert.IsType<NoContentResult>(result);
        _notificationsService.Verify(service => service.SendOrderConfirmationAsync("ORD-1", "Pavan"), Times.Once);
    }

    [Fact]
    public async Task SendShipmentNotificationAsync_ReturnsNoContent()
    {
        var result = await _controller.SendShipmentNotificationAsync(
            new NotificationsController.SendShipmentNotificationRequest("SHP-1", "Pavan"),
            CancellationToken.None);

        Assert.IsType<NoContentResult>(result);
        _notificationsService.Verify(service => service.SendShipmentNotificationAsync("SHP-1", "Pavan"), Times.Once);
    }
}

