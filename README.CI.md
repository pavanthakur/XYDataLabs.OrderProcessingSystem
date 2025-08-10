# CI/CLI Solution

Use `XYDataLabs.OrderProcessingSystem.CI.sln` for cross-platform CLI and CI builds. It excludes `docker-compose.dcproj` which is not supported by `dotnet` CLI.

## Commands

- Clean: `dotnet clean XYDataLabs.OrderProcessingSystem.CI.sln`
- Restore: `dotnet restore XYDataLabs.OrderProcessingSystem.CI.sln`
- Build: `dotnet build XYDataLabs.OrderProcessingSystem.CI.sln -c Debug`
- Test: `dotnet test XYDataLabs.OrderProcessingSystem.CI.sln -c Debug`

Or run the helper script on Windows PowerShell:

```
./build-ci.ps1 -Configuration Debug
```
