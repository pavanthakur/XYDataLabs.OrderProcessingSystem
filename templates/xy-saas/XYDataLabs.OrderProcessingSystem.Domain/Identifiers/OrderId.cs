using System.Globalization;

namespace XYDataLabs.OrderProcessingSystem.Domain.Identifiers;

public readonly record struct OrderId(int Value) : IComparable<OrderId>, IParsable<OrderId>
{
    public static implicit operator int(OrderId id) => id.Value;
    public static implicit operator OrderId(int value) => new(value);

    public int CompareTo(OrderId other) => Value.CompareTo(other.Value);

    public static OrderId Parse(string s, IFormatProvider? provider)
    {
        if (!TryParse(s, provider, out var result))
        {
            throw new FormatException($"'{s}' is not a valid order id.");
        }

        return result;
    }

    public static bool TryParse(string? s, IFormatProvider? provider, out OrderId result)
    {
        if (int.TryParse(s, NumberStyles.Integer, provider ?? CultureInfo.InvariantCulture, out var value))
        {
            result = new OrderId(value);
            return true;
        }

        result = default;
        return false;
    }

    public static bool TryParse(string? s, out OrderId result) => TryParse(s, CultureInfo.InvariantCulture, out result);

    public override string ToString() => Value.ToString(CultureInfo.InvariantCulture);
}