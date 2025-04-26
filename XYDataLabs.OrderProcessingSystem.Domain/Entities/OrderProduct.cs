using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations.Schema;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace XYDataLabs.OrderProcessingSystem.Domain.Entities
{
    public class OrderProduct : BaseAuditableCreateEntity
    {
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int SysId { get; set; }
        public int OrderId { get; set; }
        public int ProductId { get; set; }
        public int Quantity { get; set; }

        [Column(TypeName = "decimal(18,2)")]
        public decimal Price => (Product?.Price ?? 0) * Quantity;

        public Order? Order { get; set; }
        public Product? Product { get; set; }
    }

}
