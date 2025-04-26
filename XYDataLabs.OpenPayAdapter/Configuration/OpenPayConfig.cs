using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace XYDataLabs.OpenPayAdapter.Configuration
{
    public class OpenPayConfig
    {
        public string MerchantId { get; set; } = string.Empty;
        public string PrivateKey { get; set; } = string.Empty;
        public string DeviceSessionId { get; set; } = string.Empty;
        public bool IsProduction { get; set; }
    }
}
