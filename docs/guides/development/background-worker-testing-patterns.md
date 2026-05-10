# Background Worker Integration Testing Patterns

This guide documents the test mechanics used to verify hosted background services added during Phase 8 (Event-Driven Foundation). Because these workers run on their own schedules, request/response integration patterns are not sufficient on their own.

The current worker suite uses the shared `IntegrationTestWebAppFactory` plus SQL-backed integration fixtures to prove three things:

1. A naturally polling worker can be observed through persisted side effects.
2. A slow-polling worker can be exercised without waiting for its production delay interval.
3. Tenant-scoped data access still holds when work executes outside the HTTP request pipeline.

## Preconditions

Run these tests in an environment where the integration fixture can access SQL Server:

1. Default path: Docker/Testcontainers can start the SQL Server image used by `SqlServerFixture`.
2. Override path: set `ORDERPROCESSING_TEST_CONNECTION_STRING` to an existing SQL Server instance if container startup is not available.

---

## Pattern 1: The Natural Polling Approach
**Used for:** Fast-polling background workers (e.g., `OutboxPublisherWorker` which polls every 5 seconds).  
**Strategy:** Let the worker run naturally in the background and poll the database to observe its side effects.
**Current proof point:** `OutboxPublisherWorkerIntegrationTests` verifies that a tenant-scoped outbox row transitions from `ProcessedAt = null` to a processed timestamp.

### Implementation Steps
1. **Seed Tenant:** Establish a multitenant context using `IntegrationTestData.CreateTenantAsync(_factory)`.
2. **Seed State:** Inject the trigger data directly into the database (e.g., creating an `OutboxMessage` with `ProcessedAt = null`).
3. **Wait & Poll:** 
   - Define a maximum wait timeout (e.g., 15 seconds) and a polling interval (e.g., 500ms).
   - Initiate a `while` loop that queries the database to check if the expected state change has occurred.
4. **Assert:** Validate that the test succeeds as soon as the background service processes the data (e.g., `ProcessedAt` is no longer null).

---

## Pattern 2: The Reflection Bypass Approach
**Used for:** Slow-polling background workers (e.g., `PaymentReconciliationWorker` which polls every 60 seconds).  
**Strategy:** Bypass the long `Task.Delay` by invoking the worker's internal processing method synchronously via Reflection.
**Current proof point:** `PaymentReconciliationWorkerIntegrationTests` verifies that a persisted `PaymentAttempt` in `UnknownNeedsReconciliation` is picked up under the correct tenant scope and that reconciliation execution writes update metadata back to the row.

### Implementation Steps
1. **Seed Tenant:** Establish a multitenant context.
2. **Seed State:** Insert the target data (e.g., a `PaymentAttempt` with `UnknownNeedsReconciliation` status) into the database.
3. **Extract Service:** Query the test factory's Dependency Injection container for all `IHostedService` instances and single out the target worker.
   ```csharp
   using var scope = _factory.Services.CreateScope();
   var hostServices = scope.ServiceProvider.GetServices<IHostedService>();
   var worker = hostServices.FirstOrDefault(s => s.GetType().Name == "PaymentReconciliationWorker");
   ```
4. **Invoke via Reflection:** Grab the private execution loop method and invoke it, passing an empty cancellation token.
   ```csharp
   var methodInfo = worker!.GetType().GetMethod("ReconcilePaymentsAsync", BindingFlags.NonPublic | BindingFlags.Instance);
   var task = (Task)methodInfo!.Invoke(worker, new object[] { CancellationToken.None })!;
   await task;
   ```
5. **Assert:** Query the database and verify that the worker applied the expected updates immediately.

This test currently validates execution and persistence of reconciliation updates. It does not yet prove a real successful provider reconciliation path with live or stubbed provider semantics.

---

## Pattern 3: Validating Tenant Boundary Isolation
**Used for:** Ensuring background processes do not cross or leak tenant data.  
**Strategy:** Leverage global query filters natively by executing queries within targeted HTTP-like context scopes.
**Current proof point:** `TenantIsolationTests` verifies that tenant-scoped reads only surface rows owned by the active tenant, including outbox rows.

### Implementation Steps
1. **Setup Dual Tenants:** Create 'Tenant A' and 'Tenant B'.
2. **Seed Dual Contexts:** Create overlapping domain entities for both tenants in the shared database.
3. **Query Under Context A:** Open an artificial context scope simulating Tenant A (`ExecuteTenantDbContextAsync(tenantA.ToTenantContext(), ...)`).
4. **Assert Isolation:** Query the target table (e.g., `OutboxMessages`) and assert that every retrieved record belongs exclusively to Tenant A (`OutboxMessage.TenantId == tenantA.TenantId`).

---

## Execution Commands

Use these commands for local verification of the worker slice and the broader closeout gate:

```powershell
# 1. Run the targeted Outbox worker polling tests
dotnet test tests/XYDataLabs.OrderProcessingSystem.Integration.Tests --filter FullyQualifiedName~OutboxPublisherWorkerIntegrationTests

# 2. Run the targeted Payment worker reflection tests
dotnet test tests/XYDataLabs.OrderProcessingSystem.Integration.Tests --filter FullyQualifiedName~PaymentReconciliationWorkerIntegrationTests

# 3. Run the Tenant Isolation boundary checks
dotnet test tests/XYDataLabs.OrderProcessingSystem.Integration.Tests --filter FullyQualifiedName~TenantIsolationTests

# 4. Final verification: Check architectural rules (Clean Architecture dependencies)
dotnet test tests/XYDataLabs.OrderProcessingSystem.Architecture.Tests

# 5. Full test suite validation 
dotnet test tests/XYDataLabs.OrderProcessingSystem.Integration.Tests
```

Observed local verification on this branch:

1. `OutboxPublisherWorkerIntegrationTests` passed.
2. `PaymentReconciliationWorkerIntegrationTests` passed.
3. `TenantIsolationTests` passed.
4. `XYDataLabs.OrderProcessingSystem.Architecture.Tests` passed.
5. `XYDataLabs.OrderProcessingSystem.Integration.Tests` passed.