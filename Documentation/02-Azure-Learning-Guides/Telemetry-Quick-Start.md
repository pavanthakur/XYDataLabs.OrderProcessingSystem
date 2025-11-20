# Telemetry Quick Start (Application Insights)

## Objective
Rapidly enable actionable observability (requests, dependencies, logs, metrics) for the Order Processing System with minimal overhead and production‑safe defaults.

## 1. Provision / Validate Resources
If you used `setup-appinsights-dev.ps1` the resource group contains an Application Insights instance already.
Otherwise provision (example):
```bash
az monitor app-insights component create -g <rg> -a <name>-appi -l eastus --application-type web
```

## 2. Keyless Connection (Recommended)
Use the connection string (preferred) rather than legacy instrumentation key.
Retrieve:
```bash
az monitor app-insights component show -g <rg> -a <name>-appi --query connectionString -o tsv
```
Store in GitHub secret (e.g. `APPINSIGHTS_CONNECTIONSTRING`) or in Azure App Service configuration for each slot.

## 3. App Service Configuration
Set these settings (Connection Strings or App Settings):
- `APPLICATIONINSIGHTS_CONNECTION_STRING` = connection string value
- `ASPNETCORE_HOSTINGSTARTUPASSEMBLIES` = `Microsoft.AspNetCore.ApplicationInsights.HostingStartup`
- Optional sampling overrides:
  - `APPLICATIONINSIGHTS_SAMPLING_PERCENTAGE` (default ~5–10% for high volume; raise for lower volume)

## 4. SDK & Minimal Code
If using .NET 8 minimal hosting, ensure package references (usually via implicit framework):
```xml
<ItemGroup>
  <PackageReference Include="Microsoft.ApplicationInsights.AspNetCore" Version="2.*" />
</ItemGroup>
```
Add in `Program.cs` before build:
```csharp
builder.Services.AddApplicationInsightsTelemetry();
```
Custom telemetry example:
```csharp
var telemetry = builder.Services.BuildServiceProvider().GetRequiredService<TelemetryClient>();
telemetry.TrackEvent("StartupCompleted");
```

## 5. Correlation & Distributed Tracing
Outgoing HTTP calls automatically tracked. For custom operations:
```csharp
using (var op = telemetry.StartOperation<RequestTelemetry>("ProcessOrder")) {
    // work
    telemetry.TrackMetric("ItemsProcessed", itemCount);
}
```

## 6. Logging Integration
Ensure logging providers forward to AI:
```csharp
builder.Logging.AddApplicationInsights();
builder.Logging.AddFilter<ApplicationInsightsLoggerProvider>("", LogLevel.Information);
```
Use structured logging (`logger.LogInformation("Order {OrderId} queued", orderId);`) to enable Kusto filtering (`customDimensions`).

## 7. Live Metrics & Availability
Enable Live Metrics in portal for rapid feedback.
Add availability tests (ping or multi-step) naming convention:
`ops-orderprocessing-api-<env>-ping`.

## 8. Dashboards / Workbooks
Create a workbook capturing:
- Requests (Top 5 slow endpoints)
- Failures (Exceptions by type)
- Dependencies (SQL call duration percentiles)
- Custom Metrics (ItemsProcessed, QueueLagMs)
- Deployment Event Correlation (filter by release timestamp tag)

## 9. Alerting (Baseline)
Suggested alerts:
| Metric | Condition | Threshold | Window |
|--------|-----------|----------|--------|
| Server response time | P95 > | 1500 ms | 15m |
| Failed requests | Rate > | 2% | 15m |
| Exceptions | Count > | dynamic baseline | 15m |
| Availability test | Failure rate > | 1 | 5m |

## 10. Tagging Conventions
Set cloud role name explicitly:
```csharp
builder.Services.AddSingleton<IApplicationIdProvider, RoleNameInitializer>();
```
Or simpler:
```csharp
builder.Services.AddApplicationInsightsTelemetry(options => {
    options.EnableAdaptiveSampling = true;
});
```
Add `TelemetryConfiguration.Active.TelemetryInitializers.Add(new OperationNameTelemetryInitializer("order-api"));`
(Adjust for UI vs API roles.)

## 11. Deployment Correlation
Emit an event during deployment script:
```powershell
az monitor app-insights events show ...
# Or REST call using track event if using ingestion endpoint
```
Simpler: update an App Setting `RELEASE_VERSION` and include in logs.

## 12. Validation Checklist
- Connection string present in each environment
- Requests & dependencies visible within 2 minutes of traffic
- Sampling percentage acceptable (no data starvation)
- Alert rules created & enabled
- Workbook published & shared

## 13. Next Enhancements
- Add custom metric for queue backlog
- Ingest business event: `OrderSubmitted`
- Link to distributed tracing across microservices once decomposition occurs

## 14. Troubleshooting
| Symptom | Cause | Fix |
|---------|-------|-----|
| No data | Missing connection string | Set `APPLICATIONINSIGHTS_CONNECTION_STRING` |
| High cost | Sampling disabled | Re-enable adaptive sampling |
| Missing dependencies | HttpClient instrumentation removed | Ensure default handlers present |
| Incorrect role | Cloud role name not set | Add initializer or environment variable |

## 15. Script Alignment
`setup-appinsights-dev.ps1` creates resource; this guide covers runtime enablement.
Future: add script for automated alert & workbook provisioning.

---
Keep this lean; expand only when microservice telemetry evolves (messaging, caching, custom metrics).