using Asp.Versioning;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using XYDataLabs.OrderProcessingSystem.API.Extensions;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.Features.Audit.Queries;

namespace XYDataLabs.OrderProcessingSystem.API.Controllers
{
    [ApiVersion("1.0")]
    [Route("api/v{version:apiVersion}/[controller]")]
    [ApiController]
    [EnableRateLimiting("api-per-tenant")]
    public class AuditController : ControllerBase
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
}