using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Interfaces;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using Microsoft.AspNetCore.Mvc;

namespace XYDataLabs.OrderProcessingSystem.API.Controllers
{
    /// <summary>
    /// Controller to manage order-related operations.
    /// </summary>
    [Route("api/[controller]")]
    [ApiController]
    public class OrderController : ControllerBase
    {
        private readonly IOrderService _orderService;

        /// <summary>
        /// Initializes a new instance of the <see cref="OrderController"/> class.
        /// </summary>
        /// <param name="orderService">The order service.</param>
        public OrderController(IOrderService orderService)
        {
            _orderService = orderService;
        }

        /// <summary>
        /// Endpoint to Create order for a customer
        /// </summary>
        /// <remarks>Create order.</remarks>  
        /// <returns></returns>
        /// <response code="201">Create order</response>
        [HttpPost]
        [ProducesResponseType(StatusCodes.Status201Created)]
        public async Task<ActionResult<OrderDto>> CreateOrder(CreateOrderRequestDto createOrderRequestDto)
        {
            try
            {
                var order = await _orderService.CreateOrderAsync(createOrderRequestDto.CustomerId, createOrderRequestDto.ProductIds);
                return CreatedAtAction(nameof(CreateOrder), new { id = order.OrderId }, order);
            }
            catch (FluentValidation.ValidationException ex)
            {
                return BadRequest(ex.Message);
            }
            catch (KeyNotFoundException ex)
            {
                return NotFound(ex.Message);
            }
        }

        /// <summary>
        /// Endpoint to retrieve details for a specific order, including the total price
        /// </summary>
        /// <remarks>This is the first step to 
        /// retrieve a specific Order</remarks>  
        /// <param name="id">Order id</param>
        /// <returns>Order</returns>
        [HttpGet("{id}", Name = nameof(GetOrderDetailsById))]
        public async Task<ActionResult<OrderDto>> GetOrderDetailsById(int id)
        {
            try
            {
                var order = await _orderService.GetOrderDetailsAsync(id);
                return Ok(order);
            }
            catch (KeyNotFoundException ex)
            {
                return NotFound(ex.Message);
            }
        }
    }
}

