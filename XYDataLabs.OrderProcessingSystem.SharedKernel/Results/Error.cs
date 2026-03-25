using System.Text.Json.Serialization;

namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

public sealed class Error
{
    public string Code { get; }
    public string Description { get; }

    [JsonConstructor]
    private Error(string code, string description)
    {
        Code = code;
        Description = description;
    }

    public static Error Create(string code, string description) => new(code, description);

    public static readonly Error None = Create(string.Empty, string.Empty);
    public static readonly Error NotFound = Create("NotFound", "The requested resource was not found.");
    public static readonly Error Validation = Create("Validation", "A validation error occurred.");
    public static readonly Error Conflict = Create("Conflict", "A conflict occurred with the current state.");
    public static readonly Error Unauthorized = Create("Unauthorized", "Authentication is required.");
    public static readonly Error Forbidden = Create("Forbidden", "You do not have permission to perform this action.");

    public override string ToString() => $"{Code}: {Description}";
}
