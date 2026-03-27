using Asp.Versioning;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.RateLimiting;
using System.Threading.RateLimiting;
using XYDataLabs.OrderProcessingSystem.API.Middleware;
using XYDataLabs.OrderProcessingSystem.Application;
using XYDataLabs.OrderProcessingSystem.Infrastructure;
using Microsoft.OpenApi.Models;
using Serilog;
using Serilog.Events;
using Serilog.Sinks.ApplicationInsights.TelemetryConverters;
using System.Reflection;
using XYDataLabs.OrderProcessingSystem.SharedKernel;
using Microsoft.Extensions.Configuration;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.Infrastructure.SeedData;
using Microsoft.ApplicationInsights.Extensibility;
using System.Text.RegularExpressions;
using XYDataLabs.OrderProcessingSystem.Application.Utilities;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Configuration;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Observability;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Multitenancy;
using XYDataLabs.OrderProcessingSystem.Application.Features.Orders;
using XYDataLabs.OrderProcessingSystem.Application.Features.Customers;
using XYDataLabs.OrderProcessingSystem.Application.Features.Payments;

// Bootstrap Serilog as early as possible so Log.* writes go to console immediately
// Azure App Service Deployment - Fix for Application Not Starting
// Deployment Fix: Trigger API deployment to Azure App Service (dev environment)
// This deployment ensures the API application is properly deployed with Application Insights telemetry
// Deployment timestamp: 2025-12-08T05:21:00Z - Triggering deployment after bootstrap
Log.Logger = new LoggerConfiguration()
    .MinimumLevel.Information()
    .WriteTo.Console(outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] {Message:lj}{NewLine}{Exception}")
    .CreateBootstrapLogger();

var builder = WebApplication.CreateBuilder(args);

var isDocker = Environment.GetEnvironmentVariable("DOTNET_RUNNING_IN_CONTAINER") == "true";

// Detect Azure App Service using WEBSITE_SITE_NAME environment variable
var azureSiteName = Environment.GetEnvironmentVariable("WEBSITE_SITE_NAME");
var isAzure = !string.IsNullOrWhiteSpace(azureSiteName);
var runtimeLabel = isAzure ? "Azure" : (isDocker ? "Docker" : "Local");

// Map .NET environment names to our simplified profile names
var environmentName = builder.Environment.EnvironmentName switch
{
    "Development" => Constants.Environments.Dev,
    "Staging" => Constants.Environments.Staging, 
    "Production" => Constants.Environments.Production,
    _ => Constants.Environments.Dev // Default to dev for any other environment
};

// Log configuration initialization
Console.WriteLine("═══════════════════════════════════════════════════════════════");
Console.WriteLine($"[CONFIG] API Initialization - Environment: {environmentName}");
Console.WriteLine($"[CONFIG] Azure App Service: {(isAzure ? "YES" : "NO")}");
Console.WriteLine($"[CONFIG] Docker Container: {(isDocker ? "YES" : "NO")}");
if (isAzure)
{
    Console.WriteLine($"[CONFIG] Key Vault is REQUIRED for Azure deployments (enterprise security policy)");
}
Console.WriteLine("═══════════════════════════════════════════════════════════════");

// Centralized loading, binding, and active ApiSettings selection
// IMPORTANT: For Azure deployments, this will fail if Key Vault is not properly configured
ApiSettings apiSettings;
ApiSettingsSection activeSettings;
try
{
    activeSettings = SharedSettingsLoader.AddAndBindSettings(
        builder.Services,
        builder.Configuration,
        environmentName,
        isDocker,
        s => s.API,
        out apiSettings,
        out _ // ignore useHttps
    );
    
    if (isAzure)
    {
        Console.WriteLine("[CONFIG] ✅ Configuration loaded successfully from Azure Key Vault");
    }
}
catch (Exception ex)
{
    Console.WriteLine($"[FATAL] Configuration initialization failed: {ex.Message}");
    throw; // Re-throw to stop application startup
}

