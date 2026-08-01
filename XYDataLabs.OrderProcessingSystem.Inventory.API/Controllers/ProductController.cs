using Asp.Versioning;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.Features.Products.Queries;
using XYDataLabs.OrderProcessingSystem.Inventory.API.Extensions;

namespace XYDataLabs.OrderProcessingSystem.Inventory.API.Controllers;

[ApiVersion("1.0")]
[Route("api/v{version:apiVersion}/[controller]")]
[ApiController]
[EnableRateLimiting("api-per-tenant")]
public sealed class ProductController : ControllerBase
{
    private readonly IDispatcher _dispatcher;

    public ProductController(IDispatcher dispatcher)
    {
        _dispatcher = dispatcher;
    }

    [HttpGet("GetAllProducts", Name = nameof(GetAllProducts))]
    public async Task<ActionResult> GetAllProducts(CancellationToken cancellationToken)
    {
        var result = await _dispatcher.QueryAsync(new GetAllProductsQuery(), cancellationToken);
        return result.ToActionResult();
    }
}
