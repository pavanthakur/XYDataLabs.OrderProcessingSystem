using System.Globalization;

namespace XYDataLabs.OrderProcessingSystem.Domain.ValueObjects;

public readonly record struct Money(decimal Value) : IComparable<Money>
{
    public static Money Zero => new(0m);

    public static implicit operator decimal(Money money) => money.Value;
    public static implicit operator Money(decimal value) => From(value);

    public static Money From(decimal value)
    {
        if (value < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(value), "Money cannot be negative.");
        }

        return new Money(decimal.Round(value, 2, MidpointRounding.AwayFromZero));
    }

    public static Money operator +(Money left, Money right) => From(left.Value + right.Value);

    public static Money operator *(Money money, int quantity)
    {
        if (quantity < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(quantity), "Quantity cannot be negative.");
        }

        return From(money.Value * quantity);
    }

    public static bool operator <(Money left, Money right) => left.Value < right.Value;
    public static bool operator <=(Money left, Money right) => left.Value <= right.Value;
    public static bool operator >(Money left, Money right) => left.Value > right.Value;
    public static bool operator >=(Money left, Money right) => left.Value >= right.Value;

    public int CompareTo(Money other) => Value.CompareTo(other.Value);

    public override string ToString() => Value.ToString("0.00", CultureInfo.InvariantCulture);
}