// Verify DB connection string presence (mask password before logging)
var dbConn = builder.Configuration.GetConnectionString(Constants.Configuration.OrderProcessingSystemDbConnectionString);
if (string.IsNullOrWhiteSpace(dbConn))
{
    Console.WriteLine($"[CONFIG ERROR] ConnectionStrings:{Constants.Configuration.OrderProcessingSystemDbConnectionString} is missing or empty. Check sharedsettings.dev.json at solution root.");
}
else
{
    var masked = Regex.Replace(dbConn, @"(?i)(Password|Pwd)=([^;]+)", "$1=***");
    Console.WriteLine($"[CONFIG] Resolved DB connection: {masked}");
}

builder.Services.AddSingleton<IHttpContextAccessor, HttpContextAccessor>(); // Required for LoggingMiddleware
builder.Services.AddScoped<ITenantProvider, HeaderTenantProvider>();
builder.Services.AddScoped<ITenantResolver, EntityFrameworkTenantResolver>();
builder.Services.AddSingleton(TimeProvider.System);

// Configure Application Insights for environment-wise telemetry and logging
var applicationInsightsOptions = ApplicationInsightsOptions.FromConfiguration(builder.Configuration);
var appInsightsConnectionString = applicationInsightsOptions.ConnectionString;

if (!string.IsNullOrWhiteSpace(appInsightsConnectionString))
{
    try
    {
        builder.Services.AddApplicationInsightsTelemetry(options =>
        {
            options.ConnectionString = appInsightsConnectionString;
            options.EnableAdaptiveSampling = true;
            options.EnableQuickPulseMetricStream = true;
        });
        Log.Information("[CONFIG] Application Insights enabled for {Environment} environment", environmentName);
    }
    catch (Exception ex)
    {
        Log.Error(ex, "[CONFIG] Failed to configure Application Insights for {Environment} environment - application will continue without telemetry", environmentName);
    }
}
else
{
    Log.Warning("[CONFIG] Application Insights NOT configured - connection string missing for {Environment} environment", environmentName);
}

// OpenTelemetry distributed tracing and metrics (Phase 3 — Observability)
builder.Services.AddObservability(
    "OrderProcessingSystem.API",
    builder.Configuration,
    OrderActivitySource.Name,
    CustomerActivitySource.Name,
    PaymentActivitySource.Name);

builder.Services.AddCors(options =>
{
    // Development / Staging / local Docker: permissive policy for inner-loop convenience.
    options.AddPolicy("AllowAll", policy =>
    {
        policy.SetIsOriginAllowed(_ => true) // Allow any origin
              .AllowAnyMethod()
              .AllowAnyHeader()
              .AllowCredentials();
    });

    // Production (Azure): restrict to the known UI origin derived from the API site name.
    // The UI App Service name follows the pattern: replace "-api-xyapp-" with "-ui-xyapp-".
    var uiOrigin = !string.IsNullOrWhiteSpace(azureSiteName)
        ? $"https://{azureSiteName.Replace("-api-xyapp-", "-ui-xyapp-", StringComparison.Ordinal)}.azurewebsites.net"
        : null;

    options.AddPolicy("AllowProductionUI", policy =>
    {
        var origins = new List<string>();
        if (!string.IsNullOrWhiteSpace(uiOrigin))
            origins.Add(uiOrigin);

        if (origins.Count > 0)
            policy.WithOrigins([.. origins]).AllowAnyMethod().AllowAnyHeader().AllowCredentials();
        else
            policy.SetIsOriginAllowed(_ => false); // no origins configured — block all
    });
});

builder.InjectInfrastructureDependencies();
builder.InjectApplicationDependencies();

// Health checks — /health/live (liveness), /health/ready (SQL + Redis), /health (backward compat)
var healthChecksBuilder = builder.Services.AddHealthChecks();
var dbConnForHealth = builder.Configuration.GetConnectionString(Constants.Configuration.OrderProcessingSystemDbConnectionString);
if (!string.IsNullOrWhiteSpace(dbConnForHealth))
    healthChecksBuilder.AddSqlServer(dbConnForHealth, name: "sqlserver", tags: new[] { "ready" });
var redisConnForHealth = builder.Configuration.GetConnectionString("Redis");
if (!string.IsNullOrWhiteSpace(redisConnForHealth))
    healthChecksBuilder.AddRedis(redisConnForHealth, name: "redis", tags: new[] { "ready" });

