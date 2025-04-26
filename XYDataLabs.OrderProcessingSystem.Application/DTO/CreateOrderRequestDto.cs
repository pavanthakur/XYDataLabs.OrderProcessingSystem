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
    }
}
