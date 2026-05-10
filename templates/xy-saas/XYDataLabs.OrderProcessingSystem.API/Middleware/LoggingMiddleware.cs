using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

namespace XYDataLabs.OrderProcessingSystem.API.Middleware
{
    /// <summary>
    /// Middleware for logging HTTP requests and responses.
    /// </summary>
    public class LoggingMiddleware
    {
        private static readonly HashSet<string> SensitiveJsonFields = new(StringComparer.OrdinalIgnoreCase)
        {
            "name",
            "holder_name",
            "email",
            "cardNumber",
            "card_number",
            "cvv2",
            "deviceSessionId",
            "device_session_id",
            "token",
            "sourceId",
            "customerId"
        };

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
        public async Task InvokeAsync(HttpContext context, ITenantProvider tenantProvider)
        {
            ArgumentNullException.ThrowIfNull(context);
            ArgumentNullException.ThrowIfNull(tenantProvider);

            var request = context.Request;
            var requestTenantCode = ResolveTenantCode(context, tenantProvider);
            var requestBody = await TryGetSanitizedRequestBodyAsync(request);

            TryLogRequest(request, requestTenantCode, requestBody);

            var originalBodyStream = context.Response.Body;
            await using var memoryStream = new MemoryStream();
            context.Response.Body = memoryStream;

            try
            {
                await _next(context);
            }
            finally
            {
                await WriteResponseAndRestoreBodyAsync(context, tenantProvider, memoryStream, originalBodyStream);
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

        private static string SanitizeBody(string body)
        {
            if (string.IsNullOrWhiteSpace(body))
            {
                return string.Empty;
            }

            try
            {
                var jsonNode = JsonNode.Parse(body);
                if (jsonNode is not null)
                {
                    MaskSensitiveJsonValues(jsonNode);
                    return Truncate(jsonNode.ToJsonString());
                }
            }
            catch (JsonException)
            {
                // Fall through and log the original body when it is not JSON.
            }

            return Truncate(body);
        }

        private async Task<string> TryGetSanitizedRequestBodyAsync(HttpRequest request)
        {
            try
            {
                return SanitizeBody(await GetRequestBodyAsync(request));
            }
            catch (Exception ex)
            {
                _logger.LogWarning(
                    ex,
                    "Request body sanitization failed for {Method} {Path}. Falling back to raw truncated body.",
                    request.Method,
                    request.Path);

                return Truncate(await GetRequestBodyAsync(request));
            }
        }

        private async Task WriteResponseAndRestoreBodyAsync(
            HttpContext context,
            ITenantProvider tenantProvider,
            MemoryStream responseBuffer,
            Stream originalBodyStream)
        {
            try
            {
                responseBuffer.Seek(0, SeekOrigin.Begin);

                using var responseReader = new StreamReader(responseBuffer, Encoding.UTF8, leaveOpen: true);
                var responseBody = await responseReader.ReadToEndAsync();
                var sanitizedResponseBody = TrySanitizeResponseBody(context, responseBody);
                var responseTenantCode = ResolveTenantCode(context, tenantProvider);

                TryLogResponse(context, responseTenantCode, sanitizedResponseBody);

                responseBuffer.Seek(0, SeekOrigin.Begin);
                await responseBuffer.CopyToAsync(originalBodyStream);
            }
            finally
            {
                context.Response.Body = originalBodyStream;
            }
        }

        private void TryLogRequest(HttpRequest request, string tenantCode, string requestBody)
        {
            try
            {
                _logger.LogInformation(
                    "Request: {Method} {Url} {QueryString} Tenant: {TenantCode} Body: {RequestBody}",
                    request.Method,
                    request.Path,
                    request.QueryString,
                    tenantCode,
                    requestBody);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(
                    ex,
                    "Request logging failed for {Method} {Path} Tenant: {TenantCode}",
                    request.Method,
                    request.Path,
                    tenantCode);
            }
        }

        private void TryLogResponse(HttpContext context, string tenantCode, string responseBody)
        {
            try
            {
                _logger.LogInformation(
                    "Response: {StatusCode} Tenant: {TenantCode} Body: {ResponseBody}",
                    context.Response.StatusCode,
                    tenantCode,
                    responseBody);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(
                    ex,
                    "Response logging failed for {Method} {Path} Tenant: {TenantCode}",
                    context.Request.Method,
                    context.Request.Path,
                    tenantCode);
            }
        }

        private string TrySanitizeResponseBody(HttpContext context, string responseBody)
        {
            try
            {
                return SanitizeBody(responseBody);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(
                    ex,
                    "Response body sanitization failed for {Method} {Path}. Falling back to raw truncated body.",
                    context.Request.Method,
                    context.Request.Path);

                return Truncate(responseBody);
            }
        }

        private static void MaskSensitiveJsonValues(JsonNode node)
        {
            switch (node)
            {
                case JsonObject jsonObject:
                    foreach (var property in jsonObject.ToList())
                    {
                        if (property.Value is null)
                        {
                            continue;
                        }

                        if (SensitiveJsonFields.Contains(property.Key))
                        {
                            jsonObject[property.Key] = MaskSensitiveValue(property.Key, property.Value);
                            continue;
                        }

                        MaskSensitiveJsonValues(property.Value);
                    }
                    break;

                case JsonArray jsonArray:
                    foreach (var child in jsonArray)
                    {
                        if (child is not null)
                        {
                            MaskSensitiveJsonValues(child);
                        }
                    }
                    break;
            }
        }

        private static string MaskSensitiveValue(string propertyName, JsonNode value)
        {
            var stringValue = value switch
            {
                JsonValue jsonValue => jsonValue.TryGetValue<string>(out var exactString)
                    ? exactString ?? string.Empty
                    : jsonValue.ToJsonString().Trim('"'),
                _ => value.ToJsonString().Trim('"')
            };

            if (string.IsNullOrWhiteSpace(stringValue))
            {
                return string.Empty;
            }

            if (propertyName.Contains("email", StringComparison.OrdinalIgnoreCase))
            {
                var atIndex = stringValue.IndexOf('@');
                if (atIndex > 1)
                {
                    return $"{stringValue[0]}***{stringValue[atIndex..]}";
                }
            }

            if (propertyName.Contains("name", StringComparison.OrdinalIgnoreCase))
            {
                return $"{stringValue[0]}***";
            }

            if (stringValue.Length <= 4)
            {
                return "***";
            }

            return $"***{stringValue[^4..]}";
        }

        private static string Truncate(string body)
        {
            const int maxLength = 2048;

            return body.Length <= maxLength
                ? body
                : $"{body[..maxLength]}... [truncated]";
        }

        private static string ResolveTenantCode(HttpContext context, ITenantProvider tenantProvider)
        {
            if (tenantProvider.HasTenantContext && !string.IsNullOrWhiteSpace(tenantProvider.TenantCode))
            {
                return tenantProvider.TenantCode;
            }

            var requestedTenantCode = context.Request.Headers[TenantMiddleware.TenantHeaderName].FirstOrDefault();
            if (!string.IsNullOrWhiteSpace(requestedTenantCode))
            {
                return requestedTenantCode.Trim();
            }

            if (string.Equals(context.Request.Path.Value, "/payment/callback", StringComparison.OrdinalIgnoreCase))
            {
                var callbackTenantCode = context.Request.Query["tenantCode"].FirstOrDefault()?.Trim();
                return string.IsNullOrWhiteSpace(callbackTenantCode) ? "callback" : callbackTenantCode;
            }

            return string.Equals(context.Request.Path.Value, "/api/v1/info/runtime-configuration", StringComparison.OrdinalIgnoreCase)
                ? "bootstrap"
                : "none";
        }
    }
}
