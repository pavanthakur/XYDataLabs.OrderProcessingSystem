using FluentValidation;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Customers.Commands;

public sealed class UpdateCustomerCommandValidator : AbstractValidator<UpdateCustomerCommand>
{
    public UpdateCustomerCommandValidator()
    {
        RuleFor(x => x.CustomerId).GreaterThan(0).WithMessage("Customer ID must be greater than zero.");
        RuleFor(x => x.Name).NotEmpty().WithMessage("Name is required.");
        RuleFor(x => x.Email).NotEmpty().WithMessage("Email is required.")
                              .EmailAddress().WithMessage("Invalid email format.");
    }
}
