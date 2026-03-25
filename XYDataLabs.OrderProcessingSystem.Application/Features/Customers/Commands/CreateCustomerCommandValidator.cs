using FluentValidation;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Customers.Commands;

public sealed class CreateCustomerCommandValidator : AbstractValidator<CreateCustomerCommand>
{
    public CreateCustomerCommandValidator()
    {
        RuleFor(x => x.Name).NotEmpty().WithMessage("Name is required.");
        RuleFor(x => x.Email).NotEmpty().WithMessage("Email is required.")
                              .EmailAddress().WithMessage("Invalid email format.");
    }
}
