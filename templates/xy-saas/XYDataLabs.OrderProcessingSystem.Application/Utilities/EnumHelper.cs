using System.ComponentModel;
using System.Reflection;

namespace XYDataLabs.OrderProcessingSystem.Application.Utilities
{
    public static class EnumHelper
    {
        // Get description from enum
        public static string GetEnumDescription(Enum value)
        {
            FieldInfo? field = value.GetType().GetField(value.ToString());
            DescriptionAttribute? attribute = field?.GetCustomAttribute<DescriptionAttribute>();

            return attribute?.Description ?? value.ToString();
        }

        // Get enum value (ID) from description
        public static int? GetEnumIdFromDescription<TEnum>(string description) where TEnum : Enum
        {
            foreach (TEnum enumValue in Enum.GetValues(typeof(TEnum)))
            {
                if (GetEnumDescription(enumValue).Equals(description, StringComparison.OrdinalIgnoreCase))
                {
                    return Convert.ToInt32(enumValue);
                }
            }
            return null;  // Return null if description not found
        }

        /// <summary>
        /// Normalises a raw OpenPay payment status string to the canonical internal status value
        /// used across all payment tables (TransactionStatus, PaymentStatus enum descriptions).
        /// </summary>
        /// <summary>
        /// Normalises a raw OpenPay status string to the canonical PaymentStatus description value.
        /// Returns null for unrecognised inputs so callers can use ?? chains to provide a fallback.
        /// </summary>
        public static string? NormalizeOpenPayStatus(string? status)
        {
            if (string.IsNullOrWhiteSpace(status))
                return null;

            return status.Trim().ToUpperInvariant() switch
            {
                "COMPLETED" or "SUCCESS" or "PAID" => "completed",
                "CHARGE_PENDING" or "PENDING" or "IN_PROGRESS" => "charge_pending",
                "FAILED" or "DECLINED" or "ERROR" => "failed",
                "CANCELLED" or "CANCELED" => "cancelled",
                _ => null  // unknown inputs fall through to the caller's ?? default
            };
        }

        // ── Payment-status predicates ─────────────────────────────────────────
        // Single source of truth: all comparisons derive from PaymentStatus enum descriptions.
        // Handlers must NOT declare their own copies of these — use EnumHelper directly.

        public static bool IsSuccessStatus(string? status)
            => string.Equals(status, GetEnumDescription(AppMasterConstant.PaymentStatus.Success), StringComparison.Ordinal);

        public static bool IsPendingStatus(string? status)
            => string.Equals(status, GetEnumDescription(AppMasterConstant.PaymentStatus.Pending), StringComparison.Ordinal);

        public static bool IsFailedStatus(string? status)
            => string.Equals(status, GetEnumDescription(AppMasterConstant.PaymentStatus.Failed), StringComparison.Ordinal);

        public static bool IsCancelledStatus(string? status)
            => string.Equals(status, GetEnumDescription(AppMasterConstant.PaymentStatus.Cancelled), StringComparison.Ordinal);

        /// <summary>Failed OR Cancelled — both are terminal non-success outcomes.</summary>
        public static bool IsFailureStatus(string? status)
            => IsFailedStatus(status) || IsCancelledStatus(status);

        public static bool IsFinalStatus(string? status)
            => IsSuccessStatus(status) || IsFailureStatus(status);

        public static string ToStatusCategory(string? status)
        {
            if (IsSuccessStatus(status)) return "success";
            if (IsPendingStatus(status)) return "warning";
            if (IsFailedStatus(status)) return "danger";
            if (IsCancelledStatus(status)) return "secondary";
            return "info";
        }

        public static string ToStatusMessage(string? status, bool remoteStatusConfirmed)
        {
            if (IsSuccessStatus(status))
                return remoteStatusConfirmed
                    ? "Payment completed successfully and the final status was confirmed with OpenPay."
                    : "Payment completed successfully based on the latest local record.";

            if (IsPendingStatus(status))
                return remoteStatusConfirmed
                    ? "Payment is still pending issuer or 3D Secure completion according to OpenPay."
                    : "Payment is still pending confirmation based on the latest local record.";

            if (IsFailedStatus(status))
                return remoteStatusConfirmed
                    ? "Payment failed and the final status was confirmed with OpenPay."
                    : "Payment failed based on the latest local record.";

            if (IsCancelledStatus(status))
                return remoteStatusConfirmed
                    ? "Payment was cancelled and the final status was confirmed with OpenPay."
                    : "Payment was cancelled based on the latest local record.";

            return remoteStatusConfirmed
                ? "Payment callback was received, but OpenPay returned a status that is not explicitly mapped yet."
                : "Payment callback was received, but the final status could not be confirmed remotely.";
        }
    }
}
