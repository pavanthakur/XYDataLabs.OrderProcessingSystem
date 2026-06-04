using FluentAssertions;
using Moq;
using Razorpay.Api.Errors;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;
using XYDataLabs.RazorpayAdapter;

namespace XYDataLabs.OrderProcessingSystem.API.Tests.Payments;

/// <summary>
/// Unit tests for RazorpayPaymentGateway — the provider-neutral IPaymentProviderGateway
/// implementation that wraps IRazorpayAdapterService.
/// </summary>
public class RazorpayPaymentGatewayTests
{
    private readonly Mock<IRazorpayAdapterService> _mockAdapter;
    private readonly RazorpayPaymentGateway _sut;

    public RazorpayPaymentGatewayTests()
    {
        _mockAdapter = new Mock<IRazorpayAdapterService>();
        _mockAdapter.SetupGet(a => a.ProviderType).Returns(PaymentProviderTypes.Razorpay);
        _sut = new RazorpayPaymentGateway(_mockAdapter.Object);
    }

    // ------------------------------------------------------------------ ProviderType

    [Fact]
    public void ProviderType_ReturnsRazorpay()
    {
        _sut.ProviderType.Should().Be(PaymentProviderTypes.Razorpay);
    }

    // ------------------------------------------------------------------ CreateCustomerAsync (stub)

    [Fact]
    public async Task CreateCustomerAsync_ReturnsStubCustomer_WithNoProviderCall()
    {
        var result = await _sut.CreateCustomerAsync(
            new PaymentGatewayCreateCustomerRequest("John Doe", "john@example.com"));

        result.Should().NotBeNull();
        result.Id.Should().StartWith("razorpay-cust-");
        result.Name.Should().Be("John Doe");
        result.Email.Should().Be("john@example.com");

        _mockAdapter.Verify(
            a => a.CreateOrderAsync(It.IsAny<RazorpayCreateOrderRequest>(), It.IsAny<CancellationToken>()),
            Times.Never,
            "CreateCustomerAsync must not call the Razorpay API");
    }

    // ------------------------------------------------------------------ CreateCardTokenAsync (stub)

    [Fact]
    public async Task CreateCardTokenAsync_ReturnsStubToken_WithNoProviderCall()
    {
        var result = await _sut.CreateCardTokenAsync(
            new PaymentGatewayCreateCardTokenRequest("4111111111111111", "John Doe", "12", "25", "123", "device-session"));

        result.Should().NotBeNull();
        result.Id.Should().Be("razorpay-token-pending");

        _mockAdapter.Verify(
            a => a.CreateOrderAsync(It.IsAny<RazorpayCreateOrderRequest>(), It.IsAny<CancellationToken>()),
            Times.Never,
            "CreateCardTokenAsync must not call the Razorpay API");
    }

    // ------------------------------------------------------------------ CreateChargeAsync — happy path

