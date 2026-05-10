using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations.Schema;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using XYDataLabs.OrderProcessingSystem.Domain.Identifiers;
using XYDataLabs.OrderProcessingSystem.Domain.ValueObjects;

namespace XYDataLabs.OrderProcessingSystem.Domain.Entities
{
    public class OrderProduct : BaseAuditableCreateEntity
    {
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int SysId { get; set; }
        public OrderId OrderId { get; set; }
        public ProductId ProductId { get; set; }
        public int Quantity { get; set; }

        [Column(TypeName = "decimal(18,2)")]
        public Money Price => (Product?.Price ?? Money.Zero) * Quantity;

        public Order? Order { get; set; }
        public Product? Product { get; set; }
    }

}
