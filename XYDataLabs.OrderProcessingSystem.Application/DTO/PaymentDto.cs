using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace XYDataLabs.OrderProcessingSystem.Application.DTO
{
    public class PaymentDto
    {
        public string Id { get; set; } = string.Empty;
        public string OrderId { get; set; } = string.Empty;
        public string CustomerId { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public string Currency { get; set; } = "MXN";
        public string Status { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; }
        public string? TransactionId { get; set; }
        public string? ErrorMessage { get; set; }
        public string? ThreeDSecureUrl { get; set; }
    }
}