// Rate limiting — 2-tier fixed window per tenant (keyed on X-Tenant-Code header)
// TenantMiddleware validates the header first; rate limiting never fires on missing/invalid tenants.
// payment-per-tenant : 20 req/min  — payment endpoints (card tokenisation, charge creation)
// api-per-tenant     : 200 req/min — orders and customers
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;

    options.AddPolicy("payment-per-tenant", httpContext =>
    {
        var tenantCode = httpContext.Request.Headers["X-Tenant-Code"].FirstOrDefault() ?? "anonymous";
        return RateLimitPartition.GetFixedWindowLimiter(tenantCode, _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = 20,
            Window = TimeSpan.FromMinutes(1),
            QueueProcessingOrder = QueueProcessingOrder.OldestFirst,
            QueueLimit = 0
        });
    });

    options.AddPolicy("api-per-tenant", httpContext =>
    {
        var tenantCode = httpContext.Request.Headers["X-Tenant-Code"].FirstOrDefault() ?? "anonymous";
        return RateLimitPartition.GetFixedWindowLimiter(tenantCode, _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = 200,
            Window = TimeSpan.FromMinutes(1),
            QueueProcessingOrder = QueueProcessingOrder.OldestFirst,
            QueueLimit = 0
        });
    });
});

builder.Services.AddControllers();

var tenantConfigurationOptions = builder.Configuration
    .GetSection(TenantConfigurationOptions.SectionName)
    .Get<TenantConfigurationOptions>() ?? new TenantConfigurationOptions();

// API Versioning — URL segment: /api/v1/[controller]
builder.Services.AddApiVersioning(options =>
{
    options.DefaultApiVersion = new ApiVersion(1, 0);
    options.AssumeDefaultVersionWhenUnspecified = true;
    options.ReportApiVersions = true;
    options.ApiVersionReader = new UrlSegmentApiVersionReader();
}).AddApiExplorer(options =>
{
    options.GroupNameFormat = "'v'VVV";
    options.SubstituteApiVersionInUrl = true;
});

// Register Swagger services
builder.Services.AddEndpointsApiExplorer();// Required for generating Swagger API documentation
builder.Services.AddSwaggerGen(options =>
{
    var xmlFile = $"{Assembly.GetExecutingAssembly().GetName().Name}.xml";
    var xmlPath = Path.Combine(AppContext.BaseDirectory, xmlFile);

    // Tenant header is injected automatically by the Swagger UI requestInterceptor below
    // (reading window.OrderProcessingActiveTenant set by the top-bar dropdown).
    // No security scheme / Authorize button / lock icons needed.

    if (File.Exists(xmlPath))
    {
        options.IncludeXmlComments(xmlPath);
    }
    else
    {
        // Log a warning or handle the missing file scenario
        Console.WriteLine($"Warning: XML comments file '{xmlPath}' not found.");
    }

    // Optionally, you can customize the Swagger UI or API info
    options.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = $"OrderProcessingSystem API - {environmentName.ToUpper()} Environment",
        Version = "v1",
        Description = $"OrderProcessingSystem API with Customer, Order endpoints running in {environmentName.ToUpper()} environment" + 
                     $" [{runtimeLabel}]" +
                     $" | Active Tenant: {tenantConfigurationOptions.ActiveTenantCode}",
    });
    
    // Add server configuration for proper Swagger API calls
    // When running on Azure App Service, use the Azure domain; otherwise use configured settings
    var serverUrl = isAzure
        ? $"https://{azureSiteName}.azurewebsites.net"
        : activeSettings.GetBaseUrl();
    options.AddServer(new OpenApiServer 
    { 
        Url = serverUrl,
        Description = isAzure ? $"Azure {environmentName.ToUpper()} Server" : $"{environmentName.ToUpper()} Server"
    });
});

