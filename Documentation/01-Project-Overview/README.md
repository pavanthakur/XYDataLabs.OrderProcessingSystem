# TestAppXY_OrderProcessingSystem

<!---
# 🔥 Attention!!

**Currently, CleanArchitecture with below features mentioned are covered in this project. 

Note : Logs can be checked inside TestAppXY_OrderProcessingSystem\logs\ folder.
-->

# Certificate were generated with below commands
Q:\GIT\TestAppXY_OrderProcessingSystem> dotnet dev-certs https -ep ./Resources/Certificates/aspnetapp.pfx -p P@ss100
Q:\GIT\TestAppXY_OrderProcessingSystem> dotnet dev-certs https --trust

# 🏃‍♂️ How to Run the Project

## 🎯 Quick Start Options

### **Option 1: Visual Studio Non-Docker (Recommended for Development)**
1. Open solution in **Visual Studio 2022**
2. Select **API** or **UI** project as startup
3. Choose **http** or **https** profile (NOT docker-* profiles)
4. Press **F5** to start debugging
   - **API**: http://localhost:5010/swagger (or https://localhost:5011/swagger)
   - **UI**: http://localhost:5012 (or https://localhost:5013)
   - **Database**: `OrderProcessingSystem_Local` created automatically

### **Option 2: Docker Development**
```powershell
# Development environment (ports 5020-5023)
.\start-docker.ps1 -Environment dev -Profile http

# UAT environment (ports 5030-5033)
.\start-docker.ps1 -Environment uat -Profile https

# Production environment (ports 5040-5043)
.\start-docker.ps1 -Environment prod -Profile https

# CI-grade strict startup (health gated, retries + fallback)
.\start-docker.ps1 -Environment dev -Profile http -Strict

# Fast local reuse with health enforcement
.\start-docker.ps1 -Environment dev -Profile http -LegacyBuild -Strict

# Clean rebuild of single profile (http or https)
.\start-docker.ps1 -Environment dev -Profile https -Reset

# Skip base image pre-pull (already cached)
.\start-docker.ps1 -Environment dev -Profile http -NoPrePull

# Show help and usage
.\start-docker.ps1 -Help
```

### **Option 3: Enterprise Docker Mode**
```powershell
# Enterprise development with enhanced features
.\start-docker.ps1 -Environment dev -Profile https -EnterpriseMode

# UAT with conservative cleanup and automatic backups
.\start-docker.ps1 -Environment uat -Profile https -EnterpriseMode -ConservativeClean

# Production with mandatory backup and minimal cleanup
.\start-docker.ps1 -Environment prod -Profile https -EnterpriseMode -BackupFirst
```

> **🏢 Enterprise Mode Features**: Network isolation, automatic backups, environment-specific cleanup policies, enhanced logging, and production safety controls. See [Enterprise Docker Guide](../02-Azure-Learning-Guides/ENTERPRISE_DOCKER_GUIDE.md) for complete documentation.

> **📖 Simplified Interface (Nov 2025)**: Deprecated flags removed (`-PrePullRetryCount`, `-UseBuildFallbackForPrePull`, `-FailOnPrePullError`, `-WaitForHealthy`, `-CleanImages`). Use `-Strict` for resilience + health gating, `-Reset` for clean rebuilds, `-NoPrePull` to skip warming. Full migration guide in [Docker Comprehensive Guide](../02-Azure-Learning-Guides/DOCKER_COMPREHENSIVE_GUIDE.md).

## 🗄️ Database Environment Strategy

| **Mode** | **Database** | **Server** | **Ports** | **Use Case** |
|----------|-------------|------------|-----------|--------------|
| **Visual Studio F5** | `OrderProcessingSystem_Local` | localhost:1433 | 5010-5013 | Local development & debugging |
| **Docker Dev** | `OrderProcessingSystem_Dev` | host.docker.internal:1433 | 5020-5023 | Container development |
| **Docker UAT** | `OrderProcessingSystem_UAT` | host.docker.internal:1433 | 5030-5033 | Testing environment |
| **Docker Prod** | `OrderProcessingSystem_Prod` | host.docker.internal:1433 | 5040-5043 | Production simulation |

## 📋 Prerequisites
1. **.NET 8.0 SDK** and **Visual Studio 2022** installed
2. **SQL Server** running on localhost:1433  
3. **Docker Desktop** (for Docker scenarios only)
4. Build solution to ensure no errors: `dotnet build`

## 🐛 Debugging Options

### **Visual Studio F5 Debugging (Non-Docker)**
- **API**: Select http/https profile → F5 → Breakpoints work directly
- **UI**: Select http/https profile → F5 → Breakpoints work directly
- **Ports**: 5010-5013 series
- **Database**: OrderProcessingSystem_Local

### **Docker Container Debugging**
1. **Start Docker environment** first:
   ```powershell
   .\start-docker.ps1 -Environment dev -Profile http
   ```

2. **For API debugging**:
   - Debug → Attach to Process
   - Connection type: Docker (Linux Container)
   - Container target: api-dev-http-1 (or api-dev-https-1 for HTTPS)
   - Attach To: XYDataLabs.OrderProcessingSystem.API
   - Code type: Managed (.NET Core for Unix) code

3. **For UI debugging** (VSCode):
   - Open project in VSCode
   - Run and Debug → Launch Chrome (UI 5022)

### **Current Port Allocation**
- **Local (Non-Docker)**: API 5010/5011, UI 5012/5013
- **Docker Dev**: API 5020/5021, UI 5022/5023  
- **Docker UAT**: API 5030/5031, UI 5032/5033
- **Docker Prod**: API 5040/5041, UI 5042/5043
	  
# Clean Architecture in ASP.NET Core
This repository contains the implementation of Domain Driven Design and Clean Architecture in ASP.NET Core.

# ⚙️ Features
1.	Domain Driven Design
2.	REST API
3.	API Versioning
4.	Logging with Serilog
5.	EF Core Code First Approach 
6.	Microsoft SQL Server
7.	AutoMapper
8.	Swagger 
9.	LoggingMiddleware 
10.	ErrorHandlingMiddleware
11.	Fluent Assertions
12.	xUnit For UnitTest
13.	Moq For UnitTest
14.	Bogus For UnitTest
15.	Docker


# TODO
1.	~~Make Docker launch configurable separate profile http and https~~ ✅ **COMPLETED** (Multi-environment docker-compose with http/https/all profiles)
2.	Add another API
3.	Sql Post Gres
4.	Redis
5.	Azure hosting
6.	Store sensitive data in key vault
7.	Azure App Insight configuration
8.	Azure Service bus communication
9.	Azure containerization using Docker
10.	Kubernetes
11.	Angular
12.	SignalR
13.	Remove Auto Mapper
14.	CQRS without MediaR
