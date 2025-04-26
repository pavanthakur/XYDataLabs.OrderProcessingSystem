using Microsoft.Extensions.Configuration;

var builder = WebApplication.CreateBuilder(args);

// Add CORS services
//builder.Services.AddCors(options =>
//{
//    options.AddPolicy("AllowOpenPay", policy =>
//    {
//        policy.WithOrigins("https://sandbox-api.openpay.mx")
//              .AllowAnyMethod()
//              .AllowAnyHeader();
//    });
//});

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

builder.Services.AddHttpClient("ApiClient", client =>
{
    var apiBaseUrl = builder.Configuration["API_BASE_URL"];
    if (string.IsNullOrEmpty(apiBaseUrl))
    {
        throw new InvalidOperationException("API_BASE_URL environment variable is not set.");
    }
    client.BaseAddress = new Uri(apiBaseUrl);
});

// Add services to the container.
builder.Services.AddControllersWithViews();
builder.Services.AddRazorPages().AddRazorRuntimeCompilation();

var app = builder.Build();

// Configure the HTTP request pipeline.
if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Home/Error");
    app.UseHsts();
}

// Enable CORS before other middleware
//app.UseCors("AllowOpenPay");
app.UseCors("AllowAll");

app.UseHttpsRedirection();
app.UseStaticFiles();

app.UseRouting();

app.UseAuthorization();

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Home}/{action=Index}/{id?}");

app.Run();