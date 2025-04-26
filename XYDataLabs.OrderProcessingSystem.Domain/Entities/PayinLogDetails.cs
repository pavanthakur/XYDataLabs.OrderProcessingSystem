using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace XYDataLabs.OrderProcessingSystem.Domain.Entities
{
    public class PayinLogDetails : BaseAuditableEntity
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int Id { get; set; }

        public string? PostInfo { get; set; }

        public string? RespInfo { get; set; }

        public string? AdditionalInfo { get; set; }

        [Required]
        public int PayinLogId { get; set; }

        [ForeignKey(nameof(PayinLogId))]
        public virtual PayinLog PayinLog { get; set; } = null!;
    }
}