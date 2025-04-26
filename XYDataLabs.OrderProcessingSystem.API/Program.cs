using AutoMapper;
using XYDataLabs.OrderProcessingSystem.API.Middleware;
using XYDataLabs.OrderProcessingSystem.Application;
using Microsoft.OpenApi.Models;
using Serilog;
using System.Reflection;

var builder = WebApplication.CreateBuilder(args);

// Configure CORS
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
        Title = "OrderProcessingSystem API",
        Version = "v1",
        Description = "OrderProcessingSystem API with Customer, Order endpoints",
    });
});

var mappingConfig = new MapperConfiguration(mapperConfiguration =>
{
    mapperConfiguration.AddProfile(new MapperConfigurationProfile());
});
IMapper mapper = mappingConfig.CreateMapper();
builder.Services.AddSingleton(mapper);

// Add services to the container.
var logger = new LoggerConfiguration()
    .ReadFrom.Configuration(builder.Configuration)
    .Enrich.FromLogContext()
    .CreateLogger();
builder.Logging.ClearProviders();
builder.Logging.AddSerilog(logger);

var app = builder.Build();
// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
    app.UseDeveloperExceptionPage();
}
else
{
    app.UseExceptionHandler("/Home/Error");
    app.UseHsts();
}

// Enable CORS before other middleware
//app.UseCors("AllowPaymentUI");
app.UseCors("AllowAll");

app.UseHttpsRedirection();

app.UseAuthorization();

app.UseMiddleware<LoggingMiddleware>();

app.UseMiddleware<ErrorHandlingMiddleware>();

app.MapControllers();

app.Run();
