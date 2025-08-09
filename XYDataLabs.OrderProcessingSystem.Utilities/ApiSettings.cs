namespace XYDataLabs.OrderProcessingSystem.Utilities
{
    public class ApiSettingsSection
    {
        public string Host { get; set; } = "localhost";
        public int Port { get; set; }
        public bool HttpsEnabled { get; set; }
        public string? CertPassword { get; set; }
        public string? CertPath { get; set; }
        public string GetBaseUrl()
        {
            var scheme = HttpsEnabled ? "https" : "http";
            return $"{scheme}://{Host}:{Port}";
        }
    }

    public class ApiSettingsGroup
    {
        public ApiSettingsSection http { get; set; } = new ApiSettingsSection();
        public ApiSettingsSection https { get; set; } = new ApiSettingsSection();
        public ApiSettingsSection GetActive(bool useHttps)
        {
            return useHttps ? https : http;
        }
    }

    public class ApiSettings
    {
        public ApiSettingsGroup UI { get; set; } = new ApiSettingsGroup();
        public ApiSettingsGroup API { get; set; } = new ApiSettingsGroup();
    }
}