# Azure Developer Learning Path: Containerization, ACA & .NET Aspire

Target Audience: Developers moving from traditional hosting (App Service) to containerized workloads on Azure Container Apps (ACA) and optionally adopting .NET Aspire.

Learning Outcomes:
- Build, run, and debug containerized .NET apps locally
- Push images to Azure Container Registry (ACR) using OIDC CI/CD
- Deploy to Azure Container Apps with ingress, secrets, and scaling
- Implement observability (Log Analytics, App Insights, OpenTelemetry)
- Apply enterprise security practices (MI, Key Vault, SBOM, scanning, WAF)
- Integrate .NET Aspire for service composition and telemetry

Prerequisites:
- .NET 8 SDK installed
- Docker Desktop (or Podman) installed and running
- Azure CLI (`az`) authenticated (`az login`)
- VS Code with Docker and C# extensions
- Git and GitHub account with repo access

---

## Module 1: Docker Essentials for .NET

Learning Goals:
- Understand Docker images, containers, layers, and registries
- Write multi-stage Dockerfiles for .NET apps
- Use environment variables and health checks
- Run containers locally and verify behavior

Key Concepts:
- Multi-stage builds: reduce image size by separating build and runtime stages
- Base images: `mcr.microsoft.com/dotnet/aspnet:8.0` for runtime, `mcr.microsoft.com/dotnet/sdk:8.0` for build
- EXPOSE, ENV, HEALTHCHECK directives
- `.dockerignore` to exclude unnecessary files

Hands-On Tasks:

### Task 1.1: Create Dockerfile for API
Location: `XYDataLabs.OrderProcessingSystem.API/Dockerfile`

```dockerfile
# Stage 1: Build
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY ["XYDataLabs.OrderProcessingSystem.API/XYDataLabs.OrderProcessingSystem.API.csproj", "XYDataLabs.OrderProcessingSystem.API/"]
COPY ["XYDataLabs.OrderProcessingSystem.Application/XYDataLabs.OrderProcessingSystem.Application.csproj", "XYDataLabs.OrderProcessingSystem.Application/"]
COPY ["XYDataLabs.OrderProcessingSystem.Domain/XYDataLabs.OrderProcessingSystem.Domain.csproj", "XYDataLabs.OrderProcessingSystem.Domain/"]
COPY ["XYDataLabs.OrderProcessingSystem.Infrastructure/XYDataLabs.OrderProcessingSystem.Infrastructure.csproj", "XYDataLabs.OrderProcessingSystem.Infrastructure/"]
COPY ["XYDataLabs.OrderProcessingSystem.Utilities/XYDataLabs.OrderProcessingSystem.Utilities.csproj", "XYDataLabs.OrderProcessingSystem.Utilities/"]
COPY ["XYDataLabs.OpenPayAdapter/XYDataLabs.OpenPayAdapter.csproj", "XYDataLabs.OpenPayAdapter/"]
RUN dotnet restore "XYDataLabs.OrderProcessingSystem.API/XYDataLabs.OrderProcessingSystem.API.csproj"
COPY . .
WORKDIR "/src/XYDataLabs.OrderProcessingSystem.API"
RUN dotnet build "XYDataLabs.OrderProcessingSystem.API.csproj" -c Release -o /app/build

# Stage 2: Publish
FROM build AS publish
RUN dotnet publish "XYDataLabs.OrderProcessingSystem.API.csproj" -c Release -o /app/publish /p:UseAppHost=false

# Stage 3: Runtime
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
EXPOSE 8080
EXPOSE 8081
COPY --from=publish /app/publish .
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD curl --fail http://localhost:8080/health || exit 1
ENTRYPOINT ["dotnet", "XYDataLabs.OrderProcessingSystem.API.dll"]
```

