using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

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
    }
}