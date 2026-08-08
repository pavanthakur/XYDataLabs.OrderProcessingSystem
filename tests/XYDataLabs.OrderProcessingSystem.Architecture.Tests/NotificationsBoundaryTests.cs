using FluentAssertions;
using XYDataLabs.OrderProcessingSystem.Notifications.API;
using XYDataLabs.OrderProcessingSystem.Notifications.Features.Services;

namespace XYDataLabs.OrderProcessingSystem.Architecture.Tests
{
    public class NotificationsBoundaryTests
    {
        [Fact]
        public void Notifications_API_Should_Be_Implemented_By_The_Notifications_Module()
        {
            typeof(INotificationsModuleApi).Assembly.Should().NotBeSameAs(typeof(NotificationsService).Assembly);
            typeof(INotificationsModuleApi).Namespace.Should().Be("XYDataLabs.OrderProcessingSystem.Notifications.API");
            typeof(NotificationsService).Namespace.Should().Be("XYDataLabs.OrderProcessingSystem.Notifications.Features.Services");
        }
    }
}

