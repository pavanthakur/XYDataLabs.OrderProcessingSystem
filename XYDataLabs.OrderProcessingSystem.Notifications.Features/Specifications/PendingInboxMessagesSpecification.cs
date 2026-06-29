using System.Linq.Expressions;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Specifications;

namespace XYDataLabs.OrderProcessingSystem.Notifications.Features.Specifications;

public sealed class PendingInboxMessagesSpecification : Specification<InboxMessage>
{
    public override Expression<Func<InboxMessage, bool>> Criteria
        => message => message.Status == InboxMessageStatus.Received || message.Status == InboxMessageStatus.Failed;
}
