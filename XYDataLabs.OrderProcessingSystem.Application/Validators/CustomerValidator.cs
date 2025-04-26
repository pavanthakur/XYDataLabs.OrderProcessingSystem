using FluentValidation;
using XYDataLabs.OrderProcessingSystem.Application.DTO;

namespace XYDataLabs.OrderProcessingSystem.Application.Validators
{
    public class CustomerValidator : AbstractValidator<CustomerDto>
    {
        public CustomerValidator()
        {
            RuleFor(x => x.Name).NotEmpty().WithMessage("Name is required.");
            RuleFor(x => x.Email).NotEmpty().WithMessage("Email is required.")
                                  .EmailAddress().WithMessage("Invalid email format.");
        }
    }

}
