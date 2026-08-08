using FluentAssertions;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

public sealed class DlqMessageEnvelopeHydratorTests
{
    [Theory]
    [InlineData("poison-message", "", null)]
    [InlineData("", "failed to deserialize payload", null)]
    [InlineData("", "", "validation failure")]
    [InlineData("", "", "unresolved integration event type")]
    public void IsPoison_Should_Return_True_For_Poison_Indicators(
        string deadLetterReason,
        string deadLetterDescription,
        string? failureReason)
    {
        DlqMessageEnvelopeHydrator.IsPoison(deadLetterReason, deadLetterDescription, failureReason)
            .Should()
            .BeTrue();
    }

    [Theory]
    [InlineData("transient broker failure", "retry later", null)]
    [InlineData("", "", "temporary network timeout")]
    public void IsPoison_Should_Return_False_For_Replayable_Indicators(
        string deadLetterReason,
        string deadLetterDescription,
        string? failureReason)
    {
        DlqMessageEnvelopeHydrator.IsPoison(deadLetterReason, deadLetterDescription, failureReason)
            .Should()
            .BeFalse();
    }
}
