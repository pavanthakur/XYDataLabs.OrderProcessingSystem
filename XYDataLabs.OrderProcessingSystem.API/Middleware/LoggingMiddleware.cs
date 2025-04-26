using System.Text;

namespace XYDataLabs.OrderProcessingSystem.API.Middleware
{
    /// <summary>
    /// Middleware for logging HTTP requests and responses.
    /// </summary>
    public class LoggingMiddleware
    {
        private readonly ILogger<LoggingMiddleware> _logger;
        private readonly RequestDelegate _next;

        /// <summary>
        /// Initializes a new instance of the <see cref="LoggingMiddleware"/> class.
        /// </summary>
        /// <param name="requestDelegate">The next middleware in the pipeline.</param>
        /// <param name="logger">The logger instance.</param>
        public LoggingMiddleware(RequestDelegate requestDelegate, ILogger<LoggingMiddleware> logger)
        {
            _logger = logger;
            _next = requestDelegate;
        }

        /// <summary>
        /// Invokes the middleware to log the request and response.
        /// </summary>
        /// <param name="context">The HTTP context.</param>
        /// <returns>A task that represents the asynchronous operation.</returns>
        public async Task InvokeAsync(HttpContext context)
        {
            try
            {
                var request = context.Request;
                var requestBody = await GetRequestBodyAsync(request);
                _logger.LogInformation(@"Request: {Method} {Url} {QueryString} Body: {RequestBody}",
                    request.Method,
                    request.Path,
                    request.QueryString,
                    requestBody);

                var originalBodyStream = context.Response.Body;
                using (var memoryStream = new MemoryStream())
                {
                    context.Response.Body = memoryStream;

                    await _next(context);
                    context.Response.Body.Seek(0, SeekOrigin.Begin);

                    var responseBody = await new StreamReader(context.Response.Body).ReadToEndAsync();
                    _logger.LogInformation("Response: {StatusCode} Body: {ResponseBody}",
                        context.Response.StatusCode,
                        responseBody);
                    context.Response.Body.Seek(0, SeekOrigin.Begin);
                    await memoryStream.CopyToAsync(originalBodyStream);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "An error occurred while logging the request/response.");
                throw; // Re-throw the exception after logging
            }
        }

        /// <summary>
        /// Reads the request body as a string.
        /// </summary>
        /// <param name="request">The HTTP request.</param>
        /// <returns>A task that represents the asynchronous operation. The task result contains the request body as a string.</returns>
        private async Task<string> GetRequestBodyAsync(HttpRequest request)
        {
            if (request.ContentLength > 0 && request.Body.CanSeek)
            {
                request.EnableBuffering(); // Allows reading the request body multiple times
                using (var reader = new StreamReader(request.Body, Encoding.UTF8, leaveOpen: true))
                {
                    var body = await reader.ReadToEndAsync();
                    request.Body.Seek(0, SeekOrigin.Begin); // Reset the body stream position
                    return body;
                }
            }
            return string.Empty;
        }
    }
}
