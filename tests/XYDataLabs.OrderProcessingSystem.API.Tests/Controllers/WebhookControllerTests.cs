using System.Text;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using Moq;
using XYDataLabs.OrderProcessingSystem.API.Controllers;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.Features.Webhooks.Commands;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.API.Tests.Controllers;

public sealed class WebhookControllerTests
{
    [Fact]
    public async Task ReceiveAsync_Extracts_Razorpay_EventType_FromPayload_WhenHeaderIsMissing()
    {
        var dispatcher = new Mock<IDispatcher>();
        var signatureValidator = new Mock<IWebhookSignatureValidator>();
        var logger = new Mock<ILogger<WebhookController>>();
        RecordWebhookEventCommand? capturedCommand = null;

        signatureValidator
            .Setup(validator => validator.Validate("Razorpay", It.IsAny<string>(), "valid-signature"))
            .Returns(true);

        dispatcher
            .Setup(dispatcherMock => dispatcherMock.SendAsync(It.IsAny<RecordWebhookEventCommand>(), It.IsAny<CancellationToken>()))
            .Callback<ICommand<Result<int>>, CancellationToken>((command, _) => capturedCommand = Assert.IsType<RecordWebhookEventCommand>(command))
            .ReturnsAsync(Result<int>.Success(42));

        var controller = new WebhookController(dispatcher.Object, signatureValidator.Object, logger.Object)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = CreateHttpContext("""{"event":"payment.captured","payload":{"payment":{"entity":{"id":"pay_123"}}}}""")
            }
        };

        controller.Request.Headers["X-Razorpay-Signature"] = "valid-signature";
        controller.Request.Headers["X-Razorpay-Event-Id"] = "evt_123";

        var result = await controller.ReceiveAsync("Razorpay", CancellationToken.None);

        Assert.IsType<AcceptedResult>(result);
        Assert.NotNull(capturedCommand);
        Assert.Equal("payment.captured", capturedCommand.EventType);
        Assert.Equal("evt_123", capturedCommand.ProviderEventId);
        Assert.Equal("Razorpay", capturedCommand.ProviderName);
    }

    private static DefaultHttpContext CreateHttpContext(string body)
    {
        var context = new DefaultHttpContext();
        context.Request.Body = new MemoryStream(Encoding.UTF8.GetBytes(body));
        context.Request.ContentType = "application/json";
        return context;
    }
}