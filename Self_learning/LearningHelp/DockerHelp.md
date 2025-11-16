## Beginner Quick Start (Windows PowerShell)

Follow these steps to start the dev environment reliably:

> **Note on First-Time Setup:** The initial download of base Docker images (like .NET SDK and ASP.NET runtime) can be time-consuming, especially on slower networks. The script will display a message box to inform you when this one-time download is in progress. Please be patient and allow the process to complete.

1) Navigate to the Docker scripts folder
```powershell
Set-Location R:\GitGetPavan\TestAppXY_OrderProcessingSystem\Resources\Docker
```

2) Fresh rebuild and start (recommended after image deletion)
```powershell
./start-docker.ps1 -Environment dev -Profile http
```

3) Enforce health & resilience (optional, CI-like)
```powershell
./start-docker.ps1 -Environment dev -Profile http -Strict
```
- Use `-Strict` to: (a) retry + fallback warm base images if pulls fail, (b) enforce health wait (90s default), (c) normalize exit code (0 when containers healthy even with compose stderr status lines).
- After the first build, for faster strict starts you can reuse images:
```powershell
./start-docker.ps1 -Environment dev -Profile http -LegacyBuild -Strict
```

4) Verify it’s up
- API (HTTP): `http://localhost:5020/swagger`
- API (HTTPS): `https://localhost:5021/swagger`
- UI (HTTP): `http://localhost:5022`
- UI (HTTPS): `https://localhost:5023`

Check status quickly:
```powershell
docker ps --format "table {{.Names}}`t{{.Status}}`t{{.Ports}}"
```

Stop the stack:
```powershell
./start-docker.ps1 -Environment dev -Profile http -Down
```

Tips for beginners:
- First run after image deletion: omit `-LegacyBuild` so a fresh build occurs.
- Flaky network / transient pull failures: just add `-Strict` (automatic retries + fallback warming built-in).
- Need a totally clean rebuild for ONE profile (http or https) without touching the other protocol's images: use `-Reset`.
- Want to skip warming base images (already cached): add `-NoPrePull`.

Quick scenarios:
```powershell
# Standard dev (fresh build)
./start-docker.ps1 -Environment dev -Profile http

# Fast reuse, health gated
./start-docker.ps1 -Environment dev -Profile http -LegacyBuild -Strict

# Clean rebuild for HTTPS only
./start-docker.ps1 -Environment dev -Profile https -Reset

# Skip base image warm step
./start-docker.ps1 -Environment dev -Profile http -NoPrePull

# CI-style deterministic start
./start-docker.ps1 -Environment dev -Profile http -Strict
```

## Common Errors and Fixes (Quick)

- Port already in use
  - Symptom: docker-compose fails to bind `5020-5023`.
  - Fix:
    ```powershell
    netstat -ano | findstr :5020
    taskkill /PID <PID> /F
    .\start-docker.ps1 -Environment dev -Profile http -Down
    .\start-docker.ps1 -Environment dev -Profile http
    ```

- Script execution disabled
  - Symptom: "Execution of scripts is disabled on this system".
  - Fix:
    ```powershell
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
    ```

- Docker engine not running
  - Symptom: `docker` commands fail or hang.
  - Fix: Open Docker Desktop and wait until it shows "Running"; verify with:
    ```powershell
    docker ps
    ```

- Network not found: `xy-database-network`
  - Symptom: "declared as external, but could not be found".
  - Fix: Re-run the start script (auto-creates). Manual fallback:
    ```powershell
    docker network create xy-database-network
    ```

- Images deleted or fast reuse used too early
  - Symptom: Services fail to start due to missing images. The build may fail with `Build failed and required images are missing`.
  - **Warning**: Do not manually delete base images like `mcr.microsoft.com/dotnet/sdk:8.0`. If your network blocks Docker from re-downloading them, your builds will be completely broken.
  - Fix: Rebuild without `-LegacyBuild` to force a fresh build.
    ```powershell
    .\start-docker.ps1 -Environment dev -Profile http
    ```

- Flaky base image pulls (proxy/corporate networks)
  - Fix: Use strict mode (automatic retries + fallback warming):
    ```powershell
    ./start-docker.ps1 -Environment dev -Profile http -Strict
    ```

- Containers not healthy
  - Symptom: Services stay `starting` or `unhealthy`.
  - Fix: Enforce health and print recent logs:
    ```powershell
    .\start-docker.ps1 -Environment dev -Profile http -Strict
    ```
  - Manual logs (dev):
    ```powershell
    docker-compose -f docker-compose.dev.yml logs --tail 150
    ```

- HTTPS certificate/trust issues (development)
  - Fix:
    ```powershell
    dotnet dev-certs https -ep .\Resources\Certificates\aspnetapp.pfx -p P@ss100
    dotnet dev-certs https --trust
    ```

- File blocked after download
  - Symptom: Access denied when running script.
  - Fix:
    ```powershell
    Unblock-File .\start-docker.ps1
    ```

## Section 1: Environment-Specific Docker Configuration

Here's an evaluation of the environment-specific docker-compose files:

### Environment Structure
- **docker-compose.dev.yml** - Development environment with hot reload and debugging
- **docker-compose.uat.yml** - UAT/Staging environment for production-like testing  
- **docker-compose.prod.yml** - Production environment with optimized settings

