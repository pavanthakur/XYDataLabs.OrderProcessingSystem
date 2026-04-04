# Local Development Commands

**Part of:** [quick-command-reference.md](./quick-command-reference.md)  
**Last Updated:** March 20, 2026

---

## 🔨 Build & Test

```powershell
# Clean build
dotnet clean
dotnet build XYDataLabs.OrderProcessingSystem.sln

# Release build
dotnet build XYDataLabs.OrderProcessingSystem.sln --configuration Release

# Restore NuGet packages
dotnet restore

# Run all unit tests
dotnet test XYDataLabs.OrderProcessingSystem.UnitTest/

# Run tests with detailed output
dotnet test XYDataLabs.OrderProcessingSystem.UnitTest/ --verbosity detailed

# Run specific test
dotnet test --filter "FullyQualifiedName~TestMethodName"

# Generate test coverage report
dotnet test /p:CollectCoverage=true /p:CoverletOutputFormat=opencover
```

---

## 🚀 Run Applications Locally

```powershell
# Run API (default: https://localhost:5001)
cd XYDataLabs.OrderProcessingSystem.API
dotnet run

# Run UI (default: https://localhost:5002)
cd XYDataLabs.OrderProcessingSystem.UI
dotnet run

# Run with specific environment
dotnet run --environment Development
dotnet run --environment Staging
dotnet run --environment Production

# Explicit environment variable + run
$env:ASPNETCORE_ENVIRONMENT = "Development"
dotnet run
```

> **Visual Studio (recommended for debugging):** Press F5 — sets `ASPNETCORE_ENVIRONMENT=Development` automatically.  
> **VS Code:** Set `"env": { "ASPNETCORE_ENVIRONMENT": "Development" }` in `launch.json`.

### **Port Allocations**
| Mode | API | UI |
|------|-----|-----|
| Local VS (F5) | http://localhost:5010 | http://localhost:5012 |
| Docker dev | http://localhost:5020 | http://localhost:5022 |
| Docker UAT | http://localhost:5030 | http://localhost:5032 |

---

## 🔍 EF Core SQL Logging — Local Dev Only

> **Why logging only fires locally:**  
> Azure App Service has `ASPNETCORE_ENVIRONMENT=dev` (lowercase). `IsDevelopment()` checks for the exact  
> string `"Development"` — so it returns **false** on Azure → SQL logging is intentionally OFF.  
> This prevents SQL parameter values (which may contain sensitive data) from appearing in production logs.  
> Locally (Visual Studio F5 / `dotnet run --environment Development`), `IsDevelopment()` = **true** → logging fires.

**Expected console output when running locally:**
```
[03:23:48 INF] [dev] [Local] Request: GET /api/Customer/GetAllCustomersByName
                              ?name=at&pageNumber=1&pageSize=10  Body:

info: 20-03-2026 03:23:48.503 RelationalEventId.CommandExecuted[20101]
      (Microsoft.EntityFrameworkCore.Database.Command)
      Executed DbCommand (20ms) [Parameters=[], CommandType='Text', CommandTimeout='30']
      SELECT [c].[CustomerId], [c].[CreatedBy], [c].[CreatedDate], [c].[Email],
             [c].[Name], [c].[OpenpayCustomerId], [c].[UpdatedBy], [c].[UpdatedDate]
      FROM [Customers] AS [c]

[03:23:48 INF] [dev] [Local] Response: 200 Body: [{"customerId":2,"name":"Katelyn Reynolds",...}]
[03:23:48 INF] [dev] [Local] HTTP GET /api/Customer/GetAllCustomersByName responded 200 in 587.2204 ms
```

| Log line | What it tells you |
|---|---|
| `[dev] [Local] Request:` | Request logging middleware — env tag + machine tag |
| `Executed DbCommand (20ms)` | EF Core SQL logging via `LogTo(Console.WriteLine)` |
| `SELECT FROM [Customers]` | Actual SQL sent to the database |
| `[dev] [Local] Response: 200` | Response middleware with status + JSON body |
| `responded 200 in 587ms` | ASP.NET Core built-in request timing |

**Code location:** `XYDataLabs.OrderProcessingSystem.Infrastructure/StartupHelper.cs`
```csharp
if (builder.Environment.IsDevelopment())
{
    options.LogTo(Console.WriteLine, LogLevel.Information)
           .EnableSensitiveDataLogging()
           .EnableDetailedErrors();
}
```

---

## 🐳 Docker Commands

### **Project Docker Scripts (preferred)**
```powershell
# Start — dev environment
.\Resources\Docker\start-docker.ps1 -Environment dev -Profile http

# Start — strict CI-grade startup
.\Resources\Docker\start-docker.ps1 -Environment dev -Profile http -Strict

# Clean rebuild
.\Resources\Docker\start-docker.ps1 -Environment dev -Profile https -Reset
```

### **Docker Container Management**
```powershell
# List running containers
docker ps

# List all containers (including stopped)
docker ps -a

# Start/Stop containers
docker start container-name
docker stop container-name

# View logs
docker logs container-name
docker logs container-name --follow       # Follow logs in real-time

# Remove container
docker rm container-name
docker rm -f container-name               # Force remove running container
```

### **Docker Image Management**
```powershell
# List images
docker images

# Build image
docker build -t app-name:tag .

# Remove image
docker rmi image-name:tag

# Clean up unused images
docker image prune -a
```

### **Docker Compose**
```powershell
# Start all services
docker-compose up -d

# Stop all services
docker-compose down

# View logs
docker-compose logs
docker-compose logs -f service-name

# Rebuild and start
docker-compose up -d --build
```
