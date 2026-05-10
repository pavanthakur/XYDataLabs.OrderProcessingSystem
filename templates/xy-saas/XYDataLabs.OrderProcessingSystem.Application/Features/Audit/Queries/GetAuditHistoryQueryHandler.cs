using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Audit.Queries;

public sealed class GetAuditHistoryQueryHandler : IQueryHandler<GetAuditHistoryQuery, Result<IEnumerable<AuditLogDto>>>
{
    private readonly IAppDbContext _context;

    public GetAuditHistoryQueryHandler(IAppDbContext context)
    {
        _context = context;
    }

    public async Task<Result<IEnumerable<AuditLogDto>>> HandleAsync(GetAuditHistoryQuery query, CancellationToken cancellationToken = default)
    {
        var entityName = query.EntityName?.Trim();
        var entityId = query.EntityId?.Trim();

        if (string.IsNullOrWhiteSpace(entityName) || string.IsNullOrWhiteSpace(entityId))
        {
            return Result<IEnumerable<AuditLogDto>>.Failure(Error.Validation);
        }

        var auditHistory = await _context.AuditLogs
            .AsNoTracking()
            .Where(auditLog => auditLog.EntityName == entityName && auditLog.EntityId == entityId)
            .OrderByDescending(auditLog => auditLog.CreatedDate)
            .Select(auditLog => new AuditLogDto
            {
                EntityName = auditLog.EntityName,
                EntityId = auditLog.EntityId,
                Operation = auditLog.Operation,
                ChangedAt = auditLog.CreatedDate,
                TraceId = auditLog.TraceId,
                CorrelationId = auditLog.CorrelationId,
                OldValues = auditLog.OldValues,
                NewValues = auditLog.NewValues
            })
            .ToListAsync(cancellationToken);

        return Result<IEnumerable<AuditLogDto>>.Success(auditHistory);
    }
}