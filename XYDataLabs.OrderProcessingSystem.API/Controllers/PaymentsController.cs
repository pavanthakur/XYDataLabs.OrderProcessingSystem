using Asp.Versioning;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using XYDataLabs.OrderProcessingSystem.API.Extensions;
using XYDataLabs.OrderProcessingSystem.API.Models;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Features.Payments.Commands;

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

        public PaymentsController(IDispatcher dispatcher, ILogger<PaymentsController> logger)
        {
            _dispatcher = dispatcher;
            _logger = logger;
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
                    request.CustomerOrderId), cancellationToken);
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
            var tenantCode = NormalizeLogValue(request.TenantCode, 64) ?? "none";
            var clientFlowId = NormalizeLogValue(request.ClientFlowId, 64) ?? "none";
            var customerOrderId = NormalizeLogValue(request.CustomerOrderId, 128) ?? "none";
            var attemptOrderId = NormalizeLogValue(request.AttemptOrderId, 128) ?? "none";
            var paymentId = NormalizeLogValue(request.PaymentId, 128) ?? "none";
            var paymentStatus = NormalizeLogValue(request.PaymentStatus, 64) ?? "none";
            var statusCategory = NormalizeLogValue(request.StatusCategory, 32) ?? "none";
            var errorCode = NormalizeLogValue(request.ErrorCode, 64) ?? "none";
            var errorMessage = NormalizeLogValue(request.ErrorMessage, 512) ?? "none";
            var pagePath = NormalizeLogValue(request.PagePath, 256) ?? "unknown";
            var clientTimestampUtc = NormalizeLogValue(request.ClientTimestampUtc, 64) ?? "none";

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
