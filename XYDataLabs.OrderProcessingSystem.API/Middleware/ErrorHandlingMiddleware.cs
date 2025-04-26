using System.Net;

namespace XYDataLabs.OrderProcessingSystem.API.Middleware
{
    /// <summary>
    /// Middleware to handle errors and exceptions in the request pipeline.
    /// </summary>
    public class ErrorHandlingMiddleware
    {
        private readonly RequestDelegate _next;
        private readonly ILogger<ErrorHandlingMiddleware> _logger;

        /// <summary>
        /// Initializes a new instance of the <see cref="ErrorHandlingMiddleware"/> class.
        /// </summary>
        /// <param name="requestDelegate">The next middleware in the pipeline.</param>
        /// <param name="logger">The logger to log error details.</param>
        public ErrorHandlingMiddleware(RequestDelegate requestDelegate, ILogger<ErrorHandlingMiddleware> logger)
        {
            _next = requestDelegate;
            _logger = logger;
        }

        /// <summary>
        /// Invokes the middleware to handle the HTTP context.
        /// </summary>
        /// <param name="context">The HTTP context.</param>
        /// <returns>A task that represents the completion of request processing.</returns>
        public async Task InvokeAsync(HttpContext context)
        {
            try
            {
                await _next(context);
            }
            catch (Exception ex)
            {
                // Log the exception details
                _logger.LogError(ex, "An unexpected error occurred.");

                // Set the response code to 500 and write a custom error message
                context.Response.StatusCode = (int)HttpStatusCode.InternalServerError;
                context.Response.ContentType = "application/json";

                var errorResponse = new
                {
                    message = "An unexpected error occurred. Please try again later."
                };
                await context.Response.WriteAsJsonAsync(errorResponse);
            }
        }
    }
}
