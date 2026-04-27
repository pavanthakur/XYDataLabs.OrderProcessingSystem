using FluentValidation;
using Microsoft.AspNetCore.Mvc;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Observability;

namespace XYDataLabs.OrderProcessingSystem.API.Middleware
{
    /// <summary>
    /// Middleware to handle errors and exceptions in the request pipeline.
    /// </summary>
    public sealed class ErrorHandlingMiddleware
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
            ArgumentNullException.ThrowIfNull(context);

            try
            {
                await _next(context);
            }
            catch (Exception ex)
            {
                if (context.Response.HasStarted)
                {
                    _logger.LogWarning(ex, "Response already started for {Method} {Path}; rethrowing exception.", context.Request.Method, context.Request.Path);
                    throw;
                }

                var problemDetails = CreateProblemDetails(context, ex, out var statusCode, out var logLevel);
                BusinessMetrics.RecordProblemResponse(statusCode, problemDetails.Type);

                _logger.Log(
                    logLevel,
                    ex,
                    "Request {Method} {Path} failed with status {StatusCode}.",
                    context.Request.Method,
                    context.Request.Path,
                    statusCode);

                context.Response.Clear();
                context.Response.StatusCode = statusCode;
                context.Response.ContentType = "application/problem+json";

                await context.Response.WriteAsJsonAsync(
                    value: problemDetails,
                    type: problemDetails.GetType(),
                    options: null,
                    contentType: "application/problem+json");
            }
        }

        private static ProblemDetails CreateProblemDetails(HttpContext context, Exception exception, out int statusCode, out LogLevel logLevel)
        {
            ProblemDetails problemDetails = exception switch
            {
                ValidationException validationException => CreateValidationProblemDetails(context, validationException, out statusCode, out logLevel),
                TenantContextRequiredException tenantException => CreateTenantProblemDetails(context, tenantException, out statusCode, out logLevel),
                _ => CreateUnhandledProblemDetails(context, out statusCode, out logLevel)
            };

            problemDetails.Extensions["traceId"] = context.TraceIdentifier;

            var tenantProvider = context.RequestServices.GetService<ITenantProvider>();
            if (tenantProvider is not null && tenantProvider.HasTenantContext)
            {
                problemDetails.Extensions["tenantId"] = tenantProvider.TenantId;
                problemDetails.Extensions["tenantCode"] = tenantProvider.TenantCode;
            }

            return problemDetails;
        }

        private static ProblemDetails CreateValidationProblemDetails(
            HttpContext context,
            ValidationException exception,
            out int statusCode,
            out LogLevel logLevel)
        {
            statusCode = StatusCodes.Status400BadRequest;
            logLevel = LogLevel.Warning;

            var errors = exception.Errors
                .GroupBy(
                    error => string.IsNullOrWhiteSpace(error.PropertyName) ? string.Empty : error.PropertyName,
                    StringComparer.Ordinal)
                .ToDictionary(
                    group => group.Key,
                    group => group.Select(error => error.ErrorMessage).Distinct(StringComparer.Ordinal).ToArray(),
                    StringComparer.Ordinal);

            return new ValidationProblemDetails(errors)
            {
                Status = statusCode,
                Title = "Validation failed.",
                Detail = "One or more validation errors occurred.",
                Type = "urn:xydatalabs:problem:validation-failed",
                Instance = context.Request.Path
            };
        }

        private static ProblemDetails CreateTenantProblemDetails(
            HttpContext context,
            TenantContextRequiredException exception,
            out int statusCode,
            out LogLevel logLevel)
        {
            statusCode = StatusCodes.Status400BadRequest;
            logLevel = LogLevel.Warning;

            var problemDetails = new ProblemDetails
            {
                Status = statusCode,
                Title = "Tenant context is required.",
                Detail = exception.Message,
                Type = "urn:xydatalabs:problem:tenant-context-required",
                Instance = context.Request.Path
            };

            problemDetails.Extensions["requestName"] = exception.RequestName;
            return problemDetails;
        }

        private static ProblemDetails CreateUnhandledProblemDetails(HttpContext context, out int statusCode, out LogLevel logLevel)
        {
            statusCode = StatusCodes.Status500InternalServerError;
            logLevel = LogLevel.Error;

            return new ProblemDetails
            {
                Status = statusCode,
                Title = "An unexpected error occurred.",
                Detail = "The server encountered an unexpected condition. Review the trace identifier for diagnostics.",
                Type = "urn:xydatalabs:problem:unhandled-exception",
                Instance = context.Request.Path
            };
        }
    }
}
