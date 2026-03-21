using FluentAssertions;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Features.Customers.Commands;
using XYDataLabs.OrderProcessingSystem.Application.Features.Customers.Queries;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;
using XYDataLabs.OrderProcessingSystem.Application.Tests.TestBase;
using Microsoft.EntityFrameworkCore;
using Moq;


namespace XYDataLabs.OrderProcessingSystem.Application.Tests.Handlers
{
    public class CustomerHandlerTests : CustomerServiceTestBase
    {
        [Fact]
        public async Task CreateCustomerCommand_ShouldReturnCustomerId_WhenCustomerIsCreated()
        {
            // Arrange
            var newCustomer = GenerateNewCustomerRequestDto(1)[0];
            var customer = GenerateCustomers(1).First();
            MockMapper.Setup(m => m.Map<Customer>(It.IsAny<CreateCustomerRequestDto>())).Returns(customer);
            MockDbContext.Setup(db => db.Customers.Add(It.IsAny<Customer>()));
            MockDbContext.Setup(db => db.SaveChangesAsync(It.IsAny<CancellationToken>())).ReturnsAsync(1);

            var handler = new CreateCustomerCommandHandler(MockDbContext.Object, MockMapper.Object);

            // Act
            var result = await handler.HandleAsync(new CreateCustomerCommand(newCustomer.Name, newCustomer.Email));

            // Assert
            result.IsSuccess.Should().BeTrue();
            MockDbContext.Verify(m => m.SaveChangesAsync(It.IsAny<CancellationToken>()), Times.Once);
        }

        [Fact]
        public async Task GetAllCustomersQuery_ShouldReturnListOfCustomers()
        {
            // Arrange
            var customers = GenerateCustomers(5).AsQueryable();
            var mockDbSet = GetMockDbSet(customers);
            IEnumerable<CustomerDto> customerDtos = customers.Select(c => new CustomerDto
            {
                CustomerId = c.CustomerId,
                Name = c.Name,
                Email = c.Email
            }).ToList();

            MockMapper.Setup(m => m.Map<IEnumerable<CustomerDto>>(It.IsAny<List<Customer>>())).Returns(customerDtos);
            MockDbContext.Setup(db => db.Customers).Returns(mockDbSet.Object);

            var handler = new GetAllCustomersQueryHandler(MockDbContext.Object, MockMapper.Object);

            // Act
            var result = await handler.HandleAsync(new GetAllCustomersQuery());

            // Assert
            result.IsSuccess.Should().BeTrue();
            result.Value.Should().HaveCount(5);
            result.Value!.First().Name.Should().Be(customers.First().Name);
        }

        [Fact]
        public async Task GetCustomerByIdQuery_ShouldReturnCustomer_WhenCustomerExists()
        {
            // Arrange
            var customer = GenerateCustomers(1).First();
            var customerDto = new CustomerDto
            {
                CustomerId = customer.CustomerId,
                Name = customer.Name,
                Email = customer.Email
            };
            MockMapper.Setup(m => m.Map<CustomerDto>(customer)).Returns(customerDto);
            MockDbContext.Setup(db => db.Customers.FindAsync(new object[] { 1 }, It.IsAny<CancellationToken>()))
                .ReturnsAsync(customer);

            var handler = new GetCustomerByIdQueryHandler(MockDbContext.Object, MockMapper.Object);

            // Act
            var result = await handler.HandleAsync(new GetCustomerByIdQuery(1));

            // Assert
            result.IsSuccess.Should().BeTrue();
            result.Value!.CustomerId.Should().Be(customer.CustomerId);
        }

        [Fact]
        public async Task GetCustomerByIdQuery_ShouldReturnNotFound_WhenCustomerDoesNotExist()
        {
            // Arrange
            MockDbContext.Setup(db => db.Customers.FindAsync(new object[] { 1 }, It.IsAny<CancellationToken>()))
                .ReturnsAsync((Customer?)null);

            var handler = new GetCustomerByIdQueryHandler(MockDbContext.Object, MockMapper.Object);

            // Act
            var result = await handler.HandleAsync(new GetCustomerByIdQuery(1));

            // Assert
            result.IsFailure.Should().BeTrue();
            result.Error.Code.Should().Be("NotFound");
        }

        [Fact]
        public async Task GetCustomerWithOrdersQuery_ShouldReturnCustomerWithOrders_WhenCustomerExists()
        {
            // Arrange
            var customerId = 1;
            var customers = GenerateCustomersWithOrders(1, 1).AsQueryable();
            customers.First().CustomerId = customerId;
            var mockDbSet = GetMockDbSet(customers);

            var customerDto = new CustomerDto
            {
                CustomerId = customers.First().CustomerId,
                Name = customers.First().Name,
                Email = customers.First().Email,
                OrderDtos = customers.First().Orders.Select(o => new OrderDto
                {
                    OrderId = o.OrderId,
                    OrderDate = o.OrderDate,
                    CustomerId = customerId,
                    TotalPrice = o.TotalPrice
                }).ToList()
            };

            MockDbContext.Setup(db => db.Customers).Returns(mockDbSet.Object);
            MockMapper.Setup(m => m.Map<CustomerDto>(It.IsAny<Customer>())).Returns(customerDto);

            var handler = new GetCustomerWithOrdersQueryHandler(MockDbContext.Object, MockMapper.Object);

            // Act
            var result = await handler.HandleAsync(new GetCustomerWithOrdersQuery(customerId));

            // Assert
            result.IsSuccess.Should().BeTrue();
            result.Value!.CustomerId.Should().Be(1);
            result.Value.OrderDtos.Should().ContainSingle();
        }

