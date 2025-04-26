using AutoMapper;
using FluentValidation;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Moq;


namespace XYDataLabs.OrderProcessingSystem.UnitTest.TestBase
{
    public class OrderProcessingSystemTestBase<T1> where T1 : class
    {
        protected Mock<OrderProcessingSystemDbContext> MockDbContext { get; private set; }
        protected Mock<DbSet<Customer>> MockCustomerDbSet { get; private set; }
        protected Mock<DbSet<Order>> MockOrderDbSet { get; private set; }
        protected Mock<DbSet<Product>> MockProductDbSet { get; private set; }
        protected Mock<ILogger<T1>> MockLogger { get; private set; }

        protected readonly Mock<IValidator<Order>> MockOrderValidator;
        protected Mock<IMapper> MockMapper { get; private set; }

        public OrderProcessingSystemTestBase()
        {
            // Initialize Mock DbContext
            MockDbContext = new Mock<OrderProcessingSystemDbContext>();
            MockLogger = new Mock<ILogger<T1>>();
            MockMapper = new Mock<IMapper>();

            // Initialize Mock DbSet
            MockCustomerDbSet = new Mock<DbSet<Customer>>();
            MockOrderDbSet = new Mock<DbSet<Order>>();
            MockProductDbSet = new Mock<DbSet<Product>>();

            // Initialize Mock Validator
            MockOrderValidator = new Mock<IValidator<Order>>();

            // Set up the mock DbContext to return the DbSets
            MockDbContext.Setup(c => c.Customers).Returns(MockCustomerDbSet.Object);
            MockDbContext.Setup(o => o.Orders).Returns(MockOrderDbSet.Object);
            MockDbContext.Setup(p => p.Products).Returns(MockProductDbSet.Object);

            SetupTestBase();
        }

        public virtual void SetupTestBase()
        {
        }

        protected Mock<DbSet<T2>> GetMockDbSet<T2>(IQueryable<T2> entities) where T2 : class
        {
            var mockSet = new Mock<DbSet<T2>>();
            mockSet.As<IQueryable<T2>>().Setup(m => m.Provider).Returns(entities.AsQueryable().Provider);
            mockSet.As<IQueryable<T2>>().Setup(m => m.Expression).Returns(entities.AsQueryable().Expression);
            mockSet.As<IQueryable<T2>>().Setup(m => m.ElementType).Returns(entities.AsQueryable().ElementType);
            mockSet.As<IQueryable<T2>>().Setup(m => m.GetEnumerator()).Returns(entities.AsQueryable().GetEnumerator());

            mockSet.As<IAsyncEnumerable<T2>>()
                   .Setup(m => m.GetAsyncEnumerator(It.IsAny<CancellationToken>()))
                   .Returns(new TestAsyncEnumerator<T2>(entities.GetEnumerator()));

            mockSet.As<IQueryable<T2>>()
                   .Setup(m => m.Provider)
                   .Returns(new TestAsyncQueryProvider<T2>(entities.Provider));

            return mockSet;
        }
    }
}
