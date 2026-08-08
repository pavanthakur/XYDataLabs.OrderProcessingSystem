using Asp.Versioning;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Features.Customers.Commands;
using XYDataLabs.OrderProcessingSystem.Application.Features.Customers.Queries;
using XYDataLabs.OrderProcessingSystem.Domain.Identifiers;
using XYDataLabs.OrderProcessingSystem.Orders.API.Extensions;

namespace XYDataLabs.OrderProcessingSystem.Orders.API.Controllers;

[ApiVersion("1.0")]
[Route("api/v{version:apiVersion}/[controller]")]
[ApiController]
[EnableRateLimiting("api-per-tenant")]
public sealed class CustomerController : ControllerBase
{
    private readonly IDispatcher _dispatcher;

    public CustomerController(IDispatcher dispatcher)
    {
        _dispatcher = dispatcher;
    }

    [HttpGet("GetAllCustomers", Name = nameof(GetAllCustomers))]
    public async Task<ActionResult> GetAllCustomers(CancellationToken cancellationToken)
    {
        var result = await _dispatcher.QueryAsync(new GetAllCustomersQuery(), cancellationToken);
        return result.ToActionResult();
    }

    [HttpGet("GetAllCustomersByName")]
    public async Task<ActionResult> GetAllCustomersByName(
        string name,
        int pageNumber = 1,
        int pageSize = 10,
        CancellationToken cancellationToken = default)
    {
        var result = await _dispatcher.QueryAsync(
            new GetCustomersByNameQuery(name, pageNumber, pageSize),
            cancellationToken);
        return result.ToActionResult();
    }

    [HttpGet("{id}", Name = nameof(GetCustomerById))]
    public async Task<ActionResult> GetCustomerById(CustomerId id, CancellationToken cancellationToken)
    {
        var result = await _dispatcher.QueryAsync(new GetCustomerWithOrdersQuery(id), cancellationToken);
        return result.ToActionResult();
    }

    [HttpPost]
    public async Task<ActionResult> CreateCustomer(CreateCustomerRequestDto customerRequestDto, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(customerRequestDto);

        var result = await _dispatcher.SendAsync(
            new CreateCustomerCommand(customerRequestDto.Name, customerRequestDto.Email),
            cancellationToken);
        return result.ToCreatedResult(nameof(CreateCustomer), new { id = result.Value });
    }

    [HttpPut("{id}")]
    public async Task<ActionResult> UpdateCustomer(
        CustomerId id,
        UpdateCustomerRequestDto customerRequestDto,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(customerRequestDto);

        var result = await _dispatcher.SendAsync(
            new UpdateCustomerCommand(id, customerRequestDto.Name, customerRequestDto.Email),
            cancellationToken);
        return result.ToActionResult();
    }

    [HttpDelete("{id}")]
    public async Task<ActionResult> DeleteCustomer(CustomerId id, CancellationToken cancellationToken)
    {
        var result = await _dispatcher.SendAsync(new DeleteCustomerCommand(id), cancellationToken);
        return result.ToActionResult();
    }
}
