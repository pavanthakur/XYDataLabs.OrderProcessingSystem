using AutoMapper;
using XYDataLabs.OrderProcessingSystem.API.Middleware;
using XYDataLabs.OrderProcessingSystem.Application;
using Microsoft.Extensions.Options;
using Microsoft.OpenApi.Models;
using Serilog;
using Serilog.Events;
using System.Reflection;
using XYDataLabs.OrderProcessingSystem.Utilities;
using Microsoft.Extensions.Configuration;
using System.Text.RegularExpressions;
using XYDataLabs.OrderProcessingSystem.Application.Utilities;

// Bootstrap Serilog as early as possible so Log.* writes go to console immediately
Log.Logger = new LoggerConfiguration()
    .MinimumLevel.Information()
    .WriteTo.Console(outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] {Message:lj}{NewLine}{Exception}")
    .CreateBootstrapLogger();

var builder = WebApplication.CreateBuilder(args);

var isDocker = Environment.GetEnvironmentVariable("DOTNET_RUNNING_IN_CONTAINER") == "true";

// Map .NET environment names to our simplified profile names
var environmentName = builder.Environment.EnvironmentName switch
{
    "Development" => Constants.Environments.Dev,
    "Staging" => Constants.Environments.Uat, 
    "Production" => Constants.Environments.Production,
    _ => Constants.Environments.Dev // Default to dev for any other environment
};

// Centralized loading, binding, and active ApiSettings selection
ApiSettings apiSettings;
var activeSettings = SharedSettingsLoader.AddAndBindSettings(
    builder.Services,
    builder.Configuration,
    environmentName,
    isDocker,
    s => s.API,
    out apiSettings,
    out _ // ignore useHttps
);

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

builder.Services.AddCors(options =>
{
    //options.AddPolicy("AllowPaymentUI", policy =>
    //{
    //    policy.WithOrigins(
    //            "https://localhost:7112",  // UI HTTPS port
    //            "http://localhost:5208",   // UI HTTP port
    //            "https://localhost:32773",  // Additional UI port
    //            "https://localhost:32775"  // Additional UI port
    //        )
    //        .AllowAnyMethod()
    //        .AllowAnyHeader()
    //        .AllowCredentials();
    //});

    options.AddPolicy("AllowAll", policy =>
    {
        policy.SetIsOriginAllowed(_ => true) // Allow any origin
              .AllowAnyMethod()
              .AllowAnyHeader()
              .AllowCredentials();
    });
});

builder.InjectApplicationDependencies();

builder.Services.AddControllers();

// Register Swagger services
builder.Services.AddEndpointsApiExplorer();// Required for generating Swagger API documentation
builder.Services.AddSwaggerGen(options =>
{
    var xmlFile = $"{Assembly.GetExecutingAssembly().GetName().Name}.xml";
    var xmlPath = Path.Combine(AppContext.BaseDirectory, xmlFile);

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
                     (isDocker ? " 🐳 (Docker)" : " 🖥️ (Local)"),
    });
    
    // Add server configuration for proper Swagger API calls
    options.AddServer(new OpenApiServer 
    { 
        Url = activeSettings.GetBaseUrl(),
        Description = $"{environmentName.ToUpper()} Server"
    });
});

var mappingConfig = new MapperConfiguration(mapperConfiguration =>
{
    mapperConfiguration.AddProfile(new MapperConfigurationProfile());
});
IMapper mapper = mappingConfig.CreateMapper();
builder.Services.AddSingleton(mapper);

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
        .Enrich.WithProperty("Runtime", isDocker ? "Docker" : "Local");

    if (isDocker)
    {
        loggerConfiguration
            .WriteTo.Console(outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] [{Environment}] [{Runtime}] {Message:lj}{NewLine}{Exception}")
            .WriteTo.File(
                path: "/logs/webapi-.log",
                rollingInterval: RollingInterval.Day,
                outputTemplate: "{Timestamp:yyyy-MM-dd HH:mm:ss.fff zzz} [{Level:u3}] [{Environment}] [{Runtime}] {Message:lj}{Exception}{NewLine}"
            );
    }
    else
    {
        loggerConfiguration
            .WriteTo.Console(outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] [{Environment}] [{Runtime}] {Message:lj}{NewLine}{Exception}")
            .WriteTo.File(
                path: "../logs/webapi-.log",
                rollingInterval: RollingInterval.Day,
                outputTemplate: "{Timestamp:yyyy-MM-dd HH:mm:ss.fff zzz} [{Level:u3}] [{Environment}] [{Runtime}] {Message:lj}{Exception}{NewLine}"
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

// Initialize database and AppMasterData during startup
using (var scope = app.Services.CreateScope())
{
    try
    {
        var appMasterData = scope.ServiceProvider.GetRequiredService<AppMasterData>();
        Log.Information("Database initialized and AppMasterData loaded successfully during startup");
    }
    catch (Exception ex)
    {
        Log.Fatal(ex, "Failed to initialize database during startup");
        throw;
    }
}

SharedSettingsLoader.PrintApiSettingsDebug(apiSettings, activeSettings, "API", isDocker);

// Add Serilog request logging
app.UseSerilogRequestLogging();

// Configure the HTTP request pipeline.
// Environment-specific middleware configuration using our simplified profile names
if (environmentName == "dev" || environmentName == "uat")
{
    // Enable Swagger for Development and UAT environments
    app.UseSwagger();
    app.UseSwaggerUI(options =>
    {
        // Use relative path for Docker compatibility
        options.SwaggerEndpoint("/swagger/v1/swagger.json", "OrderProcessingSystem API v1");
        options.RoutePrefix = "swagger"; // Set Swagger UI to /swagger/index.html
    });
    
    if (environmentName == "dev")
    {
        app.UseDeveloperExceptionPage();
    }
}
else if (environmentName == "prod")
{
    // Production environment configuration
    
    // TEMPORARY: Enable Swagger for Production testing
    // TODO: DISABLE SWAGGER IN PRODUCTION for security reasons
    // To disable: Comment out the next 6 lines and uncomment the security block below
    app.UseSwagger();
    app.UseSwaggerUI(options =>
    {
        options.SwaggerEndpoint("/swagger/v1/swagger.json", "OrderProcessingSystem API v1");
        options.RoutePrefix = "swagger";
    });
    
    /* PRODUCTION SECURITY CONFIGURATION (currently commented for testing)
    // Uncomment this block and comment out Swagger above for production security:
    app.UseExceptionHandler("/Home/Error");
    app.UseHsts();
    // Note: Swagger should be disabled in production for security
    */
}
else
{
    // Fallback for other environments
    app.UseExceptionHandler("/Home/Error");
    app.UseHsts();
}

// Enable CORS before other middleware
//app.UseCors("AllowPaymentUI");
app.UseCors("AllowAll");

// Only use HTTPS redirection if enabled in ApiSettings
if (activeSettings.HttpsEnabled)
{
    app.UseHttpsRedirection();
}

app.UseAuthorization();

app.UseMiddleware<LoggingMiddleware>();

app.UseMiddleware<ErrorHandlingMiddleware>();

app.MapControllers();

Console.WriteLine($"[DEBUG] API is running and listening on https://{activeSettings.Host}:{activeSettings.Port} (or http://{activeSettings.Host}:{apiSettings.API.http.Port})");

try
{
    Log.Information("Starting API web host");
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
