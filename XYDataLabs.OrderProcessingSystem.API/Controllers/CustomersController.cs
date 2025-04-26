using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Interfaces;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using Microsoft.AspNetCore.Http.HttpResults;
using Microsoft.AspNetCore.Mvc;
using System.Text;

namespace XYDataLabs.OrderProcessingSystem.API.Controllers
{
    /// <summary>
    /// Controller to manage customer-related operations.
    /// </summary>
    [Route("api/[controller]")]
    [ApiController]
    public class CustomerController : ControllerBase
    {
        private readonly ICustomerService _customerService;

        /// <summary>
        /// Initializes a new instance of the <see cref="CustomerController"/> class.
        /// </summary>
        /// <param name="customerService">The customer service.</param>
        public CustomerController(ICustomerService customerService)
        {
            _customerService = customerService;
        }

        /// <summary>
        /// Endpoint to retrieve all customers
        /// </summary>
        /// <remarks>Retrieve all customers.</remarks>  
        /// <returns></returns>
        /// <response code="200">Returns all customers</response>
        [HttpGet("GetAllCustomers", Name = nameof(GetAllCustomers))]
        public async Task<ActionResult<IEnumerable<CustomerDto>>> GetAllCustomers()
        {
            var customers = await _customerService.GetAllCustomersAsync();
            return Ok(customers);
        }

        /// <summary>
        /// Endpoint to search customers by name with pagination.
        /// </summary>
        /// <param name="name">Customer name to search for.</param>
        /// <param name="pageNumber">Page number for pagination.</param>
        /// <param name="pageSize">Page size for pagination.</param>
        /// <returns>A list of customers matching the search criteria.</returns>
        [HttpGet("GetAllCustomersByName")]
        public async Task<ActionResult<IEnumerable<CustomerDto>>> GetAllCustomersByName(string name, int pageNumber = 1, int pageSize = 10)
        {
            var validationErrors = new StringBuilder();

            if (string.IsNullOrWhiteSpace(name))
            {
                validationErrors.AppendLine("Name cannot be empty.");
            }

            if (pageNumber <= 0)
            {
                validationErrors.AppendLine("Page number must be greater than zero.");
            }

            if (pageSize <= 0)
            {
                validationErrors.AppendLine("Page size must be greater than zero.");
            }

            if (validationErrors.Length > 0)
            {
                return BadRequest(validationErrors.ToString());
            }

            var customers = await _customerService.GetAllCustomersByNameAsync(name, pageNumber, pageSize);
            return Ok(customers);
        }

        /// <summary>
        /// Endpoint to verify if exception is getting logged from service class
        /// </summary>
        /// <remarks>This is to test if logs are working in service method.</remarks>  
        /// <returns>BadRequest</returns>
        /// <response code="500">Internal server error</response>
        [HttpGet("VerifyExceptionLoggedInService", Name = nameof(VerifyExceptionLoggedInService))]
        public ActionResult VerifyExceptionLoggedInService()
        {
            _customerService.VerifyExceptionLoggedInService();
            return BadRequest("Customer service thrown some exception please check logs.");
        }

        /// <summary>
        /// Endpoint to retrieve a specific customer and their orders
        /// </summary>
        /// <remarks>This is the first step to 
        /// retrieve a specific customer</remarks>  
        /// <param name="id">Customer id</param>
        /// <returns>Customer</returns>
        [HttpGet("{id}", Name = nameof(GetCustomerById))]
        public async Task<ActionResult<CustomerDto>> GetCustomerById(int id)
        {
            try
            {
                var customer = await _customerService.GetCustomerWithOrdersAsync(id);
                if (customer == null)
                {
                    return NotFound("Customer not found");
                }
                return Ok(customer);
            }
            catch (KeyNotFoundException ex)
            {
                return NotFound(ex.Message);
            }
        }

        /// <summary>
        /// Endpoint to create a new customer
        /// </summary>
        /// <remarks>This is create a new customer</remarks>  
        /// <param name="customerRequestDto">customer</param>
        /// <returns>Customer</returns>
        [HttpPost]
        public async Task<ActionResult> CreateCustomer(CreateCustomerRequestDto customerRequestDto)
        {
            int customerId = await _customerService.CreateCustomerAsync(customerRequestDto);
            if (customerId > 0)
                return CreatedAtAction(nameof(CreateCustomer), new { id = customerId }, "Customer created successfully");
            return StatusCode(500);
        }

        /// <summary>
        /// Endpoint to update an existing customer
        /// </summary>
        /// <remarks>This is to update an existing customer</remarks>  
        /// <param name="id">Customer id</param>
        /// <param name="customerRequestDto">customer</param>
        /// <returns>Customer</returns>
        [HttpPut("{id}")]
        public async Task<ActionResult> UpdateCustomer(int id, UpdateCustomerRequestDto customerRequestDto)
        {
            try
            {
                await _customerService.UpdateCustomerAsync(id, customerRequestDto);
                int customerId = await _customerService.UpdateCustomerAsync(id, customerRequestDto);
                if (customerId == 0)
                {
                    return StatusCode(500, "Error updating customer");
                }
                return Ok(new { id, message = "Customer updated successfully" });
            }
            catch (KeyNotFoundException ex)
            {
                return NotFound(ex.Message);
            }
        }

        /// <summary>
        /// Endpoint to delete an existing customer
        /// </summary>
        /// <remarks>This is to delete an existing customer</remarks>  
        /// <param name="id">Customer id</param>
        /// <returns>Customer</returns>
        [HttpDelete("{id}")]
        public async Task<ActionResult> DeleteCustomer(int id)
        {
            try
            {
                await _customerService.DeleteCustomerAsync(id);
                return Ok(new { id, message = "Customer deleted successfully" });
            }
            catch (KeyNotFoundException ex)
            {
                return NotFound(ex.Message);
            }
        }
    }
}