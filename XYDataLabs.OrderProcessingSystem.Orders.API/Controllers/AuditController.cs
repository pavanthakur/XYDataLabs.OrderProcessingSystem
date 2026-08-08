using Asp.Versioning;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.Features.Audit.Queries;
using XYDataLabs.OrderProcessingSystem.Orders.API.Extensions;

namespace XYDataLabs.OrderProcessingSystem.Orders.API.Controllers;

[ApiVersion("1.0")]
[Route("api/v{version:apiVersion}/[controller]")]
[ApiController]
[EnableRateLimiting("api-per-tenant")]
public sealed class AuditController : ControllerBase
{
    private readonly IDispatcher _dispatcher;

    public AuditController(IDispatcher dispatcher)
    {
        _dispatcher = dispatcher;
    }

    [HttpGet("{entityName}/{entityId}")]
    public async Task<ActionResult> GetAuditHistory(string entityName, string entityId, CancellationToken cancellationToken)
    {
        var result = await _dispatcher.QueryAsync(new GetAuditHistoryQuery(entityName, entityId), cancellationToken);
        return result.ToActionResult();
    }
}
