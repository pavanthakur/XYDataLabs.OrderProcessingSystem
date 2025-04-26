using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace XYDataLabs.OrderProcessingSystem.Domain.Entities
{
    public class BillingCustomer : BaseAuditableEntity
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int Id { get; set; }

        [Required]
        [MaxLength(2)]
        public string TwoLetterIsoCode { get; set; } = string.Empty;

        [Required]
        public string Name { get; set; } = string.Empty;

        [Required]
        [EmailAddress]
        public string Email { get; set; } = string.Empty;

        [Required]
        public string PhoneNumber { get; set; } = string.Empty;

        [Required]
        public string APICustomerId { get; set; } = string.Empty;

        [Required]
        public int PaymentMethodId { get; set; }

        [ForeignKey(nameof(PaymentMethodId))]
        public PaymentMethod PaymentMethod { get; set; } = null!;

        public virtual ICollection<BillingCustomerKeyInfo> KeyInfos { get; set; } = new List<BillingCustomerKeyInfo>();
        public virtual ICollection<CardTransaction> CardTransactions { get; set; } = new List<CardTransaction>();
    }
}