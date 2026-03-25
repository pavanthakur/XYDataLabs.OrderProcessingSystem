using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace XYDataLabs.OrderProcessingSystem.Domain.Entities
{
    public class PayinLog : BaseAuditableEntity
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int Id { get; set; }

        [MaxLength(50)]
        public string? AttemptOrderId { get; set; }

        [Required]
        [MaxLength(128)]
        public string CustomerOrderId { get; set; } = string.Empty;

        public int? PaymentMethodId { get; set; }

        [MaxLength(50)]
        public string? PaymentMethodName { get; set; }

        public int? PayinType { get; set; }

        [MaxLength(50)]
        public string? OpenPayChargeId { get; set; }

        [Required]
        [MaxLength(64)]
        public string PaymentTraceId { get; set; } = string.Empty;

        [MaxLength(50)]
        public string? OpenPayAuthorizationId { get; set; }

        [Column(TypeName = "decimal(18,4)")]
        public decimal? Amount { get; set; }

        [Column(TypeName = "decimal(18,4)")]
        public decimal? AmountFromAPI { get; set; }

        [MaxLength(4)]
        public string? LastFourCardNbr { get; set; }

        [MaxLength(100)]
        public string? CardOwnerName { get; set; }

        [MaxLength(50)]
        public string? Currency { get; set; }

        public bool IsThreeDSecureEnabled { get; set; }

        [MaxLength(64)]
        public string? ThreeDSecureStage { get; set; }

        public int? Result { get; set; }

        [ForeignKey(nameof(PaymentMethodId))]
        public virtual PaymentMethod? PaymentMethod { get; set; }

        public virtual ICollection<PayinLogDetails> PayinLogDetails { get; set; } = new List<PayinLogDetails>();
    }
}