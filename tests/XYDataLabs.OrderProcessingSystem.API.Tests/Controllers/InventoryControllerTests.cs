using Microsoft.AspNetCore.Mvc;
using Moq;
using XYDataLabs.OrderProcessingSystem.Inventory.API;
using XYDataLabs.OrderProcessingSystem.Inventory.API.Controllers;

namespace XYDataLabs.OrderProcessingSystem.API.Tests.Controllers;

public sealed class InventoryControllerTests
{
    private readonly Mock<IInventoryModuleApi> _inventoryService = new();
    private readonly InventoryController _controller;

    public InventoryControllerTests()
    {
        _controller = new InventoryController(_inventoryService.Object);
    }

    [Fact]
    public async Task GetStockLevelAsync_ReturnsOk_WithInventorySnapshot()
    {
        _inventoryService.Setup(service => service.GetStockLevelAsync("SKU-1")).ReturnsAsync(12);
        _inventoryService.Setup(service => service.CheckStockAsync("SKU-1")).ReturnsAsync(true);

        var result = await _controller.GetStockLevelAsync("SKU-1", CancellationToken.None);

        var ok = Assert.IsType<OkObjectResult>(result.Result);
        var response = Assert.IsType<InventoryController.InventoryStockResponse>(ok.Value);
        Assert.Equal("SKU-1", response.ProductId);
        Assert.Equal(12, response.AvailableQuantity);
        Assert.True(response.IsReservable);
    }

    [Fact]
    public async Task UpdateStockAsync_ReturnsNoContent()
    {
        var result = await _controller.UpdateStockAsync("SKU-2", new InventoryController.InventoryUpdateRequest(5), CancellationToken.None);

        Assert.IsType<NoContentResult>(result);
        _inventoryService.Verify(service => service.UpdateStockAsync("SKU-2", 5), Times.Once);
    }
}