        [Fact]
        public async Task GetCustomersByNameQuery_ShouldReturnListOfCustomers()
        {
            // Arrange
            var customers = GenerateCustomers(5).AsQueryable();
            var tempCustomers = customers.Select((c, index) => new Customer
            {
                CustomerId = c.CustomerId,
                Name = (index == 0 || index == 2) ? "JohnXXX" : c.Name,
                Email = c.Email
            }).AsQueryable();
            var filteredCustomers = tempCustomers.Where(c => c.Name == "JohnXXX");
            var mockDbSet = GetMockDbSet<Customer>(tempCustomers);
            var customerDtos = filteredCustomers.Select(c => new CustomerDto
            {
                CustomerId = c.CustomerId,
                Name = c.Name,
                Email = c.Email
            }).ToList();

            MockMapper.Setup(m => m.Map<IEnumerable<CustomerDto>>(It.IsAny<List<Customer>>()))
                .Returns(customerDtos);

            MockDbContext.Setup(db => db.Customers).Returns(mockDbSet.Object);

            var handler = new GetCustomersByNameQueryHandler(MockDbContext.Object, MockMapper.Object);

            // Act
            var result = await handler.HandleAsync(new GetCustomersByNameQuery("JohnXXX", 1, 10));

            // Assert
            result.IsSuccess.Should().BeTrue();
            result.Value.Should().HaveCount(2);
            result.Value!.First().Name.Should().Be("JohnXXX");
        }

        [Fact]
        public async Task UpdateCustomerCommand_ShouldReturnCustomerId_WhenCustomerIsUpdated()
        {
            // Arrange
            var customer = GenerateCustomers(1).First();
            MockDbContext.Setup(db => db.Customers.FindAsync(new object[] { 1 }, It.IsAny<CancellationToken>()))
                .ReturnsAsync(customer);
            MockDbContext.Setup(db => db.SaveChangesAsync(default)).ReturnsAsync(1);

            var handler = new UpdateCustomerCommandHandler(MockDbContext.Object, MockMapper.Object);

            // Act
            var result = await handler.HandleAsync(new UpdateCustomerCommand(1, "John Doe", "test@test1.com"));

            // Assert
            result.IsSuccess.Should().BeTrue();
            MockDbContext.Verify(m => m.SaveChangesAsync(It.IsAny<CancellationToken>()), Times.Once);
        }

        [Fact]
        public async Task UpdateCustomerCommand_ShouldReturnNotFound_WhenCustomerDoesNotExist()
        {
            // Arrange
            MockDbContext.Setup(db => db.Customers.FindAsync(new object[] { 1 }, It.IsAny<CancellationToken>()))
                .ReturnsAsync((Customer?)null);

            var handler = new UpdateCustomerCommandHandler(MockDbContext.Object, MockMapper.Object);

            // Act
            var result = await handler.HandleAsync(new UpdateCustomerCommand(1, "Updated Name", "updated@example.com"));

            // Assert
            result.IsFailure.Should().BeTrue();
            result.Error.Code.Should().Be("NotFound");
        }

        [Fact]
        public async Task DeleteCustomerCommand_ShouldReturnSuccess_WhenCustomerIsDeleted()
        {
            // Arrange
            var customer = GenerateCustomers(1).First();
            MockDbContext.Setup(db => db.Customers.FindAsync(new object[] { 1 }, It.IsAny<CancellationToken>()))
                .ReturnsAsync(customer);
            MockDbContext.Setup(db => db.Customers.Remove(It.IsAny<Customer>()));
            MockDbContext.Setup(db => db.SaveChangesAsync(default)).ReturnsAsync(1);

            var handler = new DeleteCustomerCommandHandler(MockDbContext.Object);

            // Act
            var result = await handler.HandleAsync(new DeleteCustomerCommand(1));

            // Assert
            result.IsSuccess.Should().BeTrue();
            MockDbContext.Verify(m => m.SaveChangesAsync(It.IsAny<CancellationToken>()), Times.Once);
        }

        [Fact]
        public async Task DeleteCustomerCommand_ShouldReturnNotFound_WhenCustomerDoesNotExist()
        {
            // Arrange
            MockDbContext.Setup(db => db.Customers.FindAsync(new object[] { 1 }, It.IsAny<CancellationToken>()))
                .ReturnsAsync((Customer?)null);

            var handler = new DeleteCustomerCommandHandler(MockDbContext.Object);

            // Act
            var result = await handler.HandleAsync(new DeleteCustomerCommand(1));

            // Assert
            result.IsFailure.Should().BeTrue();
            result.Error.Code.Should().Be("NotFound");
        }
    }
}
