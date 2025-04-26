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
    }
}
