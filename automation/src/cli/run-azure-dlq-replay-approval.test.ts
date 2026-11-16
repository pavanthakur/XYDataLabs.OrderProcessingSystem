import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { parseArguments } from "./run-azure-dlq-replay-approval.js";

const quarantineId = "11111111-1111-4111-8111-111111111111";
const sourceMessageId = "33333333-3333-4333-8333-333333333333";
const correlationId = "phase10-replay-acceptance-001";
const baseArgs = ["--tenant-code", "TenantA", "--quarantine-id", quarantineId, "--source-message-id", sourceMessageId, "--correlation-id", correlationId];

test("requires an explicit approval command with tenant and quarantine identity", () => {
  assert.deepEqual(parseArguments([...baseArgs, "--confirm-approval", "--confirm-firewall-lease"]), {
    tenantCode: "TenantA", quarantineId, sourceMessageId, correlationId, confirmFirewallLease: true
  });
});

test("refuses approval or SQL firewall lease without separate explicit confirmation", () => {
  assert.throws(() => parseArguments([...baseArgs, "--confirm-firewall-lease"]), /--confirm-approval/);
  assert.throws(() => parseArguments([...baseArgs, "--confirm-approval"]), /separate dev mutation/);
});

test("pins approval to Azure dev and rejects unsafe or malformed input", () => {
  const confirmed = [...baseArgs, "--confirm-approval", "--confirm-firewall-lease"];
  assert.throws(() => parseArguments([...confirmed, "--target", "azure-prod"]), /pinned to azure-dev/);
  assert.throws(() => parseArguments(confirmed.map(value => value === "TenantA" ? "../prod" : value)), /invalid characters/);
  assert.throws(() => parseArguments(confirmed.map(value => value === quarantineId ? "bad" : value)), /must be a GUID/);
  assert.throws(() => parseArguments(confirmed.map(value => value === sourceMessageId ? "bad" : value)), /Source message ID/);
  assert.throws(() => parseArguments(confirmed.map(value => value === correlationId ? "bad correlation" : value)), /Correlation ID/);
});

test("reserves the run report before starting the operator-assisted API flow", async () => {
  const source = await readFile(fileURLToPath(new URL("./run-azure-dlq-replay-approval.ts", import.meta.url)), "utf8");
  const reservation = source.indexOf("await reservePhase10Report(reportPath, report)");
  const apiFlow = source.indexOf("await runner.execute(");
  assert.notEqual(reservation, -1);
  assert.notEqual(apiFlow, -1);
  assert.ok(reservation < apiFlow, "approval must not start until the exclusive report artifact is reserved");
});
