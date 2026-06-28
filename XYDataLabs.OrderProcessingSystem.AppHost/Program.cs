using System.Net.Sockets;

var builder = DistributedApplication.CreateBuilder(args);

var sqlServer = builder.AddContainer("sqlserver", "mcr.microsoft.com/mssql/server", "2022-CU14-ubuntu-22.04")
    .WithEnvironment("ACCEPT_EULA", "Y")
    .WithEnvironment("MSSQL_SA_PASSWORD", "MyLocal1!")
    .WithEndpoint("sql", endpoint =>
    {
        endpoint.Port = 15433;
        endpoint.TargetPort = 1433;
        endpoint.UriScheme = "tcp";
        endpoint.Protocol = ProtocolType.Tcp;
    });

var redis = builder.AddContainer("redis", "redis", "7-alpine")
    .WithEndpoint("redis", endpoint =>
    {
        endpoint.Port = 16379;
        endpoint.TargetPort = 6379;
        endpoint.UriScheme = "tcp";
        endpoint.Protocol = ProtocolType.Tcp;
    });

var api = builder.AddProject<Projects.XyDataLabsOrderProcessingSystemApi>("api");
var gateway = builder.AddProject<Projects.XyDataLabsOrderProcessingSystemGateway>("gateway");

api.WithEnvironment("ConnectionStrings__OrderProcessingSystemDbConnection",
    "Server=localhost,15433;Database=OrderProcessingSystem_Dev;User Id=sa;Password=MyLocal1!;TrustServerCertificate=True;");
api.WithEnvironment("ConnectionStrings__Redis", "localhost:16379");
api.WaitFor(sqlServer);
api.WaitFor(redis);

gateway.WithReference(api);
gateway.WaitFor(api);

builder.Build().Run();
