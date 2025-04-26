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

        [Required]
        [MaxLength(50)]
        public string Status { get; set; } = string.Empty;

        [MaxLength(255)]
        public string? Notes { get; set; }

        [ForeignKey(nameof(TransactionId))]
        public virtual CardTransaction Transaction { get; set; } = null!;
    }
}