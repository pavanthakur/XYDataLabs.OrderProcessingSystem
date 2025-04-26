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
        public int CustomerId { get; set; }

        [Required]
        public string TransactionCustomerId { get; set; } = string.Empty;

        [Required]
        public string TransactionId { get; set; } = string.Empty;

        [Required]
        public string PaymentMethod { get; set; } = string.Empty;

        [Required]
        public string TransactionType { get; set; } = string.Empty;

        public string? OrderId { get; set; }

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

        [Required]
        public string CreditCardCvv2 { get; set; } = string.Empty;

        public string? Description { get; set; }

        [Required]
        [Column(TypeName = "decimal(18,2)")]
        public decimal Amount { get; set; }

        [Required]
        public string CreditCardNumber { get; set; } = string.Empty;

        [Required]
        public bool IsTransactionSuccess { get; set; }

        public string? RedirectUrl { get; set; }

        public string? TransactionMessage { get; set; }

        [ForeignKey(nameof(CustomerId))]
        public virtual BillingCustomer Customer { get; set; } = null!;

        public virtual ICollection<TransactionStatusHistory> StatusHistory { get; set; } = new List<TransactionStatusHistory>();
    }
}
