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
            Unknown = 4,

            [Description("cancelled")]
            Cancelled = 5
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

        public enum ThreeDSecureStage
        {
            [Description("not_applicable")]
            NotApplicable = 1,

            [Description("tokenization_completed")]
            TokenizationCompleted = 2,

            [Description("charge_requested")]
            ChargeRequested = 3,

            [Description("redirect_issued")]
            RedirectIssued = 4,

            [Description("callback_received")]
            CallbackReceived = 5,

            [Description("remote_confirmation_started")]
            RemoteConfirmationStarted = 6,

            [Description("pending_confirmation")]
            PendingConfirmation = 7,

            [Description("completed")]
            Completed = 8,

            [Description("failed")]
            Failed = 9,

            [Description("cancelled")]
            Cancelled = 10,

            [Description("unknown")]
            Unknown = 11
        }
    }
}
