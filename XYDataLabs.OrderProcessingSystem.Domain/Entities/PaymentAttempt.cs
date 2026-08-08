using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using XYDataLabs.OrderProcessingSystem.Domain.Events;

namespace XYDataLabs.OrderProcessingSystem.Domain.Entities
{
    public class PaymentAttempt : BaseAuditableEntity
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int Id { get; set; }

        [Required]
        [MaxLength(128)]
        public string CustomerOrderId { get; set; } = string.Empty;

        [Required]
        [MaxLength(128)]
        public string AttemptOrderId { get; set; } = string.Empty;

        [Required]
        [MaxLength(64)]
        public string PaymentTraceId { get; set; } = string.Empty;

        [Required]
        public int AttemptNumber { get; set; }

        [Required]
        public PaymentAttemptStatus Status { get; set; } = PaymentAttemptStatus.PendingProviderCall;

        [Required]
        [MaxLength(64)]
        public string PaymentProviderName { get; set; } = string.Empty;

        [MaxLength(64)]
        public string? ProviderStatus { get; set; }

        [MaxLength(128)]
        public string? ProviderReferenceId { get; set; }

        [MaxLength(128)]
        public string? ProviderChargeId { get; set; }

        [MaxLength(512)]
        public string? LastErrorMessage { get; set; }

        /// <summary>Optimistic concurrency token. Required because webhook handlers may write concurrent state transitions.</summary>
        public byte[] RowVersion { get; private set; } = Array.Empty<byte>();

        public virtual ICollection<PaymentAttemptHistory> History { get; set; } = new List<PaymentAttemptHistory>();

        /// <summary>
        /// Transitions this attempt to Succeeded and raises a domain event for Outbox propagation.
        /// Idempotent: if already Succeeded, exits without raising a duplicate event.
        /// </summary>
        public void MarkAsSucceeded(string providerName)
        {
            if (Status == PaymentAttemptStatus.Succeeded)
                return;

            Status = PaymentAttemptStatus.Succeeded;
            ProviderStatus = "captured";
            RaiseDomainEvent(new PaymentAttemptSucceededDomainEvent(Id, TenantId, providerName, CustomerOrderId, DateTime.UtcNow));
        }

        /// <summary>
        /// Transitions this attempt to Failed and raises a domain event for Outbox propagation.
        /// Idempotent: if already Failed, exits without raising a duplicate event.
        /// </summary>
        public void MarkAsFailed(string providerName, string? errorReason)
        {
            if (Status == PaymentAttemptStatus.Failed)
                return;

            Status = PaymentAttemptStatus.Failed;
            ProviderStatus = "failed";
            LastErrorMessage = errorReason;
            RaiseDomainEvent(new PaymentAttemptFailedDomainEvent(
                Id,
                TenantId,
                providerName,
                CustomerOrderId,
                errorReason,
                DateTime.UtcNow));
        }
    }
}
