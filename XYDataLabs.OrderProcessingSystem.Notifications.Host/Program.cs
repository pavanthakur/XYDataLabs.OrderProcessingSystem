using XYDataLabs.OrderProcessingSystem.API.Hosting;

var builder = WebApplication.CreateBuilder(args);
builder.AddPhase10OwnedService(Phase10ServiceKind.Notifications);

var app = builder.Build();
app.MapPhase10OwnedService(Phase10ServiceKind.Notifications);

await app.RunAsync();

public partial class Program;
