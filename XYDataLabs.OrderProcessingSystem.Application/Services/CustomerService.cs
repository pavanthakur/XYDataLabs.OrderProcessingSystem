using AutoMapper;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Interfaces;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace XYDataLabs.OrderProcessingSystem.Application.Services
{
    public class CustomerService : ICustomerService
    {
        private readonly OrderProcessingSystemDbContext _context;
        private readonly ILogger<CustomerService> _logger;
        private readonly IMapper _autoMapper;

        public CustomerService(OrderProcessingSystemDbContext context, ILogger<CustomerService> logger, IMapper autoMapper)
        {
            _context = context;
            _logger = logger;
            _autoMapper = autoMapper;
        }

        // Retrieve all customers
        public async Task<IEnumerable<CustomerDto>> GetAllCustomersAsync()
        {
            var customers = await _context.Customers.ToListAsync();
            return _autoMapper.Map<IEnumerable<CustomerDto>>(customers);
        }

        public async Task<IEnumerable<CustomerDto>> GetAllCustomersByNameAsync(string name, int pageNumber, int pageSize)
        {
            var customers = await _context.Customers.ToListAsync();
            var query = customers.AsQueryable();

            if (!string.IsNullOrEmpty(name))
            {
                query = query.Where(c => c.Name.Contains(name, StringComparison.OrdinalIgnoreCase));
            }

            var totalCount = query.Count();
            var filteredCustomers = query.Skip((pageNumber - 1) * pageSize).Take(pageSize).ToList();

            return _autoMapper.Map<IEnumerable<CustomerDto>>(filteredCustomers);
        }

        // Get Customer by Id
        public async Task<CustomerDto?> GetCustomerByIdAsync(int id)
        {
            var customer = await _context.Customers.FindAsync(id);
            if (customer == null)
            {
                return null;
            }
            return _autoMapper.Map<CustomerDto>(customer);
        }

        // Verify Exception Logged In Service
        public void VerifyExceptionLoggedInService()
        {
            _logger.LogInformation("Executing VerifyExceptionLoggedInService...");
            try
            {
                // Your business logic
                throw new Exception("Test exception to verify ErrorHandlingMiddleware is working");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "An error occurred while executing VerifyExceptionLoggedInService.");
                throw;  // Re-throw the exception after logging
            }
        }

        // Retrieve a specific customer with their orders
        public async Task<CustomerDto> GetCustomerWithOrdersAsync(int customerId)
        {
            var customer = await _context.Customers
                .Include(c => c.Orders)
                .FirstOrDefaultAsync(c => c.CustomerId == customerId);

            if (customer == null)
                throw new KeyNotFoundException($"Customer with ID {customerId} not found.");

            return _autoMapper.Map<CustomerDto>(customer);
        }

        // Create a new customer
        public async Task<int> CreateCustomerAsync(CreateCustomerRequestDto customerRequestDto)
        {
            var customer = _autoMapper.Map<CreateCustomerRequestDto, Customer>(customerRequestDto);
            _context.Customers.Add(customer);
            if (await _context.SaveChangesAsync() > 0)
                return customer.CustomerId;
            return 0;
        }

        // Update an existing customer
        public async Task<int> UpdateCustomerAsync(int customerId, UpdateCustomerRequestDto customerDto)
        {
            var customer = await _context.Customers.FindAsync(customerId);
            if (customer == null)
            {
                return 0;
            }

            _autoMapper.Map(customerDto, customer);
            _context.Customers.Update(customer);
            await _context.SaveChangesAsync();
            return customer.CustomerId;
        }

        // Delete a customer
        public async Task DeleteCustomerAsync(int customerId)
        {
            var customer = await _context.Customers.FindAsync(customerId);
            if (customer == null)
            {
                throw new KeyNotFoundException($"Customer with ID {customerId} not found.");
            }

            _context.Customers.Remove(customer);
            await _context.SaveChangesAsync();
        }
    }
}
