using Microsoft.AspNetCore.Http;
using System.Threading.Tasks;

namespace XYDataLabs.OrderProcessingSystem.API.Middleware
{
    public class TenantMiddleware
    {
        private readonly RequestDelegate _next;

        public TenantMiddleware(RequestDelegate next)
        {
            _next = next;
        }

        public async Task InvokeAsync(HttpContext context)
        {
            var tenantHeader = context.Request.Headers["X-Tenant-Code"];

            if (string.IsNullOrEmpty(tenantHeader))
            {
                context.Response.StatusCode = StatusCodes.Status403Forbidden;
                await context.Response.WriteAsync("Tenant header is missing");
                return;
            }

            // Add tenant logic here

            await _next(context);
        }
    }
}