Validation:
```powershell
docker build -t orderprocessing-api:local -f XYDataLabs.OrderProcessingSystem.API/Dockerfile .
docker run -d -p 8080:8080 --name api-test orderprocessing-api:local
curl http://localhost:8080/health
docker logs api-test
docker stop api-test; docker rm api-test
```

Expected Outcome: API responds at `http://localhost:8080`, health check passes.

---

### Task 1.2: Create Dockerfile for UI
Location: `XYDataLabs.OrderProcessingSystem.UI/Dockerfile`

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY ["XYDataLabs.OrderProcessingSystem.UI/XYDataLabs.OrderProcessingSystem.UI.csproj", "XYDataLabs.OrderProcessingSystem.UI/"]
RUN dotnet restore "XYDataLabs.OrderProcessingSystem.UI/XYDataLabs.OrderProcessingSystem.UI.csproj"
COPY . .
WORKDIR "/src/XYDataLabs.OrderProcessingSystem.UI"
RUN dotnet build "XYDataLabs.OrderProcessingSystem.UI.csproj" -c Release -o /app/build
RUN dotnet publish "XYDataLabs.OrderProcessingSystem.UI.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
EXPOSE 8080
COPY --from=publish /app/publish .
ENV API_BASE_URL=http://localhost:8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD curl --fail http://localhost:8080/ || exit 1
ENTRYPOINT ["dotnet", "XYDataLabs.OrderProcessingSystem.UI.dll"]
```

Validation:
```powershell
docker build -t orderprocessing-ui:local -f XYDataLabs.OrderProcessingSystem.UI/Dockerfile .
docker run -d -p 8081:8080 --name ui-test -e API_BASE_URL=http://host.docker.internal:8080 orderprocessing-ui:local
curl http://localhost:8081
docker stop ui-test; docker rm ui-test
```

Expected Outcome: UI serves at `http://localhost:8081`, references API via env var.

---

### Task 1.3: Local Multi-Container Setup
Create `docker-compose.yml` at repo root:

```yaml
version: '3.8'
services:
  api:
    build:
      context: .
      dockerfile: XYDataLabs.OrderProcessingSystem.API/Dockerfile
    ports:
      - "8080:8080"
    environment:
      - ASPNETCORE_ENVIRONMENT=Development
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 10s
      timeout: 3s
      retries: 3
  ui:
    build:
      context: .
      dockerfile: XYDataLabs.OrderProcessingSystem.UI/Dockerfile
    ports:
      - "8081:8080"
    environment:
      - API_BASE_URL=http://api:8080
    depends_on:
      - api
```

Validation:
```powershell
docker-compose up -d
docker-compose ps
curl http://localhost:8080/health
curl http://localhost:8081
docker-compose down
```

Checkpoint: You can now build and run the full app stack locally.

---

## Module 2: Azure Container Registry (ACR)

Learning Goals:
- Provision ACR via Bicep
- Authenticate using Azure OIDC in CI/CD
- Push and pull images securely

Key Concepts:
- ACR SKUs: Basic, Standard, Premium (geo-replication, private link, content trust)
- Image tagging strategies: `:latest`, `:sha`, `:release-v1.0`
- Admin account vs Azure AD/MI authentication (prefer MI)

Hands-On Tasks:

### Task 2.1: Add ACR Bicep Module
Location: `infra/modules/acr.bicep`

```bicep
param registryName string
param location string = resourceGroup().location
param sku string = 'Standard'
param tags object = {}

resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: registryName
  location: location
  sku: {
    name: sku
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
    networkRuleBypassOptions: 'AzureServices'
  }
  tags: tags
}

output loginServer string = acr.properties.loginServer
output name string = acr.name
output id string = acr.id
```

Integration: Update `infra/main.bicep` to include ACR module:

```bicep
module acr 'modules/acr.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'acrModule'
  params: {
    registryName: '${githubOwner}acrops${environment}${uniqueString(subscription().subscriptionId)}'
    location: location
    sku: 'Standard'
    tags: tags
  }
}

output acrLoginServer string = acr.outputs.loginServer
```