    [Fact]
    public async Task CreateChargeAsync_CallsCreateOrderAsync_AndMapsResultCorrectly()
    {
        var createdAt = new DateTime(2025, 1, 15, 10, 0, 0, DateTimeKind.Utc);
        _mockAdapter
            .Setup(a => a.CreateOrderAsync(It.IsAny<RazorpayCreateOrderRequest>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new RazorpayOrderResult(
                OrderId: "order_ABC123",
                Status: "created",
                Amount: 100.00m,
                Currency: "USD",
                CreatedAt: createdAt));

        var request = new PaymentGatewayCreateChargeRequest(
            SourceId: "token-abc",
            Amount: 100.00m,
            Currency: "USD",
            Description: "Test order",
            DeviceSessionId: "dev-session",
            AttemptOrderId: "ORD-001-1",
            Use3DSecure: false,
            RedirectUrl: "https://example.com/callback",
            Customer: new PaymentGatewayCustomer("cust-1", "John Doe", "john@example.com"));

        var result = await _sut.CreateChargeAsync(request);

        result.Id.Should().Be("order_ABC123");
        result.Status.Should().Be("created");
        result.Amount.Should().Be(100.00m);
        result.RedirectUrl.Should().Be("https://example.com/callback");
        result.ErrorMessage.Should().BeNull();
    }

    [Fact]
    public async Task CreateChargeAsync_PassesCorrectAmountCurrencyAndReceipt()
    {
        RazorpayCreateOrderRequest? capturedRequest = null;
        _mockAdapter
            .Setup(a => a.CreateOrderAsync(It.IsAny<RazorpayCreateOrderRequest>(), It.IsAny<CancellationToken>()))
            .Callback<RazorpayCreateOrderRequest, CancellationToken>((req, _) => capturedRequest = req)
            .ReturnsAsync(new RazorpayOrderResult("order_xyz", "created", 99.50m, "INR", DateTime.UtcNow));

        var chargeRequest = new PaymentGatewayCreateChargeRequest(
            SourceId: "src",
            Amount: 99.50m,
            Currency: "INR",
            Description: "A test payment",
            DeviceSessionId: "ds",
            AttemptOrderId: "ORD-007-2",
            Use3DSecure: false,
            RedirectUrl: "https://example.com/callback",
            Customer: new PaymentGatewayCustomer("c1", "Jane", "jane@example.com"));

        await _sut.CreateChargeAsync(chargeRequest);

        capturedRequest.Should().NotBeNull();
        capturedRequest!.Amount.Should().Be(99.50m);
        capturedRequest.Currency.Should().Be("INR");
        capturedRequest.Receipt.Should().Be("ORD-007-2");
        capturedRequest.Notes.Should().Be("A test payment");
    }

    // ------------------------------------------------------------------ CreateChargeAsync — exception classification

    [Fact]
    public async Task CreateChargeAsync_ThrowsPaymentProviderCustomerActionException_WhenBadRequestError()
    {
        _mockAdapter
            .Setup(a => a.CreateOrderAsync(It.IsAny<RazorpayCreateOrderRequest>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new BadRequestError("Insufficient funds", "BAD_REQUEST_ERROR", 400));

        var request = new PaymentGatewayCreateChargeRequest(
            SourceId: "token-abc",
            Amount: 100.00m,
            Currency: "USD",
            Description: "Test",
            DeviceSessionId: "dev-session",
            AttemptOrderId: "ORD-001-1",
            Use3DSecure: false,
            RedirectUrl: "https://example.com/callback",
            Customer: new PaymentGatewayCustomer("cust-1", "John Doe", "john@example.com"));

        var act = () => _sut.CreateChargeAsync(request);

        await act.Should()
            .ThrowAsync<PaymentProviderCustomerActionException>(
                because: "Razorpay BadRequestError must be classified as a terminal customer-action failure");
    }

    [Fact]
    public async Task CreateChargeAsync_DoesNotWrap_GenericExceptions()
    {
        _mockAdapter
            .Setup(a => a.CreateOrderAsync(It.IsAny<RazorpayCreateOrderRequest>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new InvalidOperationException("SDK connection error"));

        var request = new PaymentGatewayCreateChargeRequest(
            SourceId: "token-abc",
            Amount: 100.00m,
            Currency: "USD",
            Description: "Test",
            DeviceSessionId: "dev-session",
            AttemptOrderId: "ORD-001-1",
            Use3DSecure: false,
            RedirectUrl: "https://example.com/callback",
            Customer: new PaymentGatewayCustomer("cust-1", "John Doe", "john@example.com"));

        var act = () => _sut.CreateChargeAsync(request);

        await act.Should()
            .ThrowAsync<InvalidOperationException>(
                because: "Non-BadRequestError exceptions must propagate as-is for Polly / caller handling");
    }

    // ------------------------------------------------------------------ GetChargeAsync — status normalization

    [Theory]
    [InlineData("captured", "completed")]
    [InlineData("failed", "failed")]
    [InlineData("created", "created")]
    [InlineData("authorized", "authorized")]
    public async Task GetChargeAsync_NormalizesRazorpayStatusToGatewayStatus(string razorpayStatus, string expectedStatus)
    {
        _mockAdapter
            .Setup(a => a.GetPaymentAsync(It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new RazorpayPaymentResult(
                PaymentId: "pay_abc",
                OrderId: "order_xyz",
                Status: razorpayStatus,
                Amount: 100.00m,
                Currency: "USD",
                CreatedAt: DateTime.UtcNow,
                ErrorCode: null,
                ErrorDescription: null));

        var result = await _sut.GetChargeAsync("pay_abc");

        result.Status.Should().Be(expectedStatus,
            because: $"Razorpay status '{razorpayStatus}' should normalize to '{expectedStatus}'");
    }

    [Fact]
    public async Task GetChargeAsync_IncludesErrorMessage_WhenPaymentFailed()
    {
        _mockAdapter
            .Setup(a => a.GetPaymentAsync(It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new RazorpayPaymentResult(
                PaymentId: "pay_failed",
                OrderId: null,
                Status: "failed",
                Amount: 100.00m,
                Currency: "USD",
                CreatedAt: DateTime.UtcNow,
                ErrorCode: "BAD_REQUEST_ERROR",
                ErrorDescription: "Your card has insufficient funds."));

        var result = await _sut.GetChargeAsync("pay_failed");

        result.ErrorMessage.Should().Contain("insufficient funds",
            because: "error description from Razorpay must be surfaced in the gateway charge result");
    }

    [Fact]
    public async Task GetChargeAsync_RejectsOrderIds_BeforeCallingAdapter()
    {
        var act = () => _sut.GetChargeAsync("order_ABC123");

        await act.Should()
            .ThrowAsync<ArgumentException>()
            .WithMessage("*Expected 'pay_' but got 'order_ABC123'*");

        _mockAdapter.Verify(
            a => a.GetPaymentAsync(It.IsAny<string>(), It.IsAny<CancellationToken>()),
            Times.Never,
            "order ids must be rejected before the Razorpay payment lookup is attempted");
    }
}
