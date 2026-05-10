using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace XYDataLabs.OrderProcessingSystem.Domain.Entities
{
    public class TransactionStatusHistory : BaseAuditableEntity
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int Id { get; set; }

        [Required]
        public int TransactionId { get; set; }

        [MaxLength(128)]
        public string? AttemptOrderId { get; set; }

        [Required]
        [MaxLength(50)]
        public string Status { get; set; } = string.Empty;

        [MaxLength(255)]
        public string? Notes { get; set; }

        [MaxLength(64)]
        public string? PaymentTraceId { get; set; }

        [MaxLength(64)]
        public string? ThreeDSecureStage { get; set; }

        public bool IsThreeDSecureEnabled { get; set; }

        [MaxLength(64)]
        public string? TransactionReferenceId { get; set; }

        [ForeignKey(nameof(TransactionId))]
        public virtual CardTransaction Transaction { get; set; } = null!;
    }
}