// Configure Serilog with environment-aware paths  
builder.Host.UseSerilog((context, services, loggerConfiguration) =>
{
    loggerConfiguration
        .MinimumLevel.Information()
        .MinimumLevel.Override("Microsoft", LogEventLevel.Warning)
        .MinimumLevel.Override("Microsoft.AspNetCore.Hosting.Diagnostics", LogEventLevel.Error)
        .MinimumLevel.Override("Microsoft.Hosting.Lifetime", LogEventLevel.Information)
        .Enrich.FromLogContext()
        .Enrich.WithProperty("Environment", environmentName)
        .Enrich.WithProperty("Application", "API")
        .Enrich.WithProperty("Runtime", runtimeLabel);

    var telemetryConfiguration = services.GetService<TelemetryConfiguration>();
    if (telemetryConfiguration is not null)
    {
        loggerConfiguration.WriteTo.ApplicationInsights(telemetryConfiguration, TelemetryConverter.Traces);
    }

    if (isDocker)
    {
        // Each environment profile writes to its own file (e.g. webapi-dev-, webapi-prod-) to prevent
        // concurrent write conflicts when multiple Docker profiles run against the same host volume.
        loggerConfiguration
            .WriteTo.Console(outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] [{Environment}] [{Runtime}] [Tenant:{TenantCode}] [ReqTenant:{RequestedTenantCode}] {Message:lj}{NewLine}{Exception}")
            .WriteTo.File(
                path: $"/logs/webapi-{environmentName}-.log",
                rollingInterval: RollingInterval.Day,
                outputTemplate: "{Timestamp:yyyy-MM-dd HH:mm:ss.fff zzz} [{Level:u3}] [{Environment}] [{Runtime}] [Tenant:{TenantCode}] [ReqTenant:{RequestedTenantCode}] {Message:lj}{Exception}{NewLine}"
            );
    }
    else
    {
        loggerConfiguration
            .WriteTo.Console(outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] [{Environment}] [{Runtime}] [Tenant:{TenantCode}] [ReqTenant:{RequestedTenantCode}] {Message:lj}{NewLine}{Exception}")
            .WriteTo.File(
                path: $"../logs/webapi-{environmentName}-.log",
                rollingInterval: RollingInterval.Day,
                outputTemplate: "{Timestamp:yyyy-MM-dd HH:mm:ss.fff zzz} [{Level:u3}] [{Environment}] [{Runtime}] [Tenant:{TenantCode}] [ReqTenant:{RequestedTenantCode}] {Message:lj}{Exception}{NewLine}"
            );
    }
});

Log.Information("Serilog is now configured and working for API in {Environment} environment (Docker: {IsDocker})", environmentName, isDocker);

// Kestrel HTTPS configuration using ApiSettings
if (activeSettings.HttpsEnabled && !string.IsNullOrWhiteSpace(activeSettings.CertPath) && !string.IsNullOrWhiteSpace(activeSettings.CertPassword))
{
    Console.WriteLine($"[Kestrel] HTTPS enabled: Using certificate at {activeSettings.CertPath}");
    builder.WebHost.ConfigureKestrel(options =>
    {
        options.ListenAnyIP(activeSettings.Port, listenOptions =>
        {
            listenOptions.UseHttps(activeSettings.CertPath, activeSettings.CertPassword);
        });
        options.ListenAnyIP(apiSettings.API.http.Port); // HTTP fallback using configured port
    });
}
else
{
    Console.WriteLine("[Kestrel] HTTPS NOT enabled: Only HTTP will be used.");
    builder.WebHost.ConfigureKestrel(options =>
    {
        options.ListenAnyIP(activeSettings.Port); // HTTP only using configured port
    });
}

var app = builder.Build();

static void ConfigureApiExceptionHandler(IApplicationBuilder errorApp)
{
    errorApp.Run(async context =>
    {
        context.Response.StatusCode = StatusCodes.Status500InternalServerError;
        context.Response.ContentType = "application/json";
        await context.Response.WriteAsJsonAsync(new { message = "An unexpected error occurred. Please try again later." });
    });
}

