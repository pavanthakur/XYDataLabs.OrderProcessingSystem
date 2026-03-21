using Microsoft.AspNetCore.Mvc;
using XYDataLabs.OrderProcessingSystem.API.Extensions;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Features.Customers.Commands;
using XYDataLabs.OrderProcessingSystem.Application.Features.Customers.Queries;

namespace XYDataLabs.OrderProcessingSystem.API.Controllers
{
    /// <summary>
    /// Controller to manage customer-related operations.
    /// </summary>
    [Route("api/[controller]")]
    [ApiController]
    public class CustomerController : ControllerBase
    {
        private readonly IDispatcher _dispatcher;

        public CustomerController(IDispatcher dispatcher)
        {
            _dispatcher = dispatcher;
        }

        /// <summary>
        /// Endpoint to retrieve all customers
        /// </summary>
        /// <remarks>Retrieve all customers.</remarks>  
        /// <returns></returns>
        /// <response code="200">Returns all customers</response>
        [HttpGet("GetAllCustomers", Name = nameof(GetAllCustomers))]
        public async Task<ActionResult> GetAllCustomers()
        {
            var result = await _dispatcher.QueryAsync(new GetAllCustomersQuery());
            return result.ToActionResult();
        }

        /// <summary>
        /// Endpoint to search customers by name with pagination.
        /// </summary>
        /// <param name="name">Customer name to search for.</param>
        /// <param name="pageNumber">Page number for pagination.</param>
        /// <param name="pageSize">Page size for pagination.</param>
        /// <returns>A list of customers matching the search criteria.</returns>
        [HttpGet("GetAllCustomersByName")]
        public async Task<ActionResult> GetAllCustomersByName(string name, int pageNumber = 1, int pageSize = 10)
        {
            var result = await _dispatcher.QueryAsync(new GetCustomersByNameQuery(name, pageNumber, pageSize));
            return result.ToActionResult();
        }

        /// <summary>
        /// Endpoint to retrieve a specific customer and their orders
        /// </summary>
        /// <param name="id">Customer id</param>
        /// <returns>Customer</returns>
        [HttpGet("{id}", Name = nameof(GetCustomerById))]
        public async Task<ActionResult> GetCustomerById(int id)
        {
            var result = await _dispatcher.QueryAsync(new GetCustomerWithOrdersQuery(id));
            return result.ToActionResult();
        }

        /// <summary>
        /// Endpoint to create a new customer
        /// </summary>
        /// <param name="customerRequestDto">customer</param>
        /// <returns>Customer</returns>
        [HttpPost]
        public async Task<ActionResult> CreateCustomer(CreateCustomerRequestDto customerRequestDto)
        {
            var result = await _dispatcher.SendAsync(new CreateCustomerCommand(customerRequestDto.Name, customerRequestDto.Email));
            return result.ToCreatedResult(nameof(CreateCustomer), new { id = result.Value });
        }

        /// <summary>
        /// Endpoint to update an existing customer
        /// </summary>
        /// <param name="id">Customer id</param>
        /// <param name="customerRequestDto">customer</param>
        /// <returns>Customer</returns>
        [HttpPut("{id}")]
        public async Task<ActionResult> UpdateCustomer(int id, UpdateCustomerRequestDto customerRequestDto)
        {
            var result = await _dispatcher.SendAsync(new UpdateCustomerCommand(id, customerRequestDto.Name, customerRequestDto.Email));
            return result.ToActionResult();
        }

        /// <summary>
        /// Endpoint to delete an existing customer
        /// </summary>
        /// <param name="id">Customer id</param>
        /// <returns>Customer</returns>
        [HttpDelete("{id}")]
        public async Task<ActionResult> DeleteCustomer(int id)
        {
            var result = await _dispatcher.SendAsync(new DeleteCustomerCommand(id));
            return result.ToActionResult();
        }
    }
}