Deploy:
```powershell
az deployment sub create --location centralindia --template-file infra/main.bicep --parameters @infra/parameters/dev.json
```

Expected Outcome: ACR created; login server output available.

---

### Task 2.2: Push Images to ACR via CI
Add GitHub Actions workflow: `.github/workflows/container-build.yml`

```yaml
name: Build and Push Containers

on:
  push:
    branches: [dev, staging, main]

permissions:
  id-token: write
  contents: read

jobs:
  build-push:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Azure Login (OIDC)
        uses: azure/login@v3
        with:
          client-id: ${{ secrets.AZUREAPPSERVICE_CLIENTID }}
          tenant-id: ${{ secrets.AZUREAPPSERVICE_TENANTID }}
          subscription-id: ${{ secrets.AZUREAPPSERVICE_SUBSCRIPTIONID }}

      - name: Login to ACR
        run: |
          az acr login --name ${{ secrets.ACR_NAME }}

      - name: Build and Push API
        run: |
          docker build -t ${{ secrets.ACR_LOGIN_SERVER }}/orderprocessing-api:${{ github.sha }} -f XYDataLabs.OrderProcessingSystem.API/Dockerfile .
          docker tag ${{ secrets.ACR_LOGIN_SERVER }}/orderprocessing-api:${{ github.sha }} ${{ secrets.ACR_LOGIN_SERVER }}/orderprocessing-api:latest
          docker push ${{ secrets.ACR_LOGIN_SERVER }}/orderprocessing-api:${{ github.sha }}
          docker push ${{ secrets.ACR_LOGIN_SERVER }}/orderprocessing-api:latest

      - name: Build and Push UI
        run: |
          docker build -t ${{ secrets.ACR_LOGIN_SERVER }}/orderprocessing-ui:${{ github.sha }} -f XYDataLabs.OrderProcessingSystem.UI/Dockerfile .
          docker tag ${{ secrets.ACR_LOGIN_SERVER }}/orderprocessing-ui:${{ github.sha }} ${{ secrets.ACR_LOGIN_SERVER }}/orderprocessing-ui:latest
          docker push ${{ secrets.ACR_LOGIN_SERVER }}/orderprocessing-ui:${{ github.sha }}
          docker push ${{ secrets.ACR_LOGIN_SERVER }}/orderprocessing-ui:latest
```

Secrets to configure:
- `ACR_NAME`: Name from Bicep output
- `ACR_LOGIN_SERVER`: for example `pavanthakuracropsdev<unique>.azurecr.io`

Checkpoint: Push to `dev` branch; verify images in ACR.

---

## Module 3: Azure Container Apps (ACA)

Learning Goals:
- Provision ACA environment with Log Analytics
- Deploy Container Apps with ingress and scaling
- Configure secrets and environment variables

Key Concepts:
- Managed Environment: shared infrastructure for Container Apps
- Ingress: internal vs external; custom domains
- Revisions: immutable snapshots for blue/green deployments
- KEDA autoscaling: CPU, HTTP requests, custom metrics

Hands-On Tasks:

### Task 3.1: Add ACA Environment Module
Location: `infra/modules/aca/managedEnvironment.bicep`

```bicep
param environmentName string
param location string = resourceGroup().location
param logAnalyticsWorkspaceId string
param tags object = {}

resource acaEnv 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: environmentName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: reference(logAnalyticsWorkspaceId, '2021-06-01').customerId
        sharedKey: listKeys(logAnalyticsWorkspaceId, '2021-06-01').primarySharedKey
      }
    }
  }
  tags: tags
}

output id string = acaEnv.id
output defaultDomain string = acaEnv.properties.defaultDomain
```

---

### Task 3.2: Add Container App Module
Location: `infra/modules/aca/containerApp.bicep`

