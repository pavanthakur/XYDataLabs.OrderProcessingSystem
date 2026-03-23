using Microsoft.OpenApi.Models;
using Swashbuckle.AspNetCore.SwaggerGen;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

namespace XYDataLabs.OrderProcessingSystem.API.Swagger;

/// <summary>
/// Removes the per-endpoint X-Tenant-Code parameter from Swagger operations.
/// The tenant header is declared as a global ApiKey security scheme ("TenantCode")
/// at the document level so it appears once in the Swagger Authorize dialog and is
/// automatically injected into every API call — exactly like Bearer token auth.
/// This filter prevents the header appearing a second time on each endpoint.
/// </summary>
public sealed class RemoveTenantHeaderParameterFilter : IOperationFilter
{
    public void Apply(OpenApiOperation operation, OperationFilterContext context)
    {
        ArgumentNullException.ThrowIfNull(operation);
        ArgumentNullException.ThrowIfNull(context);

        if (operation.Parameters is null)
        {
            return;
        }

        var tenantParam = operation.Parameters.FirstOrDefault(parameter =>
            string.Equals(parameter.Name, TenantMiddleware.TenantHeaderName, StringComparison.OrdinalIgnoreCase)
            && parameter.In == ParameterLocation.Header);

        if (tenantParam is not null)
        {
            operation.Parameters.Remove(tenantParam);
        }
    }
}