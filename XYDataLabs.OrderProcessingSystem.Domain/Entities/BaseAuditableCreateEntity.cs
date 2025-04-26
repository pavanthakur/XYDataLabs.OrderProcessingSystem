using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace XYDataLabs.OrderProcessingSystem.Domain.Entities
{
    public abstract class BaseAuditableCreateEntity
    {
        public int? CreatedBy { get; set; }
        public DateTime? CreatedDate { get; set; }
    }
}