// Initialize database and AppMasterData during startup
using (var scope = app.Services.CreateScope())
{
    try
    {
        // Apply migrations locally/Docker; skip on Azure (managed via pipelines)
        var dbContext = scope.ServiceProvider.GetRequiredService<OrderProcessingSystemDbContext>();
        DbInitializer.Initialize(dbContext, app.Configuration, applyMigrations: !isAzure);

        Log.Information("Database initialized successfully during startup");
    }
    catch (Exception ex)
    {
        Log.Fatal(ex, "Failed to initialize database during startup");
        throw;
    }
}

SharedSettingsLoader.PrintApiSettingsDebug(apiSettings, activeSettings, "API", isDocker);

app.UseStaticFiles();

// Add Serilog request logging
app.UseSerilogRequestLogging(options =>
{
    options.MessageTemplate = "HTTP {RequestMethod} {RequestPath} responded {StatusCode} in {Elapsed:0.0000} ms for tenant {TenantCode}";
    options.EnrichDiagnosticContext = (diagnosticContext, httpContext) =>
    {
        var tenantCode = ResolveTenantCodeForLogging(httpContext);
        var requestedTenantCode = httpContext.Request.Headers[TenantMiddleware.TenantHeaderName].FirstOrDefault();

        diagnosticContext.Set("TenantCode", tenantCode);
        diagnosticContext.Set(
            "RequestedTenantCode",
            string.IsNullOrWhiteSpace(requestedTenantCode) ? "none" : requestedTenantCode.Trim());
        diagnosticContext.Set("TenantHeaderName", TenantMiddleware.TenantHeaderName);
    };
});

var useDeveloperExceptionPage = builder.Environment.IsDevelopment() && !isAzure;

// Configure the HTTP request pipeline.
// Environment-specific middleware configuration using our simplified profile names
if (environmentName == Constants.Environments.Dev || environmentName == Constants.Environments.Staging)
{
    // Enable Swagger for Development and Staging environments
    app.UseSwagger();
    app.UseSwaggerUI(options =>
    {
        // Use relative path for Docker compatibility
        options.SwaggerEndpoint("/swagger/v1/swagger.json", "OrderProcessingSystem API v1");
        options.RoutePrefix = "swagger"; // Set Swagger UI to /swagger/index.html
        options.InjectJavascript("/swagger-assets/tenant-selector.js");
        // Inject X-Tenant-Code on every Swagger request using the value set by the
        // top-bar dropdown (window.OrderProcessingActiveTenant). When login is added,
        // that code will set the same global — no other changes needed here.
        options.UseRequestInterceptor("(req) => { const t = window.OrderProcessingActiveTenant; if (t) req.headers['X-Tenant-Code'] = t; return req; }");
    });
    
    if (useDeveloperExceptionPage)
    {
        app.UseDeveloperExceptionPage();
    }
    else
    {
        app.UseExceptionHandler(ConfigureApiExceptionHandler);
    }
}
else
{
    // Production and any unrecognised environment: Swagger disabled, HSTS enforced.
    app.UseExceptionHandler(ConfigureApiExceptionHandler);
    app.UseHsts();

    // Short-circuit /swagger/* before TenantMiddleware so the caller gets a clear
    // intentional message rather than the generic "Missing required header 'X-Tenant-Code'" 400.
    // Derive the dev Swagger URL dynamically — no hardcoded account names.
    //   Azure:       swap the env segment in WEBSITE_SITE_NAME (same pattern used for CORS origin).
    //   Docker/Local: read the dev API http port from sharedsettings.dev.json.
    string devSwaggerUrl;
    if (isAzure && !string.IsNullOrWhiteSpace(azureSiteName))
    {
        // e.g. "myorg-orderprocessing-api-xyapp-prod" → "myorg-orderprocessing-api-xyapp-dev"
        var devSiteName = azureSiteName.Replace(
            $"-xyapp-{environmentName}",
            $"-xyapp-{Constants.Environments.Dev}",
            StringComparison.Ordinal);
        devSwaggerUrl = $"https://{devSiteName}.azurewebsites.net/swagger";
    }
    else
    {
        // Docker: published app root is /app; Local: AppContext.BaseDirectory is bin/Debug/net8.0/.
        // sharedsettings.dev.json is copied alongside the binary in both cases.
        var devSettingsPath = Path.Combine(AppContext.BaseDirectory, "Resources", "Configuration",
            $"sharedsettings.{Constants.Environments.Dev}.json");
        var devConfig = new ConfigurationBuilder()
            .AddJsonFile(devSettingsPath, optional: true)
            .Build();
        var devApiHttpPort = devConfig.GetValue<int>("ApiSettings:API:http:Port", defaultValue: 5020);
        devSwaggerUrl = $"http://localhost:{devApiHttpPort}/swagger";
    }

    app.Use(async (context, next) =>
    {
        if (context.Request.Path.StartsWithSegments("/swagger"))
        {
            context.Response.StatusCode = StatusCodes.Status404NotFound;
            context.Response.ContentType = "application/json";
            await context.Response.WriteAsJsonAsync(new
            {
                message = "Swagger UI is not available in the Production environment.",
                reason = "API documentation is intentionally disabled in production. Use the dev or staging environment to explore the API.",
                environment = environmentName,
                swaggerAvailableAt = devSwaggerUrl
            });
            return;
        }
        await next(context);
    });
}

