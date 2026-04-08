using System.Globalization;

namespace XYDataLabs.OrderProcessingSystem.Domain.Identifiers;

public readonly record struct CustomerId(int Value) : IComparable<CustomerId>, IParsable<CustomerId>
{
    public static implicit operator int(CustomerId id) => id.Value;
    public static implicit operator CustomerId(int value) => new(value);

    public int CompareTo(CustomerId other) => Value.CompareTo(other.Value);

    public static CustomerId Parse(string s, IFormatProvider? provider)
    {
        if (!TryParse(s, provider, out var result))
        {
            throw new FormatException($"'{s}' is not a valid customer id.");
        }

        return result;
    }

    public static bool TryParse(string? s, IFormatProvider? provider, out CustomerId result)
    {
        if (int.TryParse(s, NumberStyles.Integer, provider ?? CultureInfo.InvariantCulture, out var value))
        {
            result = new CustomerId(value);
            return true;
        }

        result = default;
        return false;
    }

    public static bool TryParse(string? s, out CustomerId result) => TryParse(s, CultureInfo.InvariantCulture, out result);

    public override string ToString() => Value.ToString(CultureInfo.InvariantCulture);
}