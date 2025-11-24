using Microsoft.Extensions.Configuration;
using System.IO;
using Serilog;
using Serilog.Events;
using Microsoft.Extensions.Options;
using XYDataLabs.OrderProcessingSystem.Utilities;

// Bootstrap Serilog as early as possible so Log.* writes go to console immediately
// UI deployment test - Branch-based OIDC validation
// Testing automated deployment flow: Bootstrap → OIDC Setup → GitHub Secrets → Git Push → CI/CD Trigger
// This change validates the complete end-to-end deployment pipeline with branch-based OIDC authentication
Log.Logger = new LoggerConfiguration()
    .MinimumLevel.Information()
    .WriteTo.Console(outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] {Message:lj}{NewLine}{Exception}")
    .CreateBootstrapLogger();

Console.WriteLine("[EARLIEST DEBUG] Program.cs starting execution...");

var builder = WebApplication.CreateBuilder(args);

Console.WriteLine("[EARLIEST DEBUG] WebApplication.CreateBuilder completed...");

var isDocker = Environment.GetEnvironmentVariable("DOTNET_RUNNING_IN_CONTAINER") == "true";

Console.WriteLine("[EARLIEST DEBUG] Environment variable check completed...");

// Map .NET environment names to our simplified profile names
var environmentName = builder.Environment.EnvironmentName switch
{
    "Development" => Constants.Environments.Dev,
    "Staging" => Constants.Environments.Uat,
    "Production" => Constants.Environments.Production,
    _ => Constants.Environments.Dev // Default to dev for any other environment
};

Console.WriteLine("[EARLIEST DEBUG] Environment name mapping completed...");

// Configure Application Insights for environment-wise telemetry and logging
var appInsightsConnectionString = builder.Configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"] 
    ?? Environment.GetEnvironmentVariable("APPLICATIONINSIGHTS_CONNECTION_STRING");

if (!string.IsNullOrWhiteSpace(appInsightsConnectionString))
{
    builder.Services.AddApplicationInsightsTelemetry(options =>
    {
        options.ConnectionString = appInsightsConnectionString;
        options.EnableAdaptiveSampling = true;
        options.EnableQuickPulseMetricStream = true;
    });
    Log.Information("[CONFIG] Application Insights enabled for {Environment} environment", environmentName);
}
else
{
    Log.Warning("[CONFIG] Application Insights NOT configured - connection string missing for {Environment} environment", environmentName);
}

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
        .Enrich.WithProperty("Application", "UI")
        .Enrich.WithProperty("Runtime", isDocker ? "Docker" : "Local");

    if (isDocker)
    {
        // Docker: Use console output (primary) + file output 
        loggerConfiguration
            .WriteTo.Console(outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] [{Environment}] [{Runtime}] {Message:lj}{NewLine}{Exception}")
            .WriteTo.File(
                path: "/logs/ui-.log",
                rollingInterval: RollingInterval.Day,
                outputTemplate: "{Timestamp:yyyy-MM-dd HH:mm:ss.fff zzz} [{Level:u3}] [{Environment}] [{Runtime}] {Message:lj}{Exception}{NewLine}"
            );
    }
    else
    {
        // Non-Docker: Use file output + console
        loggerConfiguration
            .WriteTo.Console(outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] [{Environment}] [{Runtime}] {Message:lj}{NewLine}{Exception}")
            .WriteTo.File(
                path: "../logs/ui-.log",
                rollingInterval: RollingInterval.Day,
                outputTemplate: "{Timestamp:yyyy-MM-dd HH:mm:ss.fff zzz} [{Level:u3}] [{Environment}] [{Runtime}] {Message:lj}{Exception}{NewLine}"
            );
    }
});

Console.WriteLine("[CONSOLE DEBUG] Serilog configured using direct configuration");

// Test Serilog after configuration is complete
Log.Information("Serilog is now configured and working for UI in {Environment} environment (Docker: {IsDocker})", environmentName, isDocker);

ApiSettings apiSettings;
var activeSettings = SharedSettingsLoader.AddAndBindSettings(
    builder.Services,
    builder.Configuration,
    environmentName,
    isDocker,
    s => s.UI,
    out apiSettings,
    out _ // ignore useHttps
);

// Use SharedSettingsLoader to load sharedsettings.json
// var sharedConfig = SharedSettingsLoader.LoadSharedSettings(builder.Configuration, builder.Environment.EnvironmentName, isDocker);
// builder.Configuration.AddConfiguration((IConfiguration)sharedConfig);

// Remove ApiSettings binding from appsettings.json
// builder.Services.Configure<ApiSettings>(builder.Configuration.GetSection("ApiSettings"));
// Remove direct section access for ApiSettings
// useHttps = builder.Configuration.GetSection("ApiSettings:UI:https").Get<ApiSettingsSection>()?.HttpsEnabled ?? false;
if (Environment.GetEnvironmentVariable("USE_HTTPS") is string envHttps)
{
    activeSettings.HttpsEnabled = bool.TryParse(envHttps, out var parsed) ? parsed : activeSettings.HttpsEnabled;
}

builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAll", policy =>
    {
        policy.SetIsOriginAllowed(_ => true) // Allow any origin
              .AllowAnyMethod()
              .AllowAnyHeader()
              .AllowCredentials();
    });
});

// Register HttpClient using the dynamically generated Base URL
builder.Services.AddHttpClient("MyApiClient", (sp, client) =>
{
    var settings = sp.GetRequiredService<IOptions<ApiSettings>>().Value;
    var api = settings.API.GetActive(activeSettings.HttpsEnabled);

    var baseUrl = isDocker
        ? $"http://api:{settings.API.http.Port}"
        : api.GetBaseUrl();

    client.BaseAddress = new Uri(baseUrl);
});
Log.Information("[DEBUG] activeSettings.HttpsEnabled: {HttpsEnabled}, USE_HTTPS env: {UseHttpsEnv}", activeSettings.HttpsEnabled, Environment.GetEnvironmentVariable("USE_HTTPS"));
// Kestrel HTTPS configuration using ApiSettings
if (activeSettings.HttpsEnabled && !string.IsNullOrWhiteSpace(activeSettings.CertPath) && !string.IsNullOrWhiteSpace(activeSettings.CertPassword))
{
    Log.Information("[Kestrel] HTTPS enabled: Using certificate at {CertPath}", activeSettings.CertPath);
    builder.WebHost.ConfigureKestrel(options =>
    {
        options.ListenAnyIP(activeSettings.Port, listenOptions =>
        {
            listenOptions.UseHttps(activeSettings.CertPath, activeSettings.CertPassword);
        });
        options.ListenAnyIP(apiSettings.UI.http.Port); // HTTP fallback using configured port
    });
}
else
{
    Log.Information("[Kestrel] HTTPS NOT enabled: Only HTTP will be used.");
    builder.WebHost.ConfigureKestrel(options =>
    {
        options.ListenAnyIP(activeSettings.Port); // HTTP only using configured port
    });
}

// Add services to the container.
builder.Services.AddControllersWithViews();
builder.Services.AddRazorPages().AddRazorRuntimeCompilation();

var app = builder.Build();

// Log requests to help diagnose issues
app.UseSerilogRequestLogging();

SharedSettingsLoader.PrintApiSettingsDebug(apiSettings, activeSettings, "UI", isDocker);

// Configure the HTTP request pipeline.
if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Home/Error");
    app.UseHsts();
}

// Enable CORS before other middleware
//app.UseCors("AllowOpenPay");
app.UseCors("AllowAll");

// Only use HTTPS redirection if enabled in ApiSettings
if (activeSettings.HttpsEnabled)
{
    app.UseHttpsRedirection();
}

app.UseStaticFiles();
app.UseRouting();
app.UseAuthorization();
app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Home}/{action=Index}/{id?}");

try
{
    Log.Information("Starting UI web host");
    app.Run();
}
catch (Exception ex)
{
    Log.Fatal(ex, "UI application terminated unexpectedly");
    throw;
}
finally
{
    Log.CloseAndFlush();
}