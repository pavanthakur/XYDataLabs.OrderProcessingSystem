using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Audit.Queries;

public sealed record GetAuditHistoryQuery(string EntityName, string EntityId) : IQuery<Result<IEnumerable<AuditLogDto>>>;