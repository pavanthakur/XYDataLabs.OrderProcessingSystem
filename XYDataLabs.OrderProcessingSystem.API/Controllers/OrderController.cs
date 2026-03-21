using Microsoft.AspNetCore.Mvc;
using XYDataLabs.OrderProcessingSystem.API.Extensions;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Features.Orders.Commands;
using XYDataLabs.OrderProcessingSystem.Application.Features.Orders.Queries;

namespace XYDataLabs.OrderProcessingSystem.API.Controllers
{
    /// <summary>
    /// Controller to manage order-related operations.
    /// </summary>
    [Route("api/[controller]")]
    [ApiController]
    public class OrderController : ControllerBase
    {
        private readonly IDispatcher _dispatcher;

        public OrderController(IDispatcher dispatcher)
        {
            _dispatcher = dispatcher;
        }

        /// <summary>
        /// Endpoint to Create order for a customer
        /// </summary>
        /// <remarks>Create order.</remarks>  
        /// <returns></returns>
        /// <response code="201">Create order</response>
        [HttpPost]
        [ProducesResponseType(StatusCodes.Status201Created)]
        public async Task<ActionResult> CreateOrder(CreateOrderRequestDto createOrderRequestDto)
        {
            var result = await _dispatcher.SendAsync(
                new CreateOrderCommand(createOrderRequestDto.CustomerId, createOrderRequestDto.ProductIds));
            return result.ToCreatedResult(nameof(CreateOrder), new { id = result.Value?.OrderId });
        }

        /// <summary>
        /// Endpoint to retrieve details for a specific order, including the total price
        /// </summary>
        /// <param name="id">Order id</param>
        /// <returns>Order</returns>
        [HttpGet("{id}", Name = nameof(GetOrderDetailsById))]
        public async Task<ActionResult> GetOrderDetailsById(int id)
        {
            var result = await _dispatcher.QueryAsync(new GetOrderDetailsQuery(id));
            return result.ToActionResult();
        }
    }
}

