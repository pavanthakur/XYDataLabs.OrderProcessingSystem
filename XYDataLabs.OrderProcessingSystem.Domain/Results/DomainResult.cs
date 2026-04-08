using System.Diagnostics.CodeAnalysis;

namespace XYDataLabs.OrderProcessingSystem.Domain.Results
{
    public sealed class DomainError
    {
        public string Code { get; }
        public string Description { get; }

        private DomainError(string code, string description)
        {
            Code = code;
            Description = description;
        }

        public static DomainError Create(string code, string description) => new(code, description);

        public static readonly DomainError None = Create(string.Empty, string.Empty);
    }

    public sealed class DomainResult
    {
        public DomainError Error { get; }
        public bool IsSuccess { get; }
        public bool IsFailure => !IsSuccess;

        private DomainResult(bool isSuccess, DomainError error)
        {
            IsSuccess = isSuccess;
            Error = error;
        }

        public static DomainResult Success() => new(true, DomainError.None);
        public static DomainResult Failure(DomainError error) => new(false, error);

        public static implicit operator DomainResult(DomainError error) => Failure(error);
    }

    public sealed class DomainResult<T>
    {
        public T? Value { get; }
        public DomainError Error { get; }

        [MemberNotNullWhen(true, nameof(Value))]
        public bool IsSuccess { get; }

        [MemberNotNullWhen(false, nameof(Value))]
        public bool IsFailure => !IsSuccess;

        private DomainResult(T? value, DomainError error, bool isSuccess)
        {
            Value = value;
            Error = error;
            IsSuccess = isSuccess;
        }

        public static DomainResult<T> Success(T value) => new(value, DomainError.None, true);
        public static DomainResult<T> Failure(DomainError error) => new(default, error, false);

        public static implicit operator DomainResult<T>(T value) => Success(value);
        public static implicit operator DomainResult<T>(DomainError error) => Failure(error);
    }
}