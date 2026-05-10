using FluentValidation;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Orders.Commands;

public sealed class CreateOrderCommandValidator : AbstractValidator<CreateOrderCommand>
{
    public CreateOrderCommandValidator()
    {
        RuleFor(x => x.CustomerId.Value).GreaterThan(0).WithMessage("Customer ID must be greater than zero.");
        RuleFor(x => x.ProductIds).NotEmpty().WithMessage("At least one product is required.");
        RuleForEach(x => x.ProductIds)
            .Must(productId => productId.Value > 0)
            .WithMessage("Product ID must be greater than zero.");
    }
}
