using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using System.Linq;
using XYDataLabs.OrderProcessingSystem.Domain.Events;
using XYDataLabs.OrderProcessingSystem.Domain.Identifiers;
using XYDataLabs.OrderProcessingSystem.Domain.Results;
using XYDataLabs.OrderProcessingSystem.Domain.ValueObjects;

namespace XYDataLabs.OrderProcessingSystem.Domain.Entities
{
    public class Order : BaseAuditableEntity
    {
        private Order()
        {
        }

        private Order(
            CustomerId customerId,
            List<OrderProduct> orderProducts,
            DateTime orderDate,
            string currencyCode)
        {
            OrderReferenceId = Guid.NewGuid();
            CustomerId = customerId;
            OrderDate = orderDate;
            OrderProducts = orderProducts;
            TotalPrice = orderProducts.Aggregate(Money.Zero, static (total, item) => total + item.Price);
            CurrencyCode = currencyCode;
            Status = OrderStatus.Created;

            RaiseDomainEvent(new OrderCreatedDomainEvent(
                customerId,
                orderDate,
                TotalPrice.Value,
                orderProducts.Count,
                orderDate,
                OrderReferenceId,
                CurrencyCode));
        }

        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public OrderId OrderId { get; set; }
        public Guid OrderReferenceId { get; private set; }
        public DateTime OrderDate { get; private set; }
        public CustomerId CustomerId { get; private set; }

        [Column(TypeName = "decimal(18,2)")]
        public Money TotalPrice { get; private set; }
        [MaxLength(3)]
        public string CurrencyCode { get; private set; } = "MXN";
        public Customer? Customer { get; private set; }
        public List<OrderProduct> OrderProducts { get; private set; } = new List<OrderProduct>();
        public OrderStatus Status { get; private set; } = OrderStatus.Created;

        [NotMapped]
        public bool IsFulfilled => Status == OrderStatus.Delivered;

        [NotMapped]
        public bool IsClosed => Status is OrderStatus.Delivered or OrderStatus.Cancelled;

        [Timestamp]
        public byte[] RowVersion { get; private set; } = Array.Empty<byte>();

        public static DomainResult<Order> Create(
            int customerId,
            IEnumerable<Product> products,
            DateTime? orderDate = null,
            string currencyCode = "MXN") =>
            Create(new CustomerId(customerId), products, orderDate, currencyCode);

        public static DomainResult<Order> Create(
            CustomerId customerId,
            IEnumerable<Product> products,
            DateTime? orderDate = null,
            string currencyCode = "MXN")
        {
            if (customerId.Value <= 0)
            {
                return DomainError.Create("Validation", "CustomerId must be greater than zero.");
            }

            var productList = products?.ToList() ?? new List<Product>();
            if (productList.Count == 0)
            {
                return DomainError.Create("Validation", "An order must contain at least one product.");
            }

            var orderProducts = productList
                .Select(product => new OrderProduct
                {
                    ProductId = product.ProductId,
                    Product = product,
                    Quantity = 1
                })
                .ToList();

            var totalPrice = orderProducts.Aggregate(Money.Zero, static (total, item) => total + item.Price);
            if (totalPrice <= Money.Zero)
            {
                return DomainError.Create("Validation", "The total price must be greater than zero.");
            }

            var normalizedCurrency = currencyCode?.Trim().ToUpperInvariant();
            if (normalizedCurrency?.Length != 3)
            {
                return DomainError.Create(
                    "Validation",
                    "CurrencyCode must be a three-letter ISO currency code.");
            }

            return new Order(
                customerId,
                orderProducts,
                orderDate ?? DateTime.UtcNow,
                normalizedCurrency);
        }

        public DomainResult Pay() => TransitionTo(
            OrderStatus.Created,
            OrderStatus.Paid,
            "Only created orders can be paid.");

        public DomainResult Ship() => TransitionTo(
            OrderStatus.Paid,
            OrderStatus.Shipped,
            "Only paid orders can be shipped.");

        public DomainResult Deliver() => TransitionTo(
            OrderStatus.Shipped,
            OrderStatus.Delivered,
            "Only shipped orders can be delivered.");

        public DomainResult Cancel()
        {
            if (Status == OrderStatus.Cancelled)
            {
                return DomainError.Create("Conflict", "Order is already cancelled.");
            }

            if (Status is OrderStatus.Shipped or OrderStatus.Delivered)
            {
                return DomainError.Create("Conflict", "Shipped or delivered orders cannot be cancelled.");
            }

            Status = OrderStatus.Cancelled;
            return DomainResult.Success();
        }

        private DomainResult TransitionTo(OrderStatus expectedStatus, OrderStatus nextStatus, string errorDescription)
        {
            if (Status != expectedStatus)
            {
                return DomainError.Create("Conflict", errorDescription);
            }

            Status = nextStatus;
            return DomainResult.Success();
        }
    }

}
