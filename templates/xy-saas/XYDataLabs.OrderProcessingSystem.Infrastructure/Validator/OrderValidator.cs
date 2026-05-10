using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Validator
{
    using FluentValidation;
    using XYDataLabs.OrderProcessingSystem.Domain.Entities;
    using XYDataLabs.OrderProcessingSystem.Domain.Identifiers;
    using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
    using Microsoft.EntityFrameworkCore;

    public class OrderValidator : AbstractValidator<Order>
    {
        private readonly OrderProcessingSystemDbContext _context;

        public OrderValidator(OrderProcessingSystemDbContext context)
        {
            _context = context;

            RuleFor(x => x.CustomerId)
                .MustAsync(HasNoOpenPreviousOrder)
                .WithMessage("Customer has an unfulfilled previous order.");

            RuleFor(x => x.TotalPrice.Value)
                .GreaterThan(0m)
                .WithMessage("Order total must be greater than zero.");
        }

        private async Task<bool> HasNoOpenPreviousOrder(CustomerId customerId, CancellationToken cancellationToken)
        {
            return !await _context.Orders
                .AnyAsync(
                    o => o.CustomerId == customerId
                        && o.Status != OrderStatus.Delivered
                        && o.Status != OrderStatus.Cancelled,
                    cancellationToken);
        }
    }

}
