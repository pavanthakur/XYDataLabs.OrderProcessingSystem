using System.Globalization;

namespace XYDataLabs.OrderProcessingSystem.Domain.Identifiers;

public readonly record struct ProductId(int Value) : IComparable<ProductId>, IParsable<ProductId>
{
    public static implicit operator int(ProductId id) => id.Value;
    public static implicit operator ProductId(int value) => new(value);

    public int CompareTo(ProductId other) => Value.CompareTo(other.Value);

    public static ProductId Parse(string s, IFormatProvider? provider)
    {
        if (!TryParse(s, provider, out var result))
        {
            throw new FormatException($"'{s}' is not a valid product id.");
        }

        return result;
    }

    public static bool TryParse(string? s, IFormatProvider? provider, out ProductId result)
    {
        if (int.TryParse(s, NumberStyles.Integer, provider ?? CultureInfo.InvariantCulture, out var value))
        {
            result = new ProductId(value);
            return true;
        }

        result = default;
        return false;
    }

    public static bool TryParse(string? s, out ProductId result) => TryParse(s, CultureInfo.InvariantCulture, out result);

    public override string ToString() => Value.ToString(CultureInfo.InvariantCulture);
}