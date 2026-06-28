import { spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import type { RuntimeTargetDefinition } from "../contracts/runtime-target-catalog.js";
import type { TenantExecutionCatalog, TenantExecutionPlan, TenantExecutionItem, TenantResolutionFailure } from "../contracts/tenant-execution-catalog.js";

interface RuntimeConfigurationResponse {
  activeTenantCode: string;
  configuredActiveTenantCode: string;
  tenantHeaderName: string;
  availableTenants: Array<{
    tenantId: number;
    tenantCode: string;
    tenantName: string;
  }>;
}

interface TenantRegistryResponseItem {
  tenantId: number;
  tenantCode: string;
  tenantName: string;
  tenantTier: string;
  paymentProviderCode: string | null;
}

export class ApiTenantExecutionCatalog implements TenantExecutionCatalog {
  public constructor(private readonly target: RuntimeTargetDefinition) {}

  private async loadTenantRegistry(
    apiBaseUrl: string,
    activeTenantCode: string,
    tenantHeaderName: string,
    logger?: (message: string) => void
  ): Promise<TenantRegistryResponseItem[]> {
    const tenantRegistryUrl = `${apiBaseUrl}/api/v1/Info/tenant-registry`;
    logger?.(`Loading tenant registry from ${tenantRegistryUrl}.`);

    try {
      return await fetchJson<TenantRegistryResponseItem[]>(
        tenantRegistryUrl,
        this.target.ignoreHttpsErrors,
        30000,
        {
          [tenantHeaderName]: activeTenantCode
        }
      );
    }
    catch (error) {
      const message = error instanceof Error ? error.message : "Unknown tenant registry API failure.";
      logger?.(`Tenant registry API lookup failed (${message}); falling back to local SQL.`);
      return await loadTenantRegistryFromDatabase(this.target.runtime, this.target.environment, logger);
    }
  }

  public async resolve(
    tenantCodes: string[],
    allowPartialExecution: boolean,
    logger?: (message: string) => void
  ): Promise<TenantExecutionPlan> {
    const apiBaseUrl = this.target.apiBaseUrl ?? this.target.baseUrl;
    logger?.(`Loading runtime configuration from ${apiBaseUrl}/api/v1/Info/runtime-configuration.`);
    const runtimeConfiguration = await this.loadRuntimeConfiguration(apiBaseUrl, logger);

    const registry = await this.loadTenantRegistry(
      apiBaseUrl,
      runtimeConfiguration.activeTenantCode,
      runtimeConfiguration.tenantHeaderName,
      logger
    );
    logger?.(`Tenant registry returned ${registry.length} record(s).`);
    const requestedTenants = tenantCodes.length > 0
      ? new Set(tenantCodes.map((tenantCode) => tenantCode.trim()).filter(Boolean))
      : null;

    const resolvedTenants: TenantExecutionItem[] = [];
    const failures: TenantResolutionFailure[] = [];

    const availableTenantCodes = runtimeConfiguration.availableTenants.length > 0
      ? new Set(runtimeConfiguration.availableTenants.map((available) => available.tenantCode))
      : null;

    const orderedRegistry = registry
      .filter((item) => (!availableTenantCodes || availableTenantCodes.has(item.tenantCode)) && (!requestedTenants || requestedTenants.has(item.tenantCode)))
      .sort((left, right) => compareTenantPriority(left, right, runtimeConfiguration.activeTenantCode));

    for (const tenant of orderedRegistry) {
      resolvedTenants.push({
        tenantCode: tenant.tenantCode,
        tenantTier: tenant.tenantTier,
        paymentProviderCode: tenant.paymentProviderCode
      });
    }

    if (requestedTenants) {
      for (const tenantCode of requestedTenants) {
        if (!resolvedTenants.some((tenant) => tenant.tenantCode === tenantCode)) {
          failures.push({
            tenantCode,
            reason: "Tenant is not active in the runtime registry."
          });
        }
      }
    }

    if (failures.length > 0 && !allowPartialExecution) {
      throw new Error(failures.map((failure) => `${failure.tenantCode}: ${failure.reason}`).join("; "));
    }

    logger?.(`Resolved ${resolvedTenants.length} active tenant(s); skipped ${failures.length}.`);
    return {
      resolvedTenants,
      skippedTenantCodes: failures.map((failure) => failure.tenantCode),
      failures
    };
  }

  private async loadRuntimeConfiguration(
    apiBaseUrl: string,
    logger?: (message: string) => void
  ): Promise<RuntimeConfigurationResponse> {
    try {
      return await fetchJson<RuntimeConfigurationResponse>(
        `${apiBaseUrl}/api/v1/Info/runtime-configuration`,
        this.target.ignoreHttpsErrors,
        30000
      );
    }
    catch (error) {
      const message = error instanceof Error ? error.message : "Unknown runtime configuration failure.";
      logger?.(`Runtime configuration API lookup failed (${message}); falling back to shared settings.`);
      return await loadRuntimeConfigurationFromSharedSettings(this.target.runtime, this.target.environment, logger);
    }
  }
}

async function fetchJson<T>(
  url: string,
  ignoreHttpsErrors: boolean,
  timeoutMs: number,
  headers?: Record<string, string>
): Promise<T> {
  const abortController = new AbortController();
  const timeoutHandle = setTimeout(() => abortController.abort(), timeoutMs);

  try {
    const response = await fetch(url, {
      signal: abortController.signal,
      headers: {
        Accept: "application/json"
        ,
        ...(headers ?? {})
      },
      // Node fetch does not expose HTTPS certificate handling here.
      // The local endpoints used by this path are HTTP.
    });

    if (!response.ok) {
      throw new Error(`Request to ${url} failed with status ${response.status}.`);
    }

    return await response.json() as T;
  }
  finally {
    clearTimeout(timeoutHandle);
  }
}

function getWorkspaceRoot(): string {
  const currentDirectory = path.dirname(fileURLToPath(import.meta.url));
  const automationRoot = path.resolve(currentDirectory, "../..");
  return path.resolve(automationRoot, "..");
}

function resolveSharedSettingsPath(runtimeKind: string, environmentName: string): string | null {
  const workspaceRoot = getWorkspaceRoot();
  const fileName = runtimeKind === "local"
    ? "sharedsettings.local.json"
    : runtimeKind === "docker" || runtimeKind === "azure"
      ? `sharedsettings.${environmentName}.json`
      : null;

  return fileName ? path.join(workspaceRoot, "Resources", "Configuration", fileName) : null;
}

async function loadTenantRegistryFromDatabase(
  runtimeKind: string,
  environmentName: string,
  logger?: (message: string) => void
): Promise<TenantRegistryResponseItem[]> {
  const sharedSettingsPath = resolveSharedSettingsPath(runtimeKind, environmentName);
  if (!sharedSettingsPath) {
    throw new Error(`No shared settings file is configured for runtime '${runtimeKind}'.`);
  }

  const sharedSettingsJson = await readFile(sharedSettingsPath, "utf8");
  const sharedSettings = JSON.parse(sharedSettingsJson) as {
    ConnectionStrings?: {
      TenantRegistryDbConnection?: string;
      OrderProcessingSystemDbConnection?: string;
      OrderProcessingSystemDbConnection_Local?: string;
    };
  };

  const connectionString = sharedSettings.ConnectionStrings?.TenantRegistryDbConnection
    ?? sharedSettings.ConnectionStrings?.OrderProcessingSystemDbConnection_Local
    ?? sharedSettings.ConnectionStrings?.OrderProcessingSystemDbConnection;

  if (!connectionString) {
    throw new Error(`No local database connection string was found in ${sharedSettingsPath}.`);
  }

  const resolvedConnectionString = runtimeKind === "docker"
    ? await resolveDockerSqlConnectionString(connectionString)
    : connectionString;

  logger?.(`Loading tenant registry from local SQL using ${sharedSettingsPath}.`);

  const script = `
$ErrorActionPreference = 'Stop'
$connectionString = $env:TENANT_REGISTRY_CONNECTION_STRING
if (-not $connectionString) { throw 'TENANT_REGISTRY_CONNECTION_STRING is missing.' }

$connectionParts = @{}
foreach ($part in $connectionString -split ';') {
  if ([string]::IsNullOrWhiteSpace($part)) { continue }
  $pair = $part -split '=', 2
  if ($pair.Count -eq 2) {
    $connectionParts[$pair[0].Trim().ToLowerInvariant()] = $pair[1].Trim()
  }
}

$server = $connectionParts['server']
if (-not $server) { $server = $connectionParts['data source'] }
$database = $connectionParts['database']
$userId = $connectionParts['user id']
$password = $connectionParts['password']
if (-not $server -or -not $database -or -not $userId -or -not $password) {
  throw 'Connection string is missing server, database, user id, or password.'
}

Add-Type -AssemblyName System.Data
$builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder $connectionString
$builder['Connection Timeout'] = 15
$builder['TrustServerCertificate'] = $true
$builder['Encrypt'] = $false

$query = @"
SET NOCOUNT ON;
SELECT
  t.Id AS tenantId,
  t.Code AS tenantCode,
  t.Name AS tenantName,
  ISNULL(t.TenantTier, '') AS tenantTier,
  ISNULL(t.PaymentProviderCode, '') AS paymentProviderCode
FROM Tenants t
WHERE t.Status = 'Active'
ORDER BY t.Name, t.Code;
"@;
$connection = New-Object System.Data.SqlClient.SqlConnection $builder.ConnectionString
try {
  $connection.Open()
  $command = $connection.CreateCommand()
  $command.CommandTimeout = 30
  $command.CommandText = $query
  $reader = $command.ExecuteReader()
  $rows = New-Object System.Collections.Generic.List[object]
  while ($reader.Read()) {
    $rows.Add([pscustomobject]@{
      tenantId = $reader.GetInt32(0)
      tenantCode = $reader.GetString(1)
      tenantName = $reader.GetString(2)
      tenantTier = $reader.GetString(3)
      paymentProviderCode = if ($reader.IsDBNull(4)) { $null } else { $reader.GetString(4) }
    })
  }

  if ($rows.Count -eq 0) {
    Write-Output '[]'
  }
  else {
    Write-Output ($rows | ConvertTo-Json -Depth 4 -Compress)
  }
}
finally {
  if ($connection.State -ne 'Closed') {
    $connection.Close()
  }
  $connection.Dispose()
}
`.trim();

  const result = spawnSync("pwsh", [
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-Command",
    script
  ], {
    encoding: "utf8",
    env: {
      ...process.env,
      TENANT_REGISTRY_CONNECTION_STRING: resolvedConnectionString
    }
  });

  if (result.error) {
    throw result.error;
  }

  if (result.status !== 0) {
    const stderr = (result.stderr ?? "").toString().trim();
    throw new Error(stderr || `Local SQL tenant registry query failed with exit code ${result.status}.`);
  }

  const rawOutput = (result.stdout ?? "").toString().trim();
  const parsed = rawOutput ? JSON.parse(rawOutput) as Array<{
    tenantId: number;
    tenantCode: string;
    tenantName: string;
    tenantTier: string;
    paymentProviderCode: string | null;
  }> : [];

  return parsed.map((item) => ({
    tenantId: item.tenantId,
    tenantCode: item.tenantCode,
    tenantName: item.tenantName,
    tenantTier: item.tenantTier ?? "",
    paymentProviderCode: item.paymentProviderCode && item.paymentProviderCode.trim().length > 0
      ? item.paymentProviderCode
      : null
  }));
}

async function loadRuntimeConfigurationFromSharedSettings(
  runtimeKind: string,
  environmentName: string,
  logger?: (message: string) => void
): Promise<RuntimeConfigurationResponse> {
  const sharedSettingsPath = resolveSharedSettingsPath(runtimeKind, environmentName);
  if (!sharedSettingsPath) {
    throw new Error(`No shared settings file is configured for runtime '${runtimeKind}'.`);
  }

  const sharedSettingsJson = await readFile(sharedSettingsPath, "utf8");
  const sharedSettings = JSON.parse(sharedSettingsJson) as {
    TenantConfiguration?: {
      ActiveTenantCode?: string;
    };
  };

  const activeTenantCode = sharedSettings.TenantConfiguration?.ActiveTenantCode?.trim();
  if (!activeTenantCode) {
    throw new Error(`No active tenant code was found in ${sharedSettingsPath}.`);
  }

  logger?.(`Using shared settings fallback runtime configuration from ${sharedSettingsPath}.`);
  return {
    activeTenantCode,
    configuredActiveTenantCode: activeTenantCode,
    tenantHeaderName: "X-Tenant-Code",
    availableTenants: []
  };
}

async function resolveDockerSqlConnectionString(connectionString: string): Promise<string> {
  if (!connectionString.includes("__LOCAL_SQL_PASSWORD__")) {
    return connectionString;
  }

  const workspaceRoot = getWorkspaceRoot();
  const envLocalPath = path.join(workspaceRoot, "Resources", "Docker", ".env.local");
  const envLocalJson = await readFile(envLocalPath, "utf8");
  const passwordLine = envLocalJson
    .split(/\r?\n/)
    .find((line) => line.trim().startsWith("LOCAL_SQL_PASSWORD="));

  if (!passwordLine) {
    throw new Error(`LOCAL_SQL_PASSWORD was not found in ${envLocalPath}.`);
  }

  const password = passwordLine.split("=", 2)[1]?.trim();
  if (!password) {
    throw new Error(`LOCAL_SQL_PASSWORD is empty in ${envLocalPath}.`);
  }

  return connectionString.replace("__LOCAL_SQL_PASSWORD__", password);
}

function compareTenantPriority(
  left: TenantRegistryResponseItem,
  right: TenantRegistryResponseItem,
  activeTenantCode: string
): number {
  const normalizedActiveTenantCode = activeTenantCode.trim().toLowerCase();
  const leftIsActive = left.tenantCode.trim().toLowerCase() === normalizedActiveTenantCode;
  const rightIsActive = right.tenantCode.trim().toLowerCase() === normalizedActiveTenantCode;

  if (leftIsActive && !rightIsActive) {
    return -1;
  }

  if (!leftIsActive && rightIsActive) {
    return 1;
  }

  const tierRankLeft = getTenantTierRank(left.tenantTier);
  const tierRankRight = getTenantTierRank(right.tenantTier);
  if (tierRankLeft !== tierRankRight) {
    return tierRankLeft - tierRankRight;
  }

  return left.tenantCode.localeCompare(right.tenantCode, undefined, { sensitivity: "base" });
}

function getTenantTierRank(tenantTier: string): number {
  if (tenantTier.trim().toLowerCase() === "sharedpool") {
    return 0;
  }

  if (tenantTier.trim().toLowerCase() === "dedicated") {
    return 1;
  }

  return 2;
}
