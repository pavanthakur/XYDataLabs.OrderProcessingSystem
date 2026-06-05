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
        await _context.SaveChangesAsync(cancellationToken);

        _logger.LogInformation(
            "Webhook event recorded. InboxMessageId={InboxMessageId} Source={Source} EventType={EventType} ProviderEventId={ProviderEventId} TenantId={TenantId}",
            inboxMessage.Id, command.ProviderName, command.EventType, command.ProviderEventId, tenantId);

        return Result<int>.Success(inboxMessage.Id);
    }
}
