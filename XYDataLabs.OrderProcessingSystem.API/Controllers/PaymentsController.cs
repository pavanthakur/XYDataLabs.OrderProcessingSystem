using Asp.Versioning;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using XYDataLabs.OrderProcessingSystem.API.Extensions;
using XYDataLabs.OrderProcessingSystem.API.Models;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Features.Payments.Commands;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Observability;

namespace XYDataLabs.OrderProcessingSystem.API.Controllers
{
    [ApiVersion("1.0")]
    [ApiController]
    [Route("api/v{version:apiVersion}/[controller]")]
    [EnableRateLimiting("payment-per-tenant")]
    public class PaymentsController : ControllerBase
    {
        private readonly IDispatcher _dispatcher;
        private readonly ILogger<PaymentsController> _logger;
        private readonly IPaymentTelemetryTracker _paymentTelemetryTracker;
        private readonly ITenantProvider _tenantProvider;

        public PaymentsController(
            IDispatcher dispatcher,
            ILogger<PaymentsController> logger,
            IPaymentTelemetryTracker paymentTelemetryTracker,
            ITenantProvider tenantProvider)
        {
            _dispatcher = dispatcher;
            _logger = logger;
            _paymentTelemetryTracker = paymentTelemetryTracker;
            _tenantProvider = tenantProvider;
        }

        /// <summary>
        ///    Creates a new customer, adds a card, and processes a payment in a single operation
        /// </summary>
        /// <param name="request">CustomerWithCardPaymentRequestDto</param>
        /// <param name="cancellationToken">Request cancellation token</param>
        /// <returns>Payment status</returns>
        [HttpPost("ProcessPayment")]
        public async Task<IActionResult> ProcessPayment([FromBody] CustomerWithCardPaymentRequestDto request, CancellationToken cancellationToken)
        {
            ArgumentNullException.ThrowIfNull(request);

            try
            {
                var result = await _dispatcher.SendAsync(new ProcessPaymentCommand(
                    request.Name,
                    request.Email,
                    request.DeviceSessionId,
                    request.CardNumber,
                    request.ExpirationYear,
                    request.ExpirationMonth,
                    request.Cvv2,
                    request.CustomerOrderId,
                    request.ClientCallbackOrigin), cancellationToken);
                return result.ToActionResult();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error processing payment");
                return StatusCode(500, new { message = "An error occurred while processing the payment" });
            }
        }

        [HttpPost("{paymentId}/confirm-status")]
        public async Task<IActionResult> ConfirmPaymentStatus(string paymentId, [FromBody] PaymentStatusLookupRequestDto request, CancellationToken cancellationToken)
        {
            ArgumentNullException.ThrowIfNull(request);

            try
            {
                _logger.LogInformation(
                    "Received payment status confirmation request for payment {PaymentId} and attempt order {AttemptOrderId}",
                    paymentId,
                    request.AttemptOrderId);

                var result = await _dispatcher.SendAsync(
                    new ConfirmPaymentStatusCommand(
                        paymentId,
                        request.AttemptOrderId,
                        request.CallbackStatus,
                        request.ErrorMessage,
                        request.CallbackParameters),
                    cancellationToken);

                return result.ToActionResult();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error confirming payment status for payment {PaymentId}", paymentId);
                return StatusCode(500, new { message = "An error occurred while confirming the payment status" });
            }
        }