### Common Features Across Environments
- Defines four services: api, api-https, ui, ui-https.
- Uses profiles (http, https, all, etc.) for flexible service selection.
- Correctly sets environment variables for each service, including API_BASE_URL for UI and UI-HTTPS.
- Exposes the right ports for HTTP and HTTPS.
- Uses Docker service names (e.g., api, api-https) for internal communication, which is best practice.
- Healthchecks and networks are set up properly with environment-specific network names.

### Environment-Specific Configurations
- **Development**: Volume mounts for source code, hot reload enabled, debugging settings
- **UAT**: Production-like settings with staging environment variables
- **Production**: Optimized resource limits, monitoring, and production database connections

### Development Environment Specific Features
- Volume mounts for source code and certificates for local development.
- Hot reload capabilities for development workflow.
- Debug-friendly configurations and logging levels.
- Source code mounting for real-time development.

### Validation
- Environment-specific files provide isolated configurations for each deployment stage.
- All environments use consistent service definitions with environment-appropriate settings.
- API_BASE_URL is correctly set for internal service communication in each environment.
- Network configurations are isolated per environment (xy-dev-network, xy-uat-network, xy-prod-network).

### Testing
You can test different environments with:
```sh
# Development environment
.\start-docker.ps1 -Environment dev -Profile http
.\start-docker.ps1 -Environment dev -Profile https

# UAT environment  
.\start-docker.ps1 -Environment uat -Profile http
.\start-docker.ps1 -Environment uat -Profile https

# Production environment
.\start-docker.ps1 -Environment prod -Profile https
```
- Development URLs:
  - API (HTTP): http://localhost:5020/swagger
  - API (HTTPS): https://localhost:5021/swagger
  - UI (HTTP): http://localhost:5022
  - UI (HTTPS): https://localhost:5023

**Conclusion:**
Environment-specific Docker Compose files provide isolation and clarity. Strict mode centralizes resilience; `-Reset` gives clean profile rebuilds; `-NoPrePull` lets you skip warming when unnecessary—all while keeping commands simple.

## Section 2: Environment-Specific Docker Compose Architecture

The current setup uses dedicated files for each environment instead of a base + override approach:

- **docker-compose.dev.yml**:  
  Complete configuration for development environment with hot reload, source mounting, and debugging features enabled.

- **docker-compose.uat.yml**:  
  Complete configuration for UAT/staging environment with production-like settings for integration testing.

- **docker-compose.prod.yml**:  
  Complete configuration for production environment with optimized resource limits, monitoring, and production database connections.

**How they work:**  
- Each environment file is completely self-contained with all necessary service definitions.
- The PowerShell script (start-docker.ps1) automatically selects the appropriate file based on the -Environment parameter.
- Sharedsettings files provide environment-specific configuration that gets injected at runtime.

**Example Usage:**  
- Development: `.\start-docker.ps1 -Environment dev -Profile http`
- UAT Testing: `.\start-docker.ps1 -Environment uat -Profile https`
- Production: `.\start-docker.ps1 -Environment prod -Profile https`

**Summary:**  
- Each environment has a dedicated, complete Docker Compose configuration.
- No file merging or override complexity - each file stands alone.
- Environment-specific networks and settings provide better isolation.
- PowerShell automation handles environment switching and configuration injection.

## Section 3: Hot Reload Development Setup

For development environments, hot reload is configured for both API and UI projects:

### Development Volume Mounts
- Source code is mounted directly into containers for real-time development.
- Certificate files are mounted for HTTPS development testing.
- Configuration files are mounted for environment-specific settings.

### File Watcher Configuration
- `DOTNET_USE_POLLING_FILE_WATCHER=1` is set in development environment for Windows compatibility.
- File changes are detected and automatically trigger application reloads.
- This ensures seamless development experience with immediate feedback.

### Development Workflow
```sh
# Start development environment with hot reload
.\start-docker.ps1 -Environment dev -Profile http

# Make code changes - they will automatically reload
# View changes at: http://localhost:5022
```

### Volume Mount Benefits
- Immediate reflection of code changes without container rebuilds.
- Faster development iteration cycles.
- Full debugging capabilities with source code access.
- Real-time configuration updates.

## Section 4: Configuration Management

### ShareSettings Architecture
The application uses a hierarchical configuration approach:

1. **Base Configuration**: appsettings.json (application defaults)
2. **Environment Settings**: sharedsettings.{env}.json (shared across projects)  
3. **Project Settings**: appsettings.{Environment}.json (project-specific overrides)

### Environment Configuration Files
- `sharedsettings.dev.json` - Development environment settings
- `sharedsettings.uat.json` - UAT/staging environment settings  
- `sharedsettings.prod.json` - Production environment settings

### Configuration Loading Order
```
appsettings.json → sharedsettings.{env}.json → appsettings.{Environment}.json
```

### Key Configuration Areas
- **API Settings**: URLs, ports, HTTPS configuration
- **Database**: Connection strings and settings per environment
- **Docker**: Network names, volume configurations
- **Azure**: Cloud resource configurations for production
- **Logging**: Environment-appropriate logging levels

### Usage in Docker
The PowerShell script automatically:
1. Reads the appropriate sharedsettings file
2. Extracts port configurations
3. Creates environment variables for Docker Compose
4. Ensures network configurations match across all components

This approach ensures consistent configuration management across all deployment scenarios while maintaining environment-specific customizations.
