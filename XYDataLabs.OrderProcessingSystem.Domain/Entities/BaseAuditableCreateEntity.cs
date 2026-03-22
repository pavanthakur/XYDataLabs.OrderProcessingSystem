using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace XYDataLabs.OrderProcessingSystem.Domain.Entities
{
    public abstract class BaseAuditableCreateEntity
    {
        [MaxLength(128)]
        public string TenantId { get; set; } = string.Empty;
        public int? CreatedBy { get; set; }
        public DateTime? CreatedDate { get; set; }
    }
}
