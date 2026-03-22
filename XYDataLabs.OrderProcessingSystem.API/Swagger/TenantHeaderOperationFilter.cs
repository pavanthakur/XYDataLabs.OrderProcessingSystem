using Microsoft.AspNetCore.Mvc.ApiExplorer;
using Microsoft.OpenApi.Models;
using Swashbuckle.AspNetCore.SwaggerGen;
using Microsoft.Extensions.Options;
using Microsoft.OpenApi.Any;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Configuration;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

namespace XYDataLabs.OrderProcessingSystem.API.Swagger;

public sealed class TenantHeaderOperationFilter : IOperationFilter
{
    private const string RuntimeConfigurationPathSuffix = "/info/runtime-configuration";
    private readonly TenantConfigurationOptions _tenantConfigurationOptions;

    public TenantHeaderOperationFilter(IOptions<TenantConfigurationOptions> tenantConfigurationOptions)
    {
        ArgumentNullException.ThrowIfNull(tenantConfigurationOptions);
        _tenantConfigurationOptions = tenantConfigurationOptions.Value;
    }

    public void Apply(OpenApiOperation operation, OperationFilterContext context)
    {
        ArgumentNullException.ThrowIfNull(operation);
        ArgumentNullException.ThrowIfNull(context);

        if (!RequiresTenantHeader(context.ApiDescription))
        {
            return;
        }

        operation.Parameters ??= new List<OpenApiParameter>();

        if (operation.Parameters.Any(parameter =>
                string.Equals(parameter.Name, TenantMiddleware.TenantHeaderName, StringComparison.OrdinalIgnoreCase)
                && parameter.In == ParameterLocation.Header))
        {
            return;
        }

        operation.Parameters.Add(new OpenApiParameter
        {
            Name = TenantMiddleware.TenantHeaderName,
            In = ParameterLocation.Header,
            Required = true,
            Description = $"Canonical tenant code required by multitenant middleware for tenant-scoped endpoints. In Swagger UI this header is controlled by the top tenant selector. Configured fallback tenant: {_tenantConfigurationOptions.ActiveTenantCode}.",
            Example = new OpenApiString(_tenantConfigurationOptions.ActiveTenantCode),
            Schema = new OpenApiSchema
            {
                Type = "string",
                Default = new OpenApiString(_tenantConfigurationOptions.ActiveTenantCode)
            }
        });
    }

    private static bool RequiresTenantHeader(ApiDescription apiDescription)
    {
        var relativePath = apiDescription.RelativePath;

        return !string.IsNullOrWhiteSpace(relativePath)
            && !relativePath.EndsWith(RuntimeConfigurationPathSuffix, StringComparison.OrdinalIgnoreCase);
    }
}