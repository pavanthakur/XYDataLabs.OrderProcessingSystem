namespace XYDataLabs.OrderProcessingSystem.Domain.Entities
{
    public enum InboxMessageStatus
    {
        /// <summary>Durably persisted; not yet picked up by a processor.</summary>
        Received,

        /// <summary>Claimed by a processor; lock is held.</summary>
        Processing,

        /// <summary>Processed successfully.</summary>
        Processed,

        /// <summary>All retry attempts exhausted; moved to dead state.</summary>
        Failed
    }
}
