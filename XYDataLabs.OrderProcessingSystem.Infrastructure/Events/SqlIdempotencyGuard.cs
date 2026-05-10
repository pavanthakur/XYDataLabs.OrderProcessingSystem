using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Events;

public class SqlIdempotencyGuard : IIdempotencyGuard
{
    private readonly OrderProcessingSystemDbContext _dbContext;

    public SqlIdempotencyGuard(OrderProcessingSystemDbContext dbContext)
    {
        _dbContext = dbContext;
    }

    public async Task<bool> HasProcessedAsync(Guid messageId, CancellationToken cancellationToken = default)
    {
        return await _dbContext.InboxMessages
            .AnyAsync(x => x.MessageId == messageId, cancellationToken);
    }

    public async Task MarkProcessedAsync(Guid messageId, CancellationToken cancellationToken = default)
    {
        var inboxMessage = new InboxMessage
        {
            MessageId = messageId,
            EventType = "Processed", // A default label since interface lacks EventType
            ProcessedUtc = DateTime.UtcNow
        };

        _dbContext.InboxMessages.Add(inboxMessage);
        await _dbContext.SaveChangesAsync(cancellationToken);
    }
}
