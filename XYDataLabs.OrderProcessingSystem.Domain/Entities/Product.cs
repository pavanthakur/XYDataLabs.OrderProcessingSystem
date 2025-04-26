using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace XYDataLabs.OrderProcessingSystem.Domain.Entities
{
    public class Product : BaseAuditableEntity
    {
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int ProductId { get; set; }

        [MaxLength(200)]
        public string Name { get; set; } = String.Empty;
        public string Description { get; set; } = String.Empty;

        [Column(TypeName = "decimal(18,2)")]
        public decimal Price { get; set; }

        public List<OrderProduct>? OrderProducts { get; set; }
    }

}
