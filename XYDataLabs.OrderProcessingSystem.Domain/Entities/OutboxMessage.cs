using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace XYDataLabs.OrderProcessingSystem.Domain.Entities
{
    public class OutboxMessage : BaseAuditableEntity
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int Id { get; set; }

        [Required]
        public Guid MessageId { get; set; }

        [Required]
        [MaxLength(256)]
        public string EventType { get; set; } = string.Empty;

        [Required]
        public int SchemaVersion { get; set; }

        [Required]
        public DateTime OccurredUtc { get; set; }

        [Required]
        public string Payload { get; set; } = string.Empty;

        [MaxLength(128)]
        public string? CorrelationId { get; set; }

        [MaxLength(128)]
        public string? CausationId { get; set; }

        [MaxLength(128)]
        public string? TraceParent { get; set; }

        public DateTime? ProcessedAt { get; set; }

        public DateTime? LockExpiry { get; set; }

        public int PublishAttempts { get; set; }

        [MaxLength(1024)]
        public string? LastError { get; set; }
    }
}