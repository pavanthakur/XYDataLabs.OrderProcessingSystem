using System.ComponentModel;

namespace XYDataLabs.OrderProcessingSystem.Application.Utilities
{
    public static class AppMasterConstant
    {
        public const string DefaultCurrencyCode = "MXN";
        public const string DefaultCountryCode = "MX";

        public enum PayInType
        {
            Charge = 1,
            Refund = 2
        }

        public enum PaymentMethodType
        {
            [Description("card")]
            Card = 1
        }

        public enum PaymentStatus
        {
            [Description("completed")]
            Success = 1,

            [Description("charge_pending")]
            Pending = 2,

            [Description("failed")]
            Failed = 3,

            [Description("unknown")]
            Unknown = 4
        }

        public enum TransactionType
        {
            [Description("pay")]
            Pay = 1,

            [Description("refund")]
            Refund = 2,

            [Description("charge")]
            Charge = 3,

            [Description("tokenization")]
            Tokenization = 4,

            [Description("unknown")]
            Unknown = 5
        }

        public enum OpenPayTransactionStatus
        {
            [Description("pending")]
            Pending = 1,

            [Description("completed")]
            Completed = 2
        }
    }
}
