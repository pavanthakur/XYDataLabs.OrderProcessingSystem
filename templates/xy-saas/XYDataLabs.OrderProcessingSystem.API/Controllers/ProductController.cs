using Asp.Versioning;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using XYDataLabs.OrderProcessingSystem.API.Extensions;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.Features.Products.Queries;

namespace XYDataLabs.OrderProcessingSystem.API.Controllers
{
    /// <summary>
    /// Controller to manage product-related operations.
    /// </summary>
    [ApiVersion("1.0")]
    [Route("api/v{version:apiVersion}/[controller]")]
    [ApiController]
    [EnableRateLimiting("api-per-tenant")]
    public class ProductController : ControllerBase
    {
        private readonly IDispatcher _dispatcher;

        public ProductController(IDispatcher dispatcher)
        {
            _dispatcher = dispatcher;
        }

        /// <summary>
        /// Endpoint to retrieve all products.
        /// </summary>
        [HttpGet("GetAllProducts", Name = nameof(GetAllProducts))]
        public async Task<ActionResult> GetAllProducts(CancellationToken cancellationToken)
        {
            var result = await _dispatcher.QueryAsync(new GetAllProductsQuery(), cancellationToken);
            return result.ToActionResult();
        }
    }
}