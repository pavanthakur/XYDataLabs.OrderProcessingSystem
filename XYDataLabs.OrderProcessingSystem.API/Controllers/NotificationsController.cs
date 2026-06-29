using Asp.Versioning;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using XYDataLabs.OrderProcessingSystem.Notifications.API;

namespace XYDataLabs.OrderProcessingSystem.API.Controllers;

[ApiVersion("1.0")]
[ApiController]
[Route("api/v{version:apiVersion}/[controller]")]
[EnableRateLimiting("api-per-tenant")]
public sealed class NotificationsController : ControllerBase
{
    private readonly INotificationsModuleApi _notificationsService;

    public NotificationsController(INotificationsModuleApi notificationsService)
    {
        _notificationsService = notificationsService;
    }

    [HttpPost("order-confirmation")]
    public async Task<IActionResult> SendOrderConfirmationAsync([FromBody] SendOrderConfirmationRequest request, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);

        await _notificationsService.SendOrderConfirmationAsync(request.OrderId, request.CustomerName).ConfigureAwait(false);
        return NoContent();
    }

    [HttpPost("shipment")]
    public async Task<IActionResult> SendShipmentNotificationAsync([FromBody] SendShipmentNotificationRequest request, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);

        await _notificationsService.SendShipmentNotificationAsync(request.ShipmentId, request.RecipientName).ConfigureAwait(false);
        return NoContent();
    }

    public sealed record SendOrderConfirmationRequest(string OrderId, string CustomerName);
    public sealed record SendShipmentNotificationRequest(string ShipmentId, string RecipientName);
}