        [HttpPost("/payment/client-event")]
        public IActionResult LogPaymentClientEvent([FromBody] PaymentClientEventRequest? request)
        {
            if (request is null || string.IsNullOrWhiteSpace(request.EventName))
            {
                return BadRequest();
            }

            if (!ModelState.IsValid)
            {
                return ValidationProblem(ModelState);
            }

            var eventName = NormalizeLogValue(request.EventName, 100) ?? "ui_payment_event";
            var severity = NormalizeLogValue(request.Severity, 16) ?? "information";
            var tenantCode = GetResolvedTenantCode();
            var normalizedClientFlowId = NormalizeLogValue(request.ClientFlowId, 64);
            var normalizedCustomerOrderId = NormalizeLogValue(request.CustomerOrderId, 128);
            var normalizedAttemptOrderId = NormalizeLogValue(request.AttemptOrderId, 128);
            var normalizedPaymentId = NormalizeLogValue(request.PaymentId, 128);
            var normalizedPaymentStatus = NormalizeLogValue(request.PaymentStatus, 64);
            var normalizedStatusCategory = NormalizeLogValue(request.StatusCategory, 32);
            var normalizedErrorCode = NormalizeLogValue(request.ErrorCode, 64);
            var normalizedErrorMessage = NormalizeLogValue(request.ErrorMessage, 512);
            var normalizedPagePath = NormalizeLogValue(request.PagePath, 256);
            var normalizedClientTimestampUtc = NormalizeLogValue(request.ClientTimestampUtc, 64);
            var clientFlowId = normalizedClientFlowId ?? "none";
            var customerOrderId = normalizedCustomerOrderId ?? "none";
            var attemptOrderId = normalizedAttemptOrderId ?? "none";
            var paymentId = normalizedPaymentId ?? "none";
            var paymentStatus = normalizedPaymentStatus ?? "none";
            var statusCategory = normalizedStatusCategory ?? "none";
            var errorCode = normalizedErrorCode ?? "none";
            var errorMessage = normalizedErrorMessage ?? "none";
            var pagePath = normalizedPagePath ?? "unknown";
            var clientTimestampUtc = normalizedClientTimestampUtc ?? "none";

            _paymentTelemetryTracker.Track(new PaymentTelemetryEvent
            {
                Application = "UI",
                EventName = eventName,
                TenantCode = _tenantProvider.HasTenantContext ? _tenantProvider.TenantCode : null,
                CustomerOrderId = normalizedCustomerOrderId,
                AttemptOrderId = normalizedAttemptOrderId,
                PaymentId = normalizedPaymentId,
                PaymentStatus = normalizedPaymentStatus,
                StatusCategory = normalizedStatusCategory,
                ClientFlowId = normalizedClientFlowId,
                PagePath = normalizedPagePath,
                HttpStatus = request.HttpStatus,
                ErrorCode = normalizedErrorCode,
                ErrorMessage = normalizedErrorMessage,
                ClientTimestampUtc = normalizedClientTimestampUtc,
                Severity = severity,
            });

            var logMessage =
                "UI payment event {UiEventName} on {PagePath} for tenant {TenantCode} customer order {CustomerOrderId} attempt {AttemptOrderId} payment {PaymentId} status {PaymentStatus} category {StatusCategory} http {HttpStatus} flow {ClientFlowId} client time {ClientTimestampUtc} error code {ErrorCode} message {ClientMessage}";

            switch (severity.ToUpperInvariant())
            {
                case "ERROR":
                    _logger.LogError(
                        logMessage,
                        eventName,
                        pagePath,
                        tenantCode,
                        customerOrderId,
                        attemptOrderId,
                        paymentId,
                        paymentStatus,
                        statusCategory,
                        request.HttpStatus,
                        clientFlowId,
                        clientTimestampUtc,
                        errorCode,
                        errorMessage);
                    break;
                case "WARNING":
                    _logger.LogWarning(
                        logMessage,
                        eventName,
                        pagePath,
                        tenantCode,
                        customerOrderId,
                        attemptOrderId,
                        paymentId,
                        paymentStatus,
                        statusCategory,
                        request.HttpStatus,
                        clientFlowId,
                        clientTimestampUtc,
                        errorCode,
                        errorMessage);
                    break;
                default:
                    _logger.LogInformation(
                        logMessage,
                        eventName,
                        pagePath,
                        tenantCode,
                        customerOrderId,
                        attemptOrderId,
                        paymentId,
                        paymentStatus,
                        statusCategory,
                        request.HttpStatus,
                        clientFlowId,
                        clientTimestampUtc,
                        errorCode,
                        errorMessage);
                    break;
            }

            return NoContent();
        }

        private string GetResolvedTenantCode()
        {
            if (!_tenantProvider.HasTenantContext)
            {
                return "none";
            }

            return NormalizeLogValue(_tenantProvider.TenantCode, 64) ?? "none";
        }

        private static string? NormalizeLogValue(string? value, int maxLength)
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                return null;
            }

            var trimmed = value.Trim();
            return trimmed.Length <= maxLength ? trimmed : trimmed[..maxLength];
        }
    }
}
