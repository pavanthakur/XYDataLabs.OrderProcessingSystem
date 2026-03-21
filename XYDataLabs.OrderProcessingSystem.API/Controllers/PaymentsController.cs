using Microsoft.AspNetCore.Mvc;
using XYDataLabs.OrderProcessingSystem.API.Extensions;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Features.Payments.Commands;

namespace XYDataLabs.OrderProcessingSystem.API.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
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
        /// <returns>Payment status</returns>
        [HttpPost("ProcessPayment")]
        public async Task<IActionResult> ProcessPayment([FromBody] CustomerWithCardPaymentRequestDto request, CancellationToken cancellationToken)
        {
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
                    request.OrderId), cancellationToken);
                return result.ToActionResult();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error processing payment");
                return StatusCode(500, new { message = "An error occurred while processing the payment" });
            }
        }
    }
}
