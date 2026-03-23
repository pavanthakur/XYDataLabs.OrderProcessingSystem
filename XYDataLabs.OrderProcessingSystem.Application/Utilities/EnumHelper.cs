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
        public static string? NormalizeOpenPayStatus(string? status)
        {
            if (string.IsNullOrWhiteSpace(status))
                return null;

            var upper = status.Trim().ToUpperInvariant();
            return upper switch
            {
                "COMPLETED" or "SUCCESS" or "PAID" => "completed",
                "CHARGE_PENDING" or "PENDING" or "IN_PROGRESS" => "charge_pending",
                "FAILED" or "DECLINED" or "ERROR" => "failed",
                "CANCELLED" or "CANCELED" => "cancelled",
                _ => upper
            };
        }
    }
}
