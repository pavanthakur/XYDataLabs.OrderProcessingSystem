namespace XYDataLabs.OrderProcessingSystem.Utilities
{
    /// <summary>
    /// Application-wide constants and configuration keys.
    /// </summary>
    public static class Constants
    {
        /// <summary>
        /// Configuration key constants for application settings
        /// </summary>
        public static class Configuration
        {
            /// <summary>
            /// The connection string name for the main Order Processing System database.
            /// </summary>
            public const string OrderProcessingSystemDbConnectionString = "OrderProcessingSystemDbConnection";
            
            /// <summary>
            /// OpenPay configuration keys
            /// </summary>
            public const string OpenPayRedirectUrl = "OpenPay:RedirectUrl";
            public const string OpenPayDeviceSessionId = "OpenPay:DeviceSessionId";
        }

        /// <summary>
        /// Application settings section names.
        /// </summary>
        public static class AppSettings
        {
            public const string ApiSettings = "ApiSettings";
            public const string OpenPay = "OpenPay";
            public const string Serilog = "Serilog";
            public const string SerilogUI = "SerilogUI";
            public const string LaunchSettings = "LaunchSettings";
            public const string Azure = "Azure";
            public const string Docker = "Docker";
        }

        /// <summary>
        /// Environment names.
        /// </summary>
        public static class Environments
        {
            public const string Development = "Development";
            public const string Local = "local";
            public const string Dev = "dev";
            public const string Uat = "uat";
            public const string Production = "prod";
        }

        /// <summary>
        /// Default values used throughout the application.
        /// </summary>
        public static class Defaults
        {
            /// <summary>
            /// Default certificate file name for development HTTPS.
            /// </summary>
            public const string CertificateFileName = "aspnetapp.pfx";
            
            /// <summary>
            /// Default certificate password for development HTTPS.
            /// </summary>
            public const string CertificatePassword = "password";
            
            /// <summary>
            /// Default shared settings file name template.
            /// </summary>
            public const string SharedSettingsFileTemplate = "sharedsettings.{0}.json";
        }
    }
}