// Enable CORS before other middleware.
// Production (Azure) uses origin-restricted policy; all other environments use AllowAll.
var corsPolicy = (isAzure && string.Equals(environmentName, Constants.Environments.Production, StringComparison.Ordinal))
    ? "AllowProductionUI"
    : "AllowAll";
app.UseCors(corsPolicy);

// Only use HTTPS redirection if enabled in ApiSettings
if (activeSettings.HttpsEnabled)
{
    app.UseHttpsRedirection();
}

app.UseAuthorization();

app.UseMiddleware<TenantMiddleware>();

// Rate limiter after TenantMiddleware — tenant is validated first, so the partition key
// is always a known tenant code. Missing/invalid tenant requests are already rejected
// 400/403 before any rate-limit counter is evaluated.
app.UseRateLimiter();

app.UseMiddleware<CorrelationMiddleware>();

app.UseMiddleware<LoggingMiddleware>();

app.UseMiddleware<ErrorHandlingMiddleware>();

app.MapControllers();

// Liveness — no dependency checks; always 200 if the process is running (App Service liveness probe)
app.MapHealthChecks("/health/live", new HealthCheckOptions { Predicate = _ => false });
// Readiness — SQL Server + Redis (when configured); only "ready"-tagged checks (App Service readiness probe)
app.MapHealthChecks("/health/ready", new HealthCheckOptions { Predicate = check => check.Tags.Contains("ready") });
// Backward-compat alias — used by manage-appservice-slots.ps1 warmup URL
app.MapHealthChecks("/health", new HealthCheckOptions { Predicate = check => check.Tags.Contains("ready") });

if (isAzure)
{
    Console.WriteLine($"[DEBUG] API is running on Azure App Service: https://{azureSiteName}.azurewebsites.net");
}
else
{
    Console.WriteLine($"[DEBUG] API is running and listening on https://{activeSettings.Host}:{activeSettings.Port} (or http://{activeSettings.Host}:{apiSettings.API.http.Port})");
}

try
{
    Log.Information("Starting API web host - Branch-based deployment enabled");
    app.Run();
}
catch (Exception ex)
{
    Log.Fatal(ex, "API application terminated unexpectedly");
    throw;
}
finally
{
    Log.CloseAndFlush();
}

static string ResolveTenantCodeForLogging(HttpContext httpContext)
{
    var tenantProvider = httpContext.RequestServices.GetService<ITenantProvider>();
    if (tenantProvider is not null && tenantProvider.HasTenantContext && !string.IsNullOrWhiteSpace(tenantProvider.TenantCode))
    {
        return tenantProvider.TenantCode;
    }

    var requestedTenantCode = httpContext.Request.Headers[TenantMiddleware.TenantHeaderName].FirstOrDefault();
    if (!string.IsNullOrWhiteSpace(requestedTenantCode))
    {
        return requestedTenantCode.Trim();
    }

    return string.Equals(httpContext.Request.Path.Value, "/api/v1/info/runtime-configuration", StringComparison.OrdinalIgnoreCase)
        ? "bootstrap"
        : "none";
}

// Required for WebApplicationFactory<Program> in integration tests
public partial class Program { }
