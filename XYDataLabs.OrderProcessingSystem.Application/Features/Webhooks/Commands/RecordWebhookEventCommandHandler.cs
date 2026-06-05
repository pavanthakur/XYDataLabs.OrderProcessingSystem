using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Webhooks.Commands;

public sealed class RecordWebhookEventCommandHandler : ICommandHandler<RecordWebhookEventCommand, Result<int>>
{
    private readonly IAppDbContext _context;
    private readonly ITenantProvider _tenantProvider;
    private readonly ILogger<RecordWebhookEventCommandHandler> _logger;

    public RecordWebhookEventCommandHandler(
        IAppDbContext context,
        ITenantProvider tenantProvider,
        ILogger<RecordWebhookEventCommandHandler> logger)
    {
        ArgumentNullException.ThrowIfNull(context);
        ArgumentNullException.ThrowIfNull(tenantProvider);
        ArgumentNullException.ThrowIfNull(logger);

        _context = context;
        _tenantProvider = tenantProvider;
        _logger = logger;
    }

    public async Task<Result<int>> HandleAsync(RecordWebhookEventCommand command, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(command);

        var tenantId = _tenantProvider.TenantId;

        var inboxMessage = new InboxMessage
        {
            MessageId = Guid.NewGuid(),
            ProviderEventId = command.ProviderEventId,
            Source = command.ProviderName,
            EventType = command.EventType,
            Payload = command.RawPayload,
            SchemaVersion = command.SchemaVersion,
            Status = InboxMessageStatus.Received,
            TenantId = tenantId,
            CreatedDate = DateTime.UtcNow
        };

        _context.InboxMessages.Add(inboxMessage);

        try
        {
            await _context.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateException ex) when (IsDuplicateKeyException(ex))
        {
            // DB-level unique constraint on (TenantId, ProviderEventId) fired — event already recorded.
            // Return the existing row's id would require a second query; returning 0 signals dedup to the caller.
            // The controller still returns 202 — the event is considered durably received.
            _logger.LogInformation(
                "Webhook event already recorded (duplicate key). Source={Source} EventType={EventType} ProviderEventId={ProviderEventId} TenantId={TenantId}",
                command.ProviderName, command.EventType, command.ProviderEventId, tenantId);
            return Result<int>.Success(0);
        }

        _logger.LogInformation(
            "Webhook event recorded. InboxMessageId={InboxMessageId} Source={Source} EventType={EventType} ProviderEventId={ProviderEventId} TenantId={TenantId}",
            inboxMessage.Id, command.ProviderName, command.EventType, command.ProviderEventId, tenantId);

        return Result<int>.Success(inboxMessage.Id);
    }

    private static bool IsDuplicateKeyException(DbUpdateException ex) =>
        ex.InnerException?.Message.Contains("IX_InboxMessages_TenantId_ProviderEventId",
            StringComparison.OrdinalIgnoreCase) == true
        || ex.InnerException?.Message.Contains("duplicate key", StringComparison.OrdinalIgnoreCase) == true
           && ex.InnerException.Message.Contains("InboxMessages", StringComparison.OrdinalIgnoreCase);
}
