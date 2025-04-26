using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations.Schema;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace XYDataLabs.OrderProcessingSystem.Domain.Entities
{
    public class Order : BaseAuditableEntity
    {
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int OrderId { get; set; }
        public DateTime OrderDate { get; set; }
        public int CustomerId { get; set; }

        [Column(TypeName = "decimal(18,2)")]
        public decimal TotalPrice { get; set; }
        public Customer? Customer { get; set; }
        public List<OrderProduct> OrderProducts { get; set; } = new List<OrderProduct>();
        public bool IsFulfilled { get; set; } // Fulfilled or not
    }

}
