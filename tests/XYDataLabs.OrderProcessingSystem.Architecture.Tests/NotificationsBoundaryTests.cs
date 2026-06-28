using FluentAssertions;
using XYDataLabs.OrderProcessingSystem.Notifications.API;
using XYDataLabs.OrderProcessingSystem.Application.API.Services;

namespace XYDataLabs.OrderProcessingSystem.Architecture.Tests
{
    public class NotificationsBoundaryTests
    {
        [Fact]
        public void Notifications_API_Should_Stay_In_The_Application_Surface()
        {
            typeof(INotificationsModuleApi).Assembly.Should().NotBeSameAs(typeof(NotificationsService).Assembly);
            typeof(INotificationsModuleApi).Namespace.Should().Be("XYDataLabs.OrderProcessingSystem.Notifications.API");
            typeof(NotificationsService).Namespace.Should().Be("XYDataLabs.OrderProcessingSystem.Application.API.Services");
        }
    }
}

