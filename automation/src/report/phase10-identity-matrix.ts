import type { EvidenceStatus } from "./phase10-report.js";

type JsonRecord = Record<string, unknown>;

export interface IdentityMatrixCase {
  role: "platform-admin" | "tenant-user" | "logout";
  tenant: string | null;
  deniedTenant: string | null;
  status: EvidenceStatus;
  allowedHttpStatus: number | null;
  deniedHttpStatus: number | null;
}

export interface IdentityMatrixReport {
  status: EvidenceStatus;
  expected: number | null;
  observed: number;
  cases: IdentityMatrixCase[];
  issues: string[];
}

function record(value: unknown): JsonRecord | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as JsonRecord : undefined;
}

function tenantCode(value: unknown): string | null {
  return typeof value === "string" && /^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/.test(value) ? value : null;
}

function positiveInteger(value: unknown): value is number {
  return Number.isSafeInteger(value) && Number(value) > 0;
}

export function normalizePhase10IdentityMatrix(summaryInput: unknown, seedInput: unknown): IdentityMatrixReport {
  const issues: string[] = [];
  const summary = record(summaryInput);
  const seed = record(seedInput);
  if (!summary || !Array.isArray(summary.results)) issues.push("Tenant identity summary is missing or malformed.");
  if (!seed || seed.status !== "passed" || !Array.isArray(seed.tenants)) {
    issues.push("Tenant identity expectations cannot be derived from the passing seed contract.");
  }

  const activeTenants = (Array.isArray(seed?.tenants) ? seed.tenants : [])
    .map(record).filter((item): item is JsonRecord => item?.status === "Active");
  const tenants = activeTenants.map(item => tenantCode(item.tenant));
  if (!tenants.length || tenants.some(item => item === null) || new Set(tenants).size !== tenants.length ||
      !Number.isSafeInteger(seed?.activeTenantCount) || seed?.activeTenantCount !== tenants.length) {
    issues.push("Active tenant identity inventory is empty, malformed, duplicated or inconsistent.");
  }

  const expectedTenants = tenants.filter((item): item is string => item !== null);
  const cases: IdentityMatrixCase[] = [];
  const rows = Array.isArray(summary?.results) ? summary.results : [];
  const observed = new Map<string, IdentityMatrixCase[]>();
  const regularAccountsByTenant = new Map<string, string>();
  let logoutRows = 0;

  for (const raw of rows) {
    const row = record(raw);
    if (!row) {
      issues.push("Tenant identity summary contains a malformed result.");
      continue;
    }
    if (row.scenario === "same-browser login/logout and cross-tab logout") {
      logoutRows++;
      const item: IdentityMatrixCase = { role: "logout", tenant: null, deniedTenant: null,
        status: row.status === "passed" ? "PASS" : row.status === "failed" ? "FAIL" : "BLOCKED",
        allowedHttpStatus: null, deniedHttpStatus: null };
      cases.push(item);
      observed.set("logout", [...(observed.get("logout") ?? []), item]);
      continue;
    }
    if (row.scenario === "identity-browser") {
      issues.push("Tenant identity browser execution reported a failed or incomplete identity flow.");
      cases.push({ role: "tenant-user", tenant: null, deniedTenant: null, status: "FAIL",
        allowedHttpStatus: null, deniedHttpStatus: null });
      continue;
    }

    const tenant = tenantCode(row.tenant);
    if (!tenant || !expectedTenants.includes(tenant)) {
      issues.push("Tenant identity result is outside the seed-derived active tenant inventory.");
      continue;
    }
    if (row.account === "tenant-admin") {
      const item: IdentityMatrixCase = { role: "platform-admin", tenant, deniedTenant: null,
        status: row.status === "passed" && row.httpStatus === 200 && positiveInteger(row.customerCount)
          ? "PASS" : row.status === "failed" ? "FAIL" : "BLOCKED",
        allowedHttpStatus: Number.isInteger(row.httpStatus) ? Number(row.httpStatus) : null,
        deniedHttpStatus: null };
      cases.push(item);
      observed.set(`admin\0${tenant}`, [...(observed.get(`admin\0${tenant}`) ?? []), item]);
      continue;
    }

    const account = typeof row.account === "string" && /^[A-Za-z0-9._-]{1,80}$/.test(row.account)
      ? row.account : null;
    if (!account || account === "tenant-admin") {
      issues.push("Tenant identity result does not have a valid non-admin account identity.");
      continue;
    }
    const deniedTenant = tenantCode(row.deniedTenant);
    const accountTenant = regularAccountsByTenant.get(tenant);
    if (accountTenant && accountTenant !== account) issues.push("More than one regular account was reported for one tenant.");
    const previousTenant = [...regularAccountsByTenant.entries()].find(([, value]) => value === account)?.[0];
    if (previousTenant && previousTenant !== tenant) issues.push("One regular account was reused across tenant assignments.");
    regularAccountsByTenant.set(tenant, account);

    const item: IdentityMatrixCase = { role: "tenant-user", tenant, deniedTenant,
      status: row.status === "passed" && row.httpStatus === 200 && positiveInteger(row.customerCount) &&
        deniedTenant !== null && expectedTenants.includes(deniedTenant) && deniedTenant !== tenant && row.deniedStatus === 403
        ? "PASS" : row.status === "failed" ? "FAIL" : "BLOCKED",
      allowedHttpStatus: Number.isInteger(row.httpStatus) ? Number(row.httpStatus) : null,
      deniedHttpStatus: Number.isInteger(row.deniedStatus) ? Number(row.deniedStatus) : null };
    cases.push(item);
    observed.set(`user\0${tenant}`, [...(observed.get(`user\0${tenant}`) ?? []), item]);
  }

  for (const tenant of expectedTenants) {
    for (const role of ["admin", "user"] as const) {
      const matches = observed.get(`${role}\0${tenant}`) ?? [];
      if (matches.length !== 1) issues.push(`Expected exactly one ${role} identity result for an active tenant; observed ${matches.length}.`);
    }
  }
  if (logoutRows !== 1 || (observed.get("logout") ?? []).length !== 1) {
    issues.push("Expected exactly one same-browser and cross-tab logout result.");
  }

  const expected = expectedTenants.length ? expectedTenants.length * 2 + 1 : null;
  const hasFailure = cases.some(item => item.status === "FAIL");
  const status: EvidenceStatus = hasFailure ? "FAIL" : issues.length ? "BLOCKED"
    : cases.length === expected && cases.every(item => item.status === "PASS") ? "PASS"
      : "BLOCKED";
  return { status, expected, observed: rows.length, cases, issues };
}
