using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;

namespace XYDataLabs.OrderProcessingSystem.Orders.API.Controllers;

[ApiController]
[Route("api/v1/admin/dlq")]
[Authorize(Roles = "phase10-operator")]
public sealed class DlqAdminController(
    IDlqReplayApprovalService approvalService,
    ILogger<DlqAdminController> logger) : ControllerBase
{
    [HttpPost("{quarantineId:guid}/approve")]
    [ProducesResponseType<DlqReplayApprovalResult>(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<DlqReplayApprovalResult>> ApproveAsync(
        Guid quarantineId,
        CancellationToken cancellationToken)
    {
        var approvedBy = User.FindFirstValue(ClaimTypes.NameIdentifier)
            ?? User.Identity?.Name
            ?? "unknown";
        var result = await approvalService
            .ApproveAsync(quarantineId, approvedBy, cancellationToken)
            .ConfigureAwait(false);

        if (result is null)
        {
            return NotFound();
        }

        logger.LogInformation(
            "Operator {ApprovedBy} approved quarantine {QuarantineId}; replay request {ReplayRequestId}; already approved {AlreadyApproved}.",
            approvedBy,
            quarantineId,
            result.ReplayRequestId,
            result.AlreadyApproved);
        return Ok(result);
    }
}
