using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace XYDataLabs.OrderProcessingSystem.Domain.Entities
{
    public class PaymentAttemptHistory : BaseAuditableCreateEntity
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int Id { get; set; }

        [Required]
        public int PaymentAttemptId { get; set; }

        [Required]
        [MaxLength(128)]
        public string AttemptOrderId { get; set; } = string.Empty;

        [Required]
        public PaymentAttemptStatus Status { get; set; }

        [MaxLength(64)]
        public string? PaymentTraceId { get; set; }

        [MaxLength(64)]
        public string? ProviderStatus { get; set; }

        [MaxLength(512)]
        public string? Notes { get; set; }

        [ForeignKey(nameof(PaymentAttemptId))]
        public virtual PaymentAttempt PaymentAttempt { get; set; } = null!;
    }
}