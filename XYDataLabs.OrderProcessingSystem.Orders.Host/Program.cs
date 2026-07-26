using XYDataLabs.OrderProcessingSystem.API.Hosting;

var builder = WebApplication.CreateBuilder(args);
builder.AddPhase10OwnedService(Phase10ServiceKind.Orders);

var app = builder.Build();
app.MapPhase10OwnedService(Phase10ServiceKind.Orders);

await app.RunAsync();

public partial class Program;
