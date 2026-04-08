using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace XYDataLabs.OrderProcessingSystem.Domain.Entities
{
    public class AuditLog : BaseAuditableCreateEntity
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int Id { get; set; }

        [Required]
        [MaxLength(128)]
        public string EntityName { get; set; } = string.Empty;

        [Required]
        [MaxLength(64)]
        public string EntityId { get; set; } = string.Empty;

        [Required]
        [MaxLength(16)]
        public string Operation { get; set; } = string.Empty;

        [MaxLength(64)]
        public string? TraceId { get; set; }

        [MaxLength(128)]
        public string? CorrelationId { get; set; }

        public string? OldValues { get; set; }

        public string? NewValues { get; set; }
    }
}