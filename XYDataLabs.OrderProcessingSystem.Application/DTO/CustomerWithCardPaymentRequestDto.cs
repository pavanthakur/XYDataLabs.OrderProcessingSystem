using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace XYDataLabs.OrderProcessingSystem.Application.DTO
{
    public class CustomerWithCardPaymentRequestDto
    {
        // Customer Info
        public string Name { get; set; } = string.Empty;
        public string Email { get; set; } = string.Empty;
        public string DeviceSessionId { get; set; } = string.Empty;

        //public string PhoneNumber { get; set; } = string.Empty;//todo: we can utilize later

        // Card Info
        public string CardNumber { get; set; } = string.Empty;
        public string ExpirationYear { get; set; } = string.Empty;
        public string ExpirationMonth { get; set; } = string.Empty;
        public string Cvv2 { get; set; } = string.Empty;

        // Payment Info
        //public string Currency { get; set; } = string.Empty;//todo: we can utilize later
        //public string Amount { get; set; } = string.Empty;//todo: we can utilize later
        public string OrderId { get; set; } = string.Empty;
    }
}
