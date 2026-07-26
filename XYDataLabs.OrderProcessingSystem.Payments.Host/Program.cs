using XYDataLabs.OrderProcessingSystem.API.Hosting;

var builder = WebApplication.CreateBuilder(args);
builder.AddPhase10OwnedService(Phase10ServiceKind.Payments);

var app = builder.Build();
app.MapPhase10OwnedService(Phase10ServiceKind.Payments);

await app.RunAsync();

public partial class Program;
