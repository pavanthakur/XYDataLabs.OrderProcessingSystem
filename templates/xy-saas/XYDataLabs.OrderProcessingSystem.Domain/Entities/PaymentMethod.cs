using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace XYDataLabs.OrderProcessingSystem.Domain.Entities
{
    public class PaymentMethod : BaseAuditableEntity
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int Id { get; set; }

        [Required]
        public int PaymentProviderId { get; set; }

        [Required]
        public string Token { get; set; } = string.Empty;

        [Required]
        public bool Status { get; set; }

        [ForeignKey(nameof(PaymentProviderId))]
        public virtual PaymentProvider PaymentProvider { get; set; } = null!;

        public virtual ICollection<BillingCustomer> BillingCustomers { get; set; } = new List<BillingCustomer>();
        public virtual ICollection<PayinLog> PayinLogs { get; set; } = new List<PayinLog>();
    }
}