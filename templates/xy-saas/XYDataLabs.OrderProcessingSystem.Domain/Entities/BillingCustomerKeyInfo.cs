using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace XYDataLabs.OrderProcessingSystem.Domain.Entities
{
    public class BillingCustomerKeyInfo : BaseAuditableEntity
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int Id { get; set; }

        [Required]
        public int BillingCustomerId { get; set; } // Change type to int

        [Required]
        [MaxLength(255)]
        public string KeyName { get; set; } = string.Empty;

        [Required]
        [MaxLength(255)]
        public string KeyValue { get; set; } = string.Empty;

        [ForeignKey(nameof(BillingCustomerId))]
        public virtual BillingCustomer BillingCustomer { get; set; } = null!;
    }
}
