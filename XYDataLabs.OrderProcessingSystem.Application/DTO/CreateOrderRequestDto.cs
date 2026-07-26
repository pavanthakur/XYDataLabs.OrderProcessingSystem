using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace XYDataLabs.OrderProcessingSystem.Application.DTO
{
    /// <summary>
    /// Request model for creating an order.
    /// </summary>
    public class CreateOrderRequestDto
    {
        /// <summary>
        /// Gets or sets the customer ID.
        /// </summary>
        public int CustomerId { get; set; }

        /// <summary>
        /// Gets or sets the list of product IDs.
        /// </summary>
        public List<int> ProductIds { get; set; } = new List<int>();

        /// <summary>
        /// Gets or sets the ISO currency code owned by the order.
        /// </summary>
        public string CurrencyCode { get; set; } = "MXN";
    }
}
