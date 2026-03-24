using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace XYDataLabs.OrderProcessingSystem.Domain.Entities
{
    public class CardTransaction : BaseAuditableEntity
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int Id { get; set; }

        [Required]
        public int BillingCustomerId { get; set; }

        [Required]
        public string TransactionCustomerId { get; set; } = string.Empty;

        [Required]
        public string TransactionId { get; set; } = string.Empty;

        [Required]
        [MaxLength(64)]
        public string PaymentTraceId { get; set; } = string.Empty;

        [Required]
        public string PaymentMethod { get; set; } = string.Empty;

        [Required]
        public string TransactionType { get; set; } = string.Empty;

        [Required]
        [MaxLength(128)]
        public string CustomerOrderId { get; set; } = string.Empty;

        [MaxLength(128)]
        public string? AttemptOrderId { get; set; }

        [Required]
        public string TransactionStatus { get; set; } = string.Empty;

        public string? TransactionReferenceId { get; set; }

        public DateTime? TransactionDate { get; set; }

        [Required]
        public string CurrencyCode { get; set; } = string.Empty;

        [Required]
        public string CreditCardOwnerName { get; set; } = string.Empty;

        [Required]
        public int CreditCardExpireYear { get; set; }

        [Required]
        public int CreditCardExpireMonth { get; set; }

        public string? Description { get; set; }

        [Required]
        [Column(TypeName = "decimal(18,2)")]
        public decimal Amount { get; set; }

        [MaxLength(19)]
        public string? MaskedCardNumber { get; set; }

        [Required]
        public bool IsTransactionSuccess { get; set; }

        [Required]
        public bool IsThreeDSecureEnabled { get; set; }

        [MaxLength(64)]
        public string? ThreeDSecureStage { get; set; }

        public string? RedirectUrl { get; set; }

        public string? TransactionMessage { get; set; }

        [ForeignKey(nameof(BillingCustomerId))]
        public virtual BillingCustomer BillingCustomer { get; set; } = null!;

        public virtual ICollection<TransactionStatusHistory> StatusHistory { get; set; } = new List<TransactionStatusHistory>();
    }
}
