using Asp.Versioning;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using XYDataLabs.OrderProcessingSystem.Inventory.API;

namespace XYDataLabs.OrderProcessingSystem.API.Controllers;

[ApiVersion("1.0")]
[ApiController]
[Route("api/v{version:apiVersion}/[controller]")]
[EnableRateLimiting("api-per-tenant")]
public sealed class InventoryController : ControllerBase
{
    private readonly IInventoryModuleApi _inventoryService;

    public InventoryController(IInventoryModuleApi inventoryService)
    {
        _inventoryService = inventoryService;
    }

    [HttpGet("{productId}/stock")]
    public async Task<ActionResult<InventoryStockResponse>> GetStockLevelAsync(string productId, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(productId);

        var availableQuantity = await _inventoryService.GetStockLevelAsync(productId).ConfigureAwait(false);
        var isReservable = await _inventoryService.CheckStockAsync(productId).ConfigureAwait(false);

        return Ok(new InventoryStockResponse(productId, availableQuantity, isReservable));
    }

    [HttpPost("{productId}/stock")]
    public async Task<IActionResult> UpdateStockAsync(string productId, [FromBody] InventoryUpdateRequest request, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(productId);
        ArgumentNullException.ThrowIfNull(request);
        ArgumentNullException.ThrowIfNull(request.Quantity);

        await _inventoryService.UpdateStockAsync(productId, request.Quantity.Value).ConfigureAwait(false);
        return NoContent();
    }

    public sealed record InventoryStockResponse(string ProductId, int AvailableQuantity, bool IsReservable);
    public sealed record InventoryUpdateRequest(int? Quantity);
}

