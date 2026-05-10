using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace XYDataLabs.OrderProcessingSystem.Domain.Entities;

public class Tenant
{
    [Key]
    [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
    public int Id { get; set; }

    [Required]
    [MaxLength(64)]
    public string ExternalId { get; set; } = string.Empty;

    [Required]
    [MaxLength(32)]
    public string Code { get; set; } = string.Empty;

    [Required]
    [MaxLength(256)]
    public string Name { get; set; } = string.Empty;

    [Required]
    [MaxLength(32)]
    public string Status { get; set; } = string.Empty;

    [Required]
    [MaxLength(20)]
    public string TenantTier { get; set; } = "SharedPool";

    public int? CreatedBy { get; set; }

    public DateTime? CreatedDate { get; set; }

    public int? UpdatedBy { get; set; }

    public DateTime? UpdatedDate { get; set; }
}