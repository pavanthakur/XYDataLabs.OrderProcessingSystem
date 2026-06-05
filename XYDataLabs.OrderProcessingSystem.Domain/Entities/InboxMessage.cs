using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace XYDataLabs.OrderProcessingSystem.Domain.Entities
{
    public class InboxMessage : BaseAuditableCreateEntity
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int Id { get; set; }

        /// <summary>Stable identity assigned by this system. Used for deduplication alongside ProviderEventId.</summary>
        [Required]
        public Guid MessageId { get; set; }

        /// <summary>Stable event identity from the provider (e.g. Razorpay payment_id, OpenPay transaction id). Used for inbox deduplication.</summary>
        [Required]
        [MaxLength(256)]
        public string ProviderEventId { get; set; } = string.Empty;

        /// <summary>Provider name that delivered the webhook (e.g. "Razorpay", "OpenPay").</summary>
        [Required]
        [MaxLength(128)]
        public string Source { get; set; } = string.Empty;

        /// <summary>Provider event category (e.g. "payment.captured", "refund.processed").</summary>
        [Required]
        [MaxLength(256)]
        public string EventType { get; set; } = string.Empty;

        /// <summary>Raw JSON payload as received — preserved for replay and audit. HMAC was validated before this was persisted.</summary>
        [Required]
        public string Payload { get; set; } = string.Empty;

        /// <summary>Schema version of the payload contract. Incremented when the handler mapping changes in a breaking way.</summary>
        [Required]
        public int SchemaVersion { get; set; } = 1;

        /// <summary>Current processing state.</summary>
        [Required]
        public InboxMessageStatus Status { get; set; } = InboxMessageStatus.Received;

        /// <summary>Number of processing attempts made so far.</summary>
        public int ProcessingAttempts { get; set; }

        /// <summary>Distributed lock expiry. Set by a processor when it claims this message; cleared on completion or failure.</summary>
        public DateTime? LockExpiry { get; set; }

        /// <summary>Error detail from the last failed processing attempt.</summary>
        [MaxLength(1024)]
        public string? LastError { get; set; }

        /// <summary>UTC timestamp when this message was successfully processed. Null until Status = Processed.</summary>
        public DateTime? ProcessedUtc { get; set; }
    }
}