```bicep
param name string
param location string = resourceGroup().location
param environmentId string
param containerImage string
param containerPort int = 8080
param minReplicas int = 0
param maxReplicas int = 5
param ingressExternal bool = true
param cpuCores string = '0.5'
param memory string = '1.0Gi'
param env array = []
param tags object = {}

resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: name
  location: location
  properties: {
    managedEnvironmentId: environmentId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: ingressExternal ? {
        external: true
        targetPort: containerPort
        transport: 'auto'
        allowInsecure: false
      } : null
    }
    template: {
      containers: [
        {
          name: 'app'
          image: containerImage
          resources: {
            cpu: json(cpuCores)
            memory: memory
          }
          env: env
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '10'
              }
            }
          }
        ]
      }
    }
  }
  tags: tags
}

output fqdn string = containerApp.properties.configuration.ingress != null ? containerApp.properties.configuration.ingress.fqdn : ''
output id string = containerApp.id
```

---

### Task 3.3: Deploy API to ACA
Update `infra/main.bicep`:

```bicep
module apiContainerApp 'modules/aca/containerApp.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'apiContainerApp'
  params: {
    name: '${githubOwner}-api-aca-${environment}'
    location: location
    environmentId: acaEnv.outputs.id
    containerImage: '${acr.outputs.loginServer}/orderprocessing-api:latest'
    containerPort: 8080
    minReplicas: 1
    maxReplicas: 5
    ingressExternal: true
    env: [
      { name: 'ASPNETCORE_ENVIRONMENT', value: environment }
    ]
    tags: tags
  }
}

output apiFqdn string = apiContainerApp.outputs.fqdn
```

Deploy:
```powershell
az deployment sub create --location centralindia --template-file infra/main.bicep --parameters @infra/parameters/dev-aca.json
```

Validation:
```powershell
curl https://<apiFqdn>/health
```

Checkpoint: API running on ACA with public HTTPS ingress.

---

## Module 4: Observability with OpenTelemetry

Learning Goals:
- Instrument .NET apps with OpenTelemetry
- Export traces and metrics to Application Insights
- Query logs in Log Analytics

Hands-On Tasks:

### Task 4.1: Add OpenTelemetry to API
In `XYDataLabs.OrderProcessingSystem.API/Program.cs`:

```csharp
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddOpenTelemetry()
    .ConfigureResource(r => r.AddService("OrderProcessingAPI"))
    .WithTracing(t => t
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddAzureMonitorTraceExporter(o => o.ConnectionString = builder.Configuration["ApplicationInsights:ConnectionString"]))
    .WithMetrics(m => m
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddAzureMonitorMetricExporter(o => o.ConnectionString = builder.Configuration["ApplicationInsights:ConnectionString"]));

var app = builder.Build();
```

NuGet packages:
- `Azure.Monitor.OpenTelemetry.Exporter`
- `OpenTelemetry.Instrumentation.AspNetCore`
- `OpenTelemetry.Instrumentation.Http`

Validation: Deploy; view traces in Application Insights -> Transaction Search.

---

## Module 5: Security & Supply Chain

Learning Goals:
- Scan images for vulnerabilities
- Generate and publish SBOM
- Sign images for integrity
- Use Managed Identity and Key Vault

Hands-On Tasks:

### Task 5.1: Add Trivy Scan to CI
Update `.github/workflows/container-build.yml`:

```yaml
      - name: Scan API Image
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ secrets.ACR_LOGIN_SERVER }}/orderprocessing-api:${{ github.sha }}
          format: 'sarif'
          output: 'trivy-api.sarif'
          severity: 'HIGH,CRITICAL'
          exit-code: '1'

      - name: Upload Trivy Results
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: 'trivy-api.sarif'
```

Checkpoint: Build fails if HIGH/CRITICAL vulnerabilities detected.

---

Transition note:

- This file is the active canonical home for the containerization, ACA, and Aspire learning path.
- Retired legacy source files are archived as the learning-reference family is validated.