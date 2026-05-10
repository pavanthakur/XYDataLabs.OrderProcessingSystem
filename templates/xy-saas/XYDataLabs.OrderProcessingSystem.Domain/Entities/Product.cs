using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using XYDataLabs.OrderProcessingSystem.Domain.Identifiers;
using XYDataLabs.OrderProcessingSystem.Domain.ValueObjects;

namespace XYDataLabs.OrderProcessingSystem.Domain.Entities
{
    public class Product : BaseAuditableEntity
    {
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public ProductId ProductId { get; set; }

        [MaxLength(200)]
        public string Name { get; set; } = String.Empty;
        public string Description { get; set; } = String.Empty;

        [Column(TypeName = "decimal(18,2)")]
        public Money Price { get; set; }

        public List<OrderProduct>? OrderProducts { get; set; }
    }

}
