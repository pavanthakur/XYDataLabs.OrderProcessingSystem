using FluentAssertions;
using XYDataLabs.OrderProcessingSystem.Application.Utilities;
using Xunit;

namespace XYDataLabs.OrderProcessingSystem.Application.Tests.Mappings;

public sealed class PaymentPendingStatusTests
{
    [Theory]
    [InlineData("authorized")]
    [InlineData("created")]
    public void UncapturedProviderState_IsNotSuccess(string status)
    {
        EnumHelper.NormalizeOpenPayStatus(status).Should().Be(status);
        EnumHelper.IsPendingStatus(status).Should().BeTrue();
        EnumHelper.IsSuccessStatus(status).Should().BeFalse();
        EnumHelper.IsFinalStatus(status).Should().BeFalse();
    }
}
