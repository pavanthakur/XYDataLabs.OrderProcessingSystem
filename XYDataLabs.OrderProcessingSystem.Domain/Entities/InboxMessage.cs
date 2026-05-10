using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace XYDataLabs.OrderProcessingSystem.Domain.Entities
{
    public class InboxMessage : BaseAuditableCreateEntity
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
        public DateTime ProcessedUtc { get; set; }
    }
}