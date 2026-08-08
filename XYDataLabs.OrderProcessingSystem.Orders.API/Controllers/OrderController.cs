using Asp.Versioning;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Domain.Identifiers;
using XYDataLabs.OrderProcessingSystem.Orders.Contracts;
using XYDataLabs.OrderProcessingSystem.Orders.API.Extensions;
using XYDataLabs.OrderProcessingSystem.Orders.Features.Commands;
using XYDataLabs.OrderProcessingSystem.Orders.Features.Queries;

namespace XYDataLabs.OrderProcessingSystem.Orders.API.Controllers;

[ApiVersion("1.0")]
[Route("api/v{version:apiVersion}/[controller]")]
[ApiController]
[EnableRateLimiting("api-per-tenant")]
public sealed class OrderController : ControllerBase
{
    private readonly IDispatcher _dispatcher;
    private readonly IOrderModuleApi _orderModuleApi;

    public OrderController(IDispatcher dispatcher, IOrderModuleApi orderModuleApi)
    {
        _dispatcher = dispatcher;
        _orderModuleApi = orderModuleApi;
    }

    [HttpPost]
    [ProducesResponseType(StatusCodes.Status201Created)]
    public async Task<ActionResult> CreateOrder(CreateOrderRequestDto createOrderRequestDto, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(createOrderRequestDto);

        var result = await _dispatcher.SendAsync(
            new CreateOrderCommand(
                new CustomerId(createOrderRequestDto.CustomerId),
                createOrderRequestDto.ProductIds.Select(static productId => new ProductId(productId)).ToArray(),
                createOrderRequestDto.CurrencyCode),
            cancellationToken);
        return result.ToCreatedResult(nameof(GetOrderDetailsById), new { id = result.Value?.OrderId });
    }

    [HttpGet("{id}", Name = nameof(GetOrderDetailsById))]
    public async Task<ActionResult> GetOrderDetailsById(OrderId id, CancellationToken cancellationToken)
    {
        var result = await _dispatcher.QueryAsync(new GetOrderDetailsQuery(id), cancellationToken);
        return result.ToActionResult();
    }

    [HttpGet("/internal/v1/orders/{customerOrderId}/payment-context")]
    [ProducesResponseType<OrderPaymentContextDto>(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<OrderPaymentContextDto>> GetPaymentContext(string customerOrderId, CancellationToken cancellationToken)
    {
        var paymentContext = await _orderModuleApi.GetPaymentContextAsync(customerOrderId, cancellationToken);
        return paymentContext is null ? NotFound() : Ok(paymentContext);
    }

    [HttpGet("/internal/v1/orders/payment-context/{orderReferenceId:guid}")]
    [ProducesResponseType<OrderPaymentContextDto>(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<OrderPaymentContextDto>> GetPaymentContextByOrderReference(Guid orderReferenceId, CancellationToken cancellationToken)
    {
        var paymentContext = await _orderModuleApi.GetPaymentContextByOrderReferenceAsync(orderReferenceId, cancellationToken);
        return paymentContext is null ? NotFound() : Ok(paymentContext);
    }
}
