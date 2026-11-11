import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, readFile, rm, utimes, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { test } from "node:test";
import { promisify } from "node:util";
import { DOCKER_PACKET_STEPS, normalizePhase10Packet, renderPhase10Report } from "./phase10-report.js";
import { FOUNDATION_AUTOMATION_TEST_CHECKS, FOUNDATION_CHECKS, normalizeFoundationSummary } from "./phase10-foundations.js";
import { FOUNDATION_TRX_PROJECTS, parseFoundationTrx } from "./phase10-trx.js";
import { parseVitest } from "./phase10-vitest.js";
import { parseBackendCoverage, parseFrontendCoverage } from "./phase10-coverage.js";
import { verifyPhase10Completion } from "./phase10-completion.js";
import { expectedAutomationTests, normalizeAutomationSuite, normalizeAutomationSuites, normalizeDiscoveredDotnetSuite,
  phase10AutomationInventorySha256 } from "./phase10-automation.js";

const execFileAsync = promisify(execFile);
const summary = {
  runId: "phase10-docker-http-20261110-030929435", status: "passed", runRoot: "run-root",
  acceptanceProfile: "baseline", paymentSuite: "both",
  startedUtc: "2026-11-09T21:39:29.4493367Z", finishedUtc: "2026-11-09T22:12:08.8474771Z", storageExitCode: 0
};
const packet = {
  status: "passed", runRoot: "run-root", storageExitCode: 0,
  restoration: { status: "passed", allRestored: true, fixtureLockPresent: false },
  steps: DOCKER_PACKET_STEPS.map(name => ({ name, status: "passed" }))
};
const foundations = {
  status: "passed",
  results: FOUNDATION_CHECKS.map(name => ({
    name, status: "passed", exitCode: 0,
    startedUtc: "2026-11-09T21:45:16.7240733Z", finishedUtc: "2026-11-09T21:45:17.6709186Z"
  }))
};
const window = { startedUtc: foundations.results[0].startedUtc, finishedUtc: foundations.results[0].finishedUtc };
const trxXml = `<?xml version="1.0"?><TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010">
<Times start="2026-11-09T21:45:16.900Z" finish="2026-11-09T21:45:17.500Z"/>
<Results><UnitTestResult executionId="01234567-89ab-cdef-0123-456789abcdef" testName="synthetic test name" outcome="Passed"/></Results>
<ResultSummary outcome="Completed"><Counters total="1" executed="1" passed="1" failed="0" notExecuted="0"/></ResultSummary></TestRun>`;
const trxInputs = Object.fromEntries(FOUNDATION_TRX_PROJECTS.map(project => [project, trxXml]));
const vitest = {
  startTime: Date.parse(window.startedUtc), success: true,
  numTotalTests: 1, numPassedTests: 1, numFailedTests: 0, numPendingTests: 0, numTodoTests: 0,
  testResults: [{ status: "passed", startTime: Date.parse(window.startedUtc), endTime: Date.parse(window.finishedUtc),
    assertionResults: [{ status: "passed", fullName: "<script>secret</script>" }] }]
};
const additional = { integrationTrx: trxXml, frontend: vitest };
const automationInventorySha256 = phase10AutomationInventorySha256(
  readFileSync(new URL("../../config/phase10-automation-test-inventory.json", import.meta.url), "utf8"));

function automationResult(suiteId: string, changes: Record<string, unknown> = {}) {
  const tests = expectedAutomationTests(suiteId).map(item => ({ id: item.id, status: "passed" }));
  return { schema: "phase10-automation-test-results-v1", suiteId, inventorySha256: automationInventorySha256,
    runnerExitCode: 0, complete: true, expectedCount: tests.length, observedCount: tests.length,
    missingCount: 0, unexpectedCount: 0, duplicateCount: 0, tests, ...changes };
}

test("automation suites require exact versioned inventory identities and consistent runner outcomes", () => {
  const suiteId = "test-callbacks";
  const valid = automationResult(suiteId);
  assert.equal(normalizeAutomationSuite(valid, suiteId, automationInventorySha256).status, "PASS");
  assert.equal(normalizeAutomationSuite({ ...valid, inventorySha256: "0".repeat(64) }, suiteId, automationInventorySha256).status, "BLOCKED");
  assert.equal(normalizeAutomationSuite({ ...valid, tests: valid.tests.slice(1), observedCount: valid.tests.length - 1,
    missingCount: 1, complete: false }, suiteId, automationInventorySha256).status, "BLOCKED");
  assert.equal(normalizeAutomationSuite({ ...valid, tests: [...valid.tests, valid.tests[0]], observedCount: valid.tests.length + 1,
    duplicateCount: 1, complete: false }, suiteId, automationInventorySha256).status, "BLOCKED");
  assert.equal(normalizeAutomationSuite({ ...valid, tests: valid.tests.map((item, index) => index ? item : { ...item, id: "unexpected" }),
    unexpectedCount: 1, complete: false }, suiteId, automationInventorySha256).status, "BLOCKED");
  assert.equal(normalizeAutomationSuite({ ...valid, runnerExitCode: 1 }, suiteId, automationInventorySha256).status, "FAIL");
  assert.equal(normalizeAutomationSuite({ ...valid, tests: valid.tests.map((item, index) => index ? item : { ...item, status: "failed" }) },
    suiteId, automationInventorySha256).status, "FAIL");
  assert.equal(normalizeAutomationSuite({ ...valid, complete: false, tests: valid.tests.map(item => ({ ...item, status: "skipped" })) },
    suiteId, automationInventorySha256).status, "SKIPPED");
  assert.equal(normalizeAutomationSuite({ ...valid, complete: false, tests: valid.tests.map((item, index) => index
    ? { ...item, status: "skipped" } : item) }, suiteId, automationInventorySha256).status, "PARTIAL");
  assert.equal(normalizeAutomationSuite(undefined, suiteId, automationInventorySha256).status, "BLOCKED");
  assert.equal(normalizeAutomationSuites({}, automationInventorySha256).length, 6);
});

test("Coverlet coverage requires valid XML, bounded counts and a passing same-window suite", () => {
  const valid = '<coverage lines-covered="214" lines-valid="507" branches-covered="26" branches-valid="56"><packages/></coverage>';
  const time = Date.parse(window.finishedUtc);
  assert.deepEqual(parseBackendCoverage(valid, time, window, "PASS"),
    { state: "MEASURED", lines: { covered: 214, total: 507 }, branches: { covered: 26, total: 56 } });
  for (const xml of [
    '<!DOCTYPE coverage [<!ENTITY x "x">]>' + valid,
    valid.replace('lines-covered="214"', 'lines-covered="508"'),
    valid.replace('branches-valid="56"', 'branches-valid="0"'),
    valid.replace('branches-covered="26"', 'branches-covered="-1"'),
    valid.replace("<coverage", "<other"), "<coverage>", ""
  ]) assert.equal(parseBackendCoverage(xml, time, window, "PASS").state, "UNAVAILABLE");
  assert.equal(parseBackendCoverage(valid, time + 3000, window, "PASS").state, "UNAVAILABLE");
  assert.equal(parseBackendCoverage(valid, time, window, "FAIL").state, "UNAVAILABLE");
  const report = normalizePhase10Packet(packet, summary, foundations, trxInputs, {
    ...additional, backendCoverage: { Domain: { xml: valid, modifiedUtc: time } }
  });
  assert.match(renderPhase10Report(report), /Domain<\/td><td>214\/507 \(42\.21%\)<\/td><td>26\/56 \(46\.43%\)/);
  assert.match(renderPhase10Report(report), /Coverlet XML root totals; detailed HTML counts only branches attached to source lines and may differ/);
});

test("integration coverage remains separate and requires reconciled passing TRX and run window", () => {
  const xml = '<coverage lines-covered="5" lines-valid="10" branches-covered="2" branches-valid="4"/>';
  const time = Date.parse(window.finishedUtc);
  const input = { ...additional, integrationCoverage: { xml, modifiedUtc: time } };
  const report = normalizePhase10Packet(packet, summary, foundations, trxInputs, input);
  assert.deepEqual(report.integrationCoverage, { state: "MEASURED", lines: { covered: 5, total: 10 },
    branches: { covered: 2, total: 4 } });
  for (const invalid of [
    { ...input, integrationDuplicate: true },
    { ...input, integrationTrx: "<invalid>" },
    { ...input, integrationCoverage: { xml, modifiedUtc: Date.parse(summary.finishedUtc) + 3000 } },
    { ...input, integrationCoverage: { xml: "<invalid>", modifiedUtc: time } }
  ]) {
    assert.equal(normalizePhase10Packet(packet, summary, foundations, trxInputs, invalid).integrationCoverage.state, "UNAVAILABLE");
  }
  const failedPacket = { ...packet, steps: packet.steps.map(step => step.name === "integration"
    ? { ...step, status: "failed" } : step) };
  assert.equal(normalizePhase10Packet(failedPacket, summary, foundations, trxInputs, input).integrationCoverage.state, "UNAVAILABLE");
});

test("frontend coverage requires sane counts, passing runner and matching time window", () => {
  const data = { total: { lines: { covered: 3, total: 4, pct: 999 }, branches: { covered: 1, total: 2 } },
    "PRIVATE_MARKER": { lines: { covered: 0, total: 0 } } };
  const time = Date.parse(window.finishedUtc);
  assert.deepEqual(parseFrontendCoverage(data, time, window, "PASS"),
    { state: "MEASURED", lines: { covered: 3, total: 4 }, branches: { covered: 1, total: 2 } });
  for (const invalid of [
    { total: { lines: { covered: 5, total: 4 }, branches: { covered: 1, total: 2 } } },
    { total: { lines: { covered: 0, total: 0 }, branches: { covered: 1, total: 2 } } },
    { total: { lines: { covered: -1, total: 4 }, branches: { covered: 1, total: 2 } } },
    { total: { lines: { covered: 1.1, total: 4 }, branches: { covered: 1, total: 2 } } },
    {}, null
  ]) assert.equal(parseFrontendCoverage(invalid, time, window, "PASS").state, "UNAVAILABLE");
  assert.equal(parseFrontendCoverage(data, time, window, "FAIL").state, "UNAVAILABLE");
  assert.equal(parseFrontendCoverage(data, time + 3000, window, "PASS").state, "UNAVAILABLE");
  assert.equal(parseFrontendCoverage(data, undefined, window, "PASS").state, "UNAVAILABLE");
  const report = normalizePhase10Packet(packet, summary, foundations, trxInputs,
    { ...additional, frontendCoverage: data, frontendCoverageModifiedUtc: time });
  const html = renderPhase10Report(report);
  assert.match(html, /Lines: 3\/4 \(75\.00%\); branches: 1\/2 \(50\.00%\)/);
  assert.doesNotMatch(html, /PRIVATE_MARKER|999/);
  assert.match(renderPhase10Report(normalizePhase10Packet(packet, summary)), /UNAVAILABLE: no valid same-window coverage/);
});

test("foundation coverage requires reconciled passing test results as well as a passing runner", () => {
  const xml = '<coverage lines-covered="5" lines-valid="10" branches-covered="2" branches-valid="4"/>';
  const coverage = { total: { lines: { covered: 3, total: 4 }, branches: { covered: 1, total: 2 } } };
  const modifiedUtc = Date.parse(window.finishedUtc);
  const input = { ...additional, frontendCoverage: coverage, frontendCoverageModifiedUtc: modifiedUtc,
    backendCoverage: { Domain: { xml, modifiedUtc } } };
  const valid = normalizePhase10Packet(packet, summary, foundations, trxInputs, input);
  assert.equal(valid.backendCoverage.find(item => item.project === "Domain")?.coverage.state, "MEASURED");
  assert.equal(valid.frontendCoverage.state, "MEASURED");

  const skippedTrx = trxXml.replace('outcome="Passed"', 'outcome="NotExecuted"')
    .replace('executed="1" passed="1" failed="0" notExecuted="0"', 'executed="0" passed="0" failed="0" notExecuted="1"');
  for (const invalidTrx of [undefined, "<invalid>", skippedTrx]) {
    const report = normalizePhase10Packet(packet, summary, foundations, { ...trxInputs, Domain: invalidTrx }, input);
    assert.equal(report.backendCoverage.find(item => item.project === "Domain")?.coverage.state, "UNAVAILABLE");
    assert.equal(report.frontendCoverage.state, "MEASURED");
  }
  const pending = { ...vitest, numPassedTests: 0, numPendingTests: 1,
    testResults: [{ ...vitest.testResults[0], assertionResults: [{ status: "pending" }] }] };
  for (const invalidFrontend of [undefined, {}, pending]) {
    const report = normalizePhase10Packet(packet, summary, foundations, trxInputs, { ...input, frontend: invalidFrontend });
    assert.equal(report.frontendCoverage.state, "UNAVAILABLE");
    assert.equal(report.backendCoverage.find(item => item.project === "Domain")?.coverage.state, "MEASURED");
  }
});

test("completion verification rejects absent, altered, contradictory and copied evidence", async () => {
  const parent = await mkdtemp(join(tmpdir(), "phase10-completion-test-"));
  const root = join(parent, "owned-run");
  await mkdir(root);
  const runRoot = join(parent, "owned-run");
  const files = {
    "acceptance-packet.json": JSON.stringify({ status: "passed", runRoot }),
    "run-summary.json": JSON.stringify({ runId: "owned-run", status: "passed", runRoot,
      gitProvenance: { start: { commit: "a".repeat(40), worktree: "clean" }, finish: { commit: "a".repeat(40), worktree: "clean" } } }),
    "phase10-preview.html": "provisional",
    "index.html": "offline report"
  };
  const hashes = Object.fromEntries(Object.entries(files).filter(([name]) => name !== "index.html").map(([name, value]) =>
    [name, createHash("sha256").update(value).digest("hex")]));
  const marker = { schema: "phase10-completion-v1", runId: "owned-run", status: "passed", sha256: hashes };
  const writeMarker = async (value: unknown) => writeFile(join(root, "phase10-completion.json"), JSON.stringify(value));
  try {
    for (const [name, value] of Object.entries(files)) await writeFile(join(root, name), value);
    assert.deepEqual(await verifyPhase10Completion(root), { state: "INCOMPLETE" });
    await writeMarker(marker);
    assert.deepEqual(await verifyPhase10Completion(root), { state: "COMPLETE", status: "passed" });
    const coverage = '{"schema":"phase10-sanitized-coverage-v1"}';
    await writeFile(join(root, "phase10-coverage-summary.json"), coverage);
    const v2 = { ...marker, schema: "phase10-completion-v2", sha256: {
      ...hashes, "phase10-coverage-summary.json": createHash("sha256").update(coverage).digest("hex")
    } };
    await writeMarker(v2);
    assert.deepEqual(await verifyPhase10Completion(root), { state: "COMPLETE", status: "passed" });
    const index = { ...files, "phase10-coverage-summary.json": coverage };
    const v3 = { ...v2, schema: "phase10-completion-v3", sha256: {
      ...v2.sha256, "index.html": createHash("sha256").update(index["index.html"]).digest("hex")
    } };
    await writeMarker(v3);
    assert.deepEqual(await verifyPhase10Completion(root), { state: "COMPLETE", status: "passed" });
    const services = ["sql-server", "redis", "azurite", "servicebus-sql", "servicebus-emulator", "keycloak-local", "orders", "payments", "inventory", "notifications", "gateway", "ui", "functions"];
    const manifest = (capturePoint: "before" | "after") => JSON.stringify({
      schema: "phase10-docker-image-identities-v1", runId: "owned-run", capturePoint,
      candidate: { commit: "a".repeat(40), worktree: "clean", dirtyStatusSha256: null }, buildLogsSha256: {},
      images: services.map((service, index) => ({ project: "xy-phase10", service, containerId: index.toString(16).padStart(12, "0"),
        imageReference: `${service}:dev`, imageId: `sha256:${(index + 1).toString(16).padStart(64, "0")}`, repositoryDigests: [] }))
    });
    const before = manifest("before");
    const after = manifest("after");
    await writeFile(join(root, "docker-image-identities-before.json"), before);
    await writeFile(join(root, "docker-image-identities-after.json"), after);
    const v4 = { ...v3, schema: "phase10-completion-v4", sha256: {
      ...v3.sha256,
      "docker-image-identities-before.json": createHash("sha256").update(before).digest("hex"),
      "docker-image-identities-after.json": createHash("sha256").update(after).digest("hex")
    } };
    await writeMarker(v4);
    assert.deepEqual(await verifyPhase10Completion(root), { state: "COMPLETE", status: "passed" });
    await rm(join(root, "docker-image-identities-before.json"));
    assert.deepEqual(await verifyPhase10Completion(root), { state: "INCOMPLETE" });
    await writeFile(join(root, "docker-image-identities-before.json"), before);
    await writeMarker(v4);
    const malformedImages = JSON.stringify({ schema: "phase10-docker-image-identities-v1", runId: "owned-run", capturePoint: "before" });
    await writeFile(join(root, "docker-image-identities-before.json"), malformedImages);
    await writeMarker({ ...v4, sha256: { ...v4.sha256,
      "docker-image-identities-before.json": createHash("sha256").update(malformedImages).digest("hex") } });
    assert.deepEqual(await verifyPhase10Completion(root), { state: "INCOMPLETE" });
    await writeFile(join(root, "docker-image-identities-before.json"), before);
    await writeMarker(v4);
    const changedImages = JSON.parse(after) as { images: { service: string; imageId: string }[] };
    changedImages.images.find(image => image.service === "inventory")!.imageId = `sha256:${"f".repeat(64)}`;
    const changedAfter = JSON.stringify(changedImages);
    await writeFile(join(root, "docker-image-identities-after.json"), changedAfter);
    await writeMarker({ ...v4, sha256: { ...v4.sha256,
      "docker-image-identities-after.json": createHash("sha256").update(changedAfter).digest("hex") } });
    assert.deepEqual(await verifyPhase10Completion(root), { state: "INCOMPLETE" });
    await writeFile(join(root, "docker-image-identities-after.json"), after);
    await writeMarker(v4);
    await writeFile(join(root, "phase10-coverage-summary.json"), "modified");
    assert.deepEqual(await verifyPhase10Completion(root), { state: "INCOMPLETE" });
    await rm(join(root, "phase10-coverage-summary.json"));
    assert.deepEqual(await verifyPhase10Completion(root), { state: "INCOMPLETE" });
    await writeMarker(marker);
    const copied = join(parent, "different-run");
    await mkdir(copied);
    for (const [name, value] of Object.entries(files)) await writeFile(join(copied, name), value);
    await writeFile(join(copied, "phase10-completion.json"), JSON.stringify(marker));
    assert.deepEqual(await verifyPhase10Completion(copied), { state: "INCOMPLETE" });
    await writeFile(join(root, "phase10-preview.html"), "changed");
    assert.deepEqual(await verifyPhase10Completion(root), { state: "INCOMPLETE" });
    await writeFile(join(root, "phase10-preview.html"), files["phase10-preview.html"]);
    for (const invalid of [
      { ...marker, schema: "other" }, { ...marker, runId: "other" },
      { ...marker, status: "failed" }, { ...marker, sha256: { ...hashes, "run-summary.json": "0".repeat(64) } },
      { ...marker, sha256: { ...hashes, extra: "0".repeat(64) } }
    ]) {
      await writeMarker(invalid);
      assert.deepEqual(await verifyPhase10Completion(root), { state: "INCOMPLETE" });
    }
    const badPacket = JSON.stringify({ status: "passed", runRoot: "other" });
    await writeFile(join(root, "acceptance-packet.json"), badPacket);
    await writeMarker({ ...marker, sha256: { ...hashes, "acceptance-packet.json": createHash("sha256").update(badPacket).digest("hex") } });
    assert.deepEqual(await verifyPhase10Completion(root), { state: "INCOMPLETE" });
    await writeFile(join(root, "phase10-completion.json"), "{");
    assert.deepEqual(await verifyPhase10Completion(root), { state: "INCOMPLETE" });
    await assert.rejects(execFileAsync(process.execPath, ["--import", "tsx", "src/cli/verify-phase10-completion.ts", root]),
      (error: unknown) => typeof error === "object" && error !== null && "code" in error && error.code === 2);
  } finally { await rm(parent, { recursive: true, force: true }); }
});

test("complete packet remains blocked until independent L5-R gates are implemented", () => {
  const result = normalizePhase10Packet(packet, summary, foundations, trxInputs, additional);
  assert.equal(result.overall, "BLOCKED");
  assert.equal(result.steps.length, DOCKER_PACKET_STEPS.length);
  assert.equal(result.restoration, "PASS");
  assert.equal(result.storage, "PASS");
  assert.equal(result.issues.length, 14);
  assert.match(renderPhase10Report(result), /cannot certify/);
});

test("Git provenance is allowlisted, provisional, and never inferred from historical runs", () => {
  const commit = "a".repeat(40);
  const result = normalizePhase10Packet(packet, {
    ...summary, gitProvenance: {
      start: { commit, worktree: "dirty", extra: "PRIVATE_MARKER" },
      finish: { commit: "b".repeat(64), worktree: "clean" }
    }
  });
  assert.deepEqual(result.git, {
    start: { commit, worktree: "DIRTY" }, finish: { commit: "b".repeat(64), worktree: "CLEAN" }
  });
  assert.match(renderPhase10Report(result), /do not identify built or running images/);
  assert.doesNotMatch(renderPhase10Report(result), /PRIVATE_MARKER/);
  const malformed = normalizePhase10Packet(packet, {
    ...summary, gitProvenance: { start: { commit: "<script>", worktree: "clean<script>" } }
  });
  assert.deepEqual(malformed.git.start, { commit: null, worktree: "UNKNOWN" });
  assert.deepEqual(malformed.git.finish, { commit: null, worktree: "UNKNOWN" });
  assert.doesNotMatch(renderPhase10Report(malformed), /<script>/);
  assert.deepEqual(normalizePhase10Packet(packet, summary).git.start, { commit: null, worktree: "UNKNOWN" });
});

test("Docker image identities are validated, rendered escaped, and never inferred when absent", () => {
  const services = ["sql-server", "redis", "azurite", "servicebus-sql", "servicebus-emulator", "keycloak-local", "orders", "payments", "inventory", "notifications", "gateway", "ui", "functions"];
  const manifest = (capturePoint: "before" | "after") => ({ schema: "phase10-docker-image-identities-v1",
    runId: summary.runId, capturePoint, candidate: { commit: "a".repeat(40), worktree: "clean", dirtyStatusSha256: null },
    buildLogsSha256: {}, images: services.map((service, index) => ({ project: "xy-phase10", service,
      containerId: index.toString(16).padStart(12, "0"), imageReference: `${service}:dev`,
      imageId: `sha256:${(index + 1).toString(16).padStart(64, "0")}`, repositoryDigests: [] })) });
  const before = manifest("before");
  const after = manifest("after");
  before.images[0].imageReference = '<img src=x onerror="alert(1)">';
  after.images[0].imageReference = '<img src=x onerror="alert(1)">';
  const valid = normalizePhase10Packet(packet, { ...summary, gitProvenance: {
    start: { commit: "a".repeat(40), worktree: "clean" }, finish: { commit: "a".repeat(40), worktree: "clean" }
  } }, foundations, trxInputs, { ...additional, dockerImageBefore: before, dockerImageAfter: after });
  assert.equal(valid.imageIdentities.status, "PASS");
  const html = renderPhase10Report(valid);
  assert.match(html, /&lt;img src=x onerror=&quot;alert\(1\)&quot;&gt;/);
  assert.doesNotMatch(html, /<img src=x/);
  const missing = normalizePhase10Packet(packet, summary, foundations, trxInputs, additional);
  assert.equal(missing.imageIdentities.status, "BLOCKED");
  assert.match(renderPhase10Report(missing), /Image identity: BLOCKED/);
});

test("suite selection is separate from step outcome and unknown selection is explicit", () => {
  const steps = DOCKER_PACKET_STEPS.map(name => ({
    name, status: name === "sandbox-payments" || name === "order-continuation" ? "not-run" : "passed"
  }));
  const deterministic = normalizePhase10Packet({ ...packet, steps }, { ...summary, paymentSuite: "deterministic" }, foundations, trxInputs, additional);
  assert.equal(deterministic.steps.find(step => step.name === "sandbox-payments")?.selection, "NOT-SELECTED");
  assert.equal(deterministic.steps.find(step => step.name === "payments-deterministic")?.selection, "SELECTED");
  assert.equal(deterministic.steps.find(step => step.name === "persistence")?.selection, "UNKNOWN");
  assert.equal(deterministic.issues.length, 14);
  const unknown = normalizePhase10Packet(packet, { ...summary, paymentSuite: "unexpected" });
  assert.equal(unknown.paymentSuite, "UNKNOWN");
  assert.equal(unknown.steps.find(step => step.name === "sandbox-payments")?.selection, "UNKNOWN");
  assert.ok(unknown.issues.some(issue => issue.includes("selection")));
});

test("integration and frontend results are reconciled without exposing raw test details", () => {
  const result = normalizePhase10Packet(packet, summary, foundations, trxInputs, additional);
  assert.equal(result.integration.status, "PASS");
  assert.equal(result.frontend.status, "PASS");
  assert.deepEqual(result.frontend.counts, { total: 1, passed: 1, failed: 0, pending: 0, todo: 0 });
  assert.doesNotMatch(renderPhase10Report(result), /secret|<script>/);
  const duplicate = normalizePhase10Packet(packet, summary, foundations, trxInputs, { ...additional, integrationDuplicate: true });
  assert.equal(duplicate.integration.status, "BLOCKED");
  assert.ok(duplicate.issues.some(issue => issue.includes("Integration TRX")));
  assert.equal(parseVitest({ ...vitest, numTotalTests: 2 }, window, "PASS").status, "BLOCKED");
  assert.equal(parseVitest({ ...vitest, startTime: 0 }, window, "PASS").status, "BLOCKED");
  assert.equal(parseVitest(vitest, window, "FAIL").status, "BLOCKED");
  const failed = { ...vitest, success: false, numPassedTests: 0, numFailedTests: 1,
    testResults: [{ ...vitest.testResults[0], status: "failed", assertionResults: [{ status: "failed" }] }] };
  assert.equal(parseVitest(failed, window, "FAIL").status, "FAIL");
  const pending = { ...vitest, numPassedTests: 0, numPendingTests: 1,
    testResults: [{ ...vitest.testResults[0], assertionResults: [{ status: "pending" }] }] };
  assert.equal(parseVitest(pending, window, "PASS").status, "PARTIAL");
  const sanitized = { schema: "phase10-vitest-sanitized-v1", startTime: Date.parse(window.startedUtc),
    endTime: Date.parse(window.finishedUtc), success: true, interrupted: false, states: ["passed"] };
  assert.equal(parseVitest(sanitized, window, "PASS").status, "PASS");
  assert.equal(parseVitest({ ...sanitized, interrupted: true }, window, "PASS").status, "BLOCKED");
  assert.equal(parseVitest({ ...sanitized, states: ["failed"] }, window, "PASS").status, "BLOCKED");
  assert.equal(parseVitest({ ...sanitized, states: ["unfinished"] }, window, "PASS").status, "BLOCKED");
  assert.equal(parseVitest({ ...sanitized, endTime: Number.POSITIVE_INFINITY }, window, "PASS").status, "BLOCKED");
});

test("structured source inventory displays bounded anonymous reconciled outcomes", () => {
  assert.equal(FOUNDATION_AUTOMATION_TEST_CHECKS.length, 6);
  assert.equal(new Set(FOUNDATION_AUTOMATION_TEST_CHECKS).size, 6);
  assert.ok(FOUNDATION_AUTOMATION_TEST_CHECKS.every(name => FOUNDATION_CHECKS.some(check => check === name)));
  const states = [...Array<string>(100).fill("passed"), "failed", "pending", "todo"];
  const sanitized = { schema: "phase10-vitest-sanitized-v1", startTime: Date.parse(window.startedUtc),
    endTime: Date.parse(window.finishedUtc), success: false, interrupted: false, states };
  const frontend = parseVitest(sanitized, window, "FAIL");
  assert.equal(frontend.status, "FAIL");
  assert.deepEqual(frontend.counts, { total: 103, passed: 100, failed: 1, pending: 1, todo: 1 });
  assert.equal(frontend.outcomes?.length, 100);
  assert.equal(parseVitest({ ...sanitized, states: [...states, "unknown"] }, window, "FAIL").outcomes, null);
  const small = parseVitest({ ...sanitized, states: ["passed", "failed", "pending", "todo"] }, window, "FAIL");
  assert.deepEqual(small.outcomes, ["PASS", "FAIL", "PENDING", "TODO"]);

  const failedXml = trxXml.replace('outcome="Passed"', 'outcome="Failed"')
    .replace('outcome="Completed"', 'outcome="Failed"').replace('passed="1" failed="0"', 'passed="0" failed="1"');
  const skippedXml = trxXml.replace('outcome="Passed"', 'outcome="NotExecuted"')
    .replace('executed="1" passed="1" failed="0" notExecuted="0"', 'executed="0" passed="0" failed="0" notExecuted="1"');
  assert.deepEqual(parseFoundationTrx("Domain", failedXml, window, "FAIL").outcomes, ["FAIL"]);
  assert.deepEqual(parseFoundationTrx("Domain", skippedXml, window, "PASS").outcomes, ["NOT-EXECUTED"]);
  assert.equal(parseFoundationTrx("Domain", trxXml.replace('passed="1"', 'passed="2"'), window, "PASS").outcomes, null);
  const longResults = Array.from({ length: 101 }, (_, index) =>
    `<UnitTestResult executionId="01234567-89ab-cdef-0123-${index.toString(16).padStart(12, "0")}" testName="synthetic test ${index}" outcome="Passed"/>`).join("");
  const longTrx = trxXml.replace(/<UnitTestResult[^/]+\/>/, longResults)
    .replace('total="1" executed="1" passed="1"', 'total="101" executed="101" passed="101"');
  const longResult = parseFoundationTrx("Domain", longTrx, window, "PASS");
  assert.equal(longResult.counts?.total, 101);
  assert.equal(longResult.outcomes?.length, 100);

  const failedFoundations = { ...foundations, status: "failed", results: foundations.results.map(entry =>
    entry.name === "frontend-tests" ? { ...entry, status: "failed", exitCode: 1 } : entry) };
  const result = normalizePhase10Packet(packet, summary, failedFoundations, trxInputs,
    { ...additional, frontend: sanitized, integrationDuplicate: true });
  const html = renderPhase10Report(result);
  assert.match(html, /These fixed sources are only a subset of Phase 10 suites/);
  assert.match(html, /Six automation suites reconcile against a versioned expected-test inventory/);
  assert.match(html, /<td>test-payment-evidence<\/td><td>PASS<\/td><td>BLOCKED<\/td><td>UNAVAILABLE<\/td>/);
  assert.match(html, /test-callbacks-browser: UNAVAILABLE/);
  assert.match(html, /omitted tests cannot be detected from counts alone/);
  assert.match(html, /<td>Frontend<\/td><td>FAIL<\/td><td>FAIL<\/td><td>103<\/td>/);
  assert.match(html, /Frontend: showing 100 of 103 outcomes/);
  assert.match(html, /Integration: UNAVAILABLE/);
  assert.match(html, /Other source outcomes remain anonymous input-order positions/);
  assert.doesNotMatch(html, /secret|<script>|01234567/);
  const empty = renderPhase10Report(normalizePhase10Packet(null, null));
  assert.match(empty, /Domain foundation: UNAVAILABLE/);
  assert.match(empty, /<td>Frontend<\/td><td>NOT-RUN<\/td><td>BLOCKED<\/td><td>UNAVAILABLE<\/td>/);
});

test("automation test inventory matches the foundation runner and package scripts", async () => {
  const runner = await readFile(resolve("../scripts/run-phase10-foundation-tests.ps1"), "utf8");
  const suiteLoop = runner.match(/foreach\(\$suite in @\(([^)]*)\)\)/);
  assert.ok(suiteLoop, "Foundation automation suite loop is missing or changed");
  const scripts = [...suiteLoop[1].matchAll(/'([^']+)'/g)].map(match => match[1]);
  assert.deepEqual(scripts.map(name => name.replaceAll(":", "-")), [...FOUNDATION_AUTOMATION_TEST_CHECKS]);
  const expectedInventory: unknown = JSON.parse(await readFile(resolve("config/phase10-automation-test-inventory.json"), "utf8"));
  assert.ok(expectedInventory && typeof expectedInventory === "object" && "suites" in expectedInventory && Array.isArray(expectedInventory.suites));
  for (const suite of expectedInventory.suites) {
    assert.ok(suite && typeof suite === "object" && "id" in suite && "file" in suite && "tests" in suite);
    const suiteId = String(suite.id);
    assert.ok(suiteId in Object.fromEntries(FOUNDATION_AUTOMATION_TEST_CHECKS.map(id => [id, true])));
    const source = await readFile(new URL(`../../${String(suite.file)}`, import.meta.url), "utf8");
    const actualNames = [...source.matchAll(/(?:\btest|\bdescribe)\s*\(\s*(["'])(.*?)\1/g)].map(match => match[2]);
    assert.deepEqual(suite.tests, actualNames, `Expected test inventory drifted: ${suiteId}`);
  }
  const manifest: unknown = JSON.parse(await readFile(resolve("package.json"), "utf8"));
  assert.ok(manifest && typeof manifest === "object" && "scripts" in manifest &&
    manifest.scripts && typeof manifest.scripts === "object");
  for (const script of scripts) {
    assert.ok(script in manifest.scripts, `Missing automation package script: ${script}`);
  }
});

test("discovered .NET inventory IDs reconcile to exact TRX counts, outcomes and run window", () => {
  const project = "Domain";
  const id = `${project}:${createHash("sha256").update("synthetic test name").digest("hex")}`;
  const fingerprint = createHash("sha256").update(id).digest("hex");
  const suite = { schema: "phase10-dotnet-test-results-v1", project, runnerExitCode: 0, complete: true,
    startedUtc: window.startedUtc, finishedUtc: window.finishedUtc, assemblySha256: "a".repeat(64),
    inventorySha256: fingerprint, expectedIds: [id], expectedCount: 1, observedCount: 1,
    missingCount: 0, unexpectedCount: 0, duplicateCount: 0, tests: [{ id, status: "passed" }] };
  const trx = { status: "PASS" as const, counts: { total: 1, passed: 1, failed: 0, skipped: 0 },
    identities: [{ id, status: "PASS" }] };
  assert.equal(normalizeDiscoveredDotnetSuite(suite, project, trx, window).status, "PASS");
  assert.equal(normalizeDiscoveredDotnetSuite(suite, project, { ...trx,
    identities: [{ id: `${project}:${"0".repeat(64)}`, status: "PASS" }] }, window).status, "BLOCKED");
  assert.equal(normalizeDiscoveredDotnetSuite({ ...suite, observedCount: 0, tests: [] }, project, trx, window).status, "BLOCKED");
  assert.equal(normalizeDiscoveredDotnetSuite({ ...suite, expectedIds: [id, id], expectedCount: 2 }, project, trx, window).status, "BLOCKED");
  assert.equal(normalizeDiscoveredDotnetSuite({ ...suite, inventorySha256: "0".repeat(64) }, project, trx, window).status, "BLOCKED");
  assert.equal(normalizeDiscoveredDotnetSuite({ ...suite, startedUtc: "2020-01-01T00:00:00Z" }, project, trx, window).status, "BLOCKED");
  assert.equal(normalizeDiscoveredDotnetSuite({ ...suite, runnerExitCode: 1 }, project, { ...trx, status: "FAIL" }, window).status, "FAIL");
  const integrationId = `Integration:${createHash("sha256").update("synthetic test name").digest("hex")}`;
  const integration = { ...suite, project: "Integration", expectedIds: [integrationId],
    inventorySha256: createHash("sha256").update(integrationId).digest("hex"),
    tests: [{ id: integrationId, status: "passed" }] };
  const integrationTrx = parseFoundationTrx("Integration", trxXml, window, "PASS");
  assert.equal(normalizeDiscoveredDotnetSuite(integration, "Integration", integrationTrx, window).status, "PASS");
  assert.equal(normalizeDiscoveredDotnetSuite(integration, "Integration", { ...integrationTrx,
    identities: [{ id: `Integration:${"0".repeat(64)}`, status: "PASS" }] }, window).status, "BLOCKED");
});

test("sanitized frontend reporter retains outcomes but omits test names and errors", async () => {
  const root = await mkdtemp(join(tmpdir(), "phase10-vitest-reporter-"));
  const runner = resolve("../frontend/node_modules/vitest/vitest.mjs");
  const reporter = resolve("../frontend/apps/web/scripts/phase10-sanitized-reporter.mjs");
  try {
    const fixture = join(root, "fixture.test.js");
    const output = join(root, "frontend-vitest.json");
    await writeFile(fixture, `import { test, expect } from "vitest";
test("PRIVATE_MARKER", () => expect(1).toBe(1));
test("PRIVATE_MARKER", () => expect(2).toBe(2));
test.skip("skipped", () => {});
test.todo("todo");`);
    const run = async () => execFileAsync(process.execPath, [runner, "run", "--root", root, "--reporter", reporter],
      { env: { ...process.env, PHASE10_FRONTEND_REPORT: output } });
    const before = Date.now();
    await run();
    const after = Date.now();
    const text = await readFile(output, "utf8");
    assert.doesNotMatch(text, /PRIVATE_MARKER|fixture|error/i);
    const payload: unknown = JSON.parse(text);
    const parsed = parseVitest(payload, { startedUtc: new Date(before).toISOString(), finishedUtc: new Date(after).toISOString() }, "PASS");
    assert.deepEqual(parsed.counts,
      { total: 4, passed: 2, failed: 0, pending: 1, todo: 1 });
    assert.equal(parsed.identities?.length, 4);
    assert.equal(new Set(parsed.identities?.map(identity => identity.id)).size, 4);
    const structured = payload as { tests: { id: string; status: string }[]; inventorySha256: string };
    assert.equal(parseVitest({ ...structured, tests: structured.tests.slice(1) },
      { startedUtc: new Date(before).toISOString(), finishedUtc: new Date(after).toISOString() }, "PASS").status, "BLOCKED");
    assert.equal(parseVitest({ ...structured, inventorySha256: "0".repeat(64) },
      { startedUtc: new Date(before).toISOString(), finishedUtc: new Date(after).toISOString() }, "PASS").status, "BLOCKED");
    await assert.rejects(run());
    assert.equal(await readFile(output, "utf8"), text);
    await rm(output);
    await writeFile(fixture, `import { test, expect } from "vitest"; test("PRIVATE_MARKER", () => expect("PRIVATE_MARKER").toBe("expected"));`);
    const failStart = Date.now();
    await assert.rejects(run());
    const failed = await readFile(output, "utf8");
    assert.doesNotMatch(failed, /PRIVATE_MARKER|fixture|expected/);
    assert.equal(parseVitest(JSON.parse(failed), { startedUtc: new Date(failStart).toISOString(), finishedUtc: new Date().toISOString() }, "FAIL").status, "FAIL");
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("TRX counters, results, timestamps and runner outcome must reconcile", () => {
  assert.deepEqual(parseFoundationTrx("Domain", trxXml, window, "PASS").counts,
    { total: 1, passed: 1, failed: 0, skipped: 0 });
  for (const xml of [
    trxXml.replace('passed="1"', 'passed="2"'),
    trxXml.replace('outcome="Passed"', 'outcome="Unknown"'),
    trxXml.replace('2026-11-09T21:45:16.900Z', '2020-01-01T00:00:00Z'),
    trxXml.replace("</Results>", '<UnitTestResult executionId="01234567-89ab-cdef-0123-456789abcdef" outcome="Passed"/></Results>'),
    trxXml.replace("<TestRun", '<!DOCTYPE TestRun [<!ENTITY x "x">]><TestRun'),
    trxXml.slice(0, -10),
    trxXml.replace('xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010"', 'xmlns="urn:wrong"')
  ]) {
    assert.equal(parseFoundationTrx("Domain", xml, window, "PASS").status, "BLOCKED");
  }
  assert.equal(parseFoundationTrx("Domain", undefined, window, "PASS").counts, null);
  assert.equal(parseFoundationTrx("Domain", trxXml, null, "PASS").status, "BLOCKED");
  const failed = trxXml.replace('outcome="Passed"', 'outcome="Failed"')
    .replace('outcome="Completed"', 'outcome="Failed"').replace('passed="1" failed="0"', 'passed="0" failed="1"');
  assert.equal(parseFoundationTrx("Domain", failed, window, "FAIL").status, "FAIL");
  assert.equal(parseFoundationTrx("Domain", failed, window, "PASS").status, "BLOCKED");
  const skipped = trxXml.replace('outcome="Passed"', 'outcome="NotExecuted"')
    .replace('executed="1" passed="1" failed="0" notExecuted="0"', 'executed="0" passed="0" failed="0" notExecuted="1"');
  assert.deepEqual(parseFoundationTrx("Domain", skipped, window, "PASS").counts,
    { total: 1, passed: 0, failed: 0, skipped: 1 });
  assert.equal(parseFoundationTrx("Domain", skipped, window, "PASS").status, "PARTIAL");
  assert.equal(parseFoundationTrx("Domain", trxXml.replace('failed="0"', 'failed="0" error="1"'), window, "PASS").status, "BLOCKED");
});

test("foundation summary reconciles missing, duplicate, stale and contradictory results", () => {
  const runStart = summary.startedUtc;
  const runEnd = summary.finishedUtc;
  assert.ok(FOUNDATION_CHECKS.includes("docker-image-evidence"));
  assert.equal(normalizeFoundationSummary(foundations, runStart, runEnd).issues.length, 0);
  const missing = normalizeFoundationSummary({ status: "passed", results: [] }, runStart, runEnd);
  assert.equal(missing.checks[0].status, "NOT-RUN");
  assert.ok(missing.issues.some(issue => issue.includes("incomplete")));
  const duplicate = normalizeFoundationSummary({
    status: "passed", results: [...foundations.results, { ...foundations.results[0], status: "failed", exitCode: 1 }]
  }, runStart, runEnd);
  assert.equal(duplicate.checks[0].status, "BLOCKED");
  assert.equal(duplicate.hasFailure, true);
  const stale = normalizeFoundationSummary({
    status: "passed", results: [{ ...foundations.results[0], startedUtc: "2020-01-01T00:00:00Z" }]
  }, runStart, runEnd);
  assert.equal(stale.checks[0].status, "BLOCKED");
  const contradiction = normalizePhase10Packet(packet, summary, {
    status: "passed", results: [{ ...foundations.results[0], status: "failed", exitCode: 1 }]
  });
  assert.equal(contradiction.overall, "FAIL");
  assert.ok(contradiction.issues.some(issue => issue.includes("foundations PASS")));
});

test("foundation untrusted names and errors never enter the report", () => {
  const report = normalizePhase10Packet(packet, summary, {
    status: "passed", results: [{ name: "<script>secret</script>", status: "failed", exitCode: 1 }]
  });
  assert.equal(report.overall, "FAIL");
  assert.doesNotMatch(renderPhase10Report(report), /<script>|secret/);
});

test("failed or contradictory restoration and storage cannot be hidden", () => {
  for (const change of [
    { restoration: { status: "passed", allRestored: false, fixtureLockPresent: false } },
    { restoration: { status: "passed", allRestored: true, fixtureLockPresent: true } },
    { storageExitCode: 1 }
  ]) {
    const result = normalizePhase10Packet({ ...packet, ...change }, summary);
    assert.equal(result.overall, "FAIL");
    assert.ok(result.issues.some(issue => issue.includes("despite")));
  }
  const incomplete = normalizePhase10Packet({ ...packet, restoration: {}, storageExitCode: undefined }, summary);
  assert.equal(incomplete.restoration, "BLOCKED");
  assert.equal(incomplete.storage, "BLOCKED");
  assert.ok(incomplete.issues.length);
});

test("mismatched run identities and invalid timestamps are visible", () => {
  const result = normalizePhase10Packet({ ...packet, runRoot: "other-run" },
    { ...summary, startedUtc: "2026-11-10T00:00:00Z", finishedUtc: "2026-11-09T00:00:00Z" });
  assert.ok(result.issues.some(issue => issue.includes("paths disagree")));
  assert.ok(result.issues.some(issue => issue.includes("timestamps")));
  assert.equal(result.overall, "BLOCKED");
});

test("missing and malformed results never pass", () => {
  const result = normalizePhase10Packet({ status: "passed", steps: [{ name: "smoke", status: "mystery" }] }, null);
  assert.equal(result.overall, "BLOCKED");
  assert.equal(result.steps.find(step => step.name === "smoke")?.status, "BLOCKED");
  assert.equal(result.steps.find(step => step.name === "integration")?.status, "NOT-RUN");
  assert.ok(result.issues.length);
});

test("inventory reconciliation counts statuses and selection independently without implying complete acceptance", () => {
  const selectedSummary = { ...summary, paymentSuite: "deterministic" };
  const steps = packet.steps.filter(step => step.name !== "payments-deterministic" && step.name !== "sandbox-payments");
  steps.push({ name: "smoke", status: "failed" });
  const result = normalizePhase10Packet({ ...packet, steps }, selectedSummary, foundations, trxInputs, additional);
  const html = renderPhase10Report(result);
  assert.equal(result.overall, "FAIL");
  assert.equal(result.steps.find(step => step.name === "smoke")?.status, "BLOCKED");
  assert.ok(result.issues.includes("Packet reports PASS with an incomplete or unsuccessful selected payment suite."));
  assert.match(html, /Docker packet steps: 14; PASS: 11; FAIL: 0; PARTIAL: 0; BLOCKED: 1; SKIPPED: 0; NOT-RUN: 2; DEFERRED: 0/);
  assert.match(html, /Packet selection: SELECTED: 1; NOT-SELECTED: 2; UNKNOWN: 11/);
  assert.match(html, /Foundation runner checks: 19; PASS: 19; FAIL: 0; PARTIAL: 0; BLOCKED: 0; SKIPPED: 0; NOT-RUN: 0; DEFERRED: 0/);
  assert.match(html, /not individual test totals or acceptance gates/);
  assert.match(html, /Duplicates are BLOCKED; failures in conflicting entries still affect the overall result/);
  const empty = renderPhase10Report(normalizePhase10Packet(null, null));
  assert.match(empty, /Docker packet steps: 14; PASS: 0; FAIL: 0; PARTIAL: 0; BLOCKED: 0; SKIPPED: 0; NOT-RUN: 14; DEFERRED: 0/);
  assert.match(empty, /Foundation runner checks: 19; PASS: 0; FAIL: 0; PARTIAL: 0; BLOCKED: 0; SKIPPED: 0; NOT-RUN: 19; DEFERRED: 0/);
  const deferred = normalizePhase10Packet({ ...packet, steps: packet.steps.map(step =>
    step.name === "order-continuation" ? { ...step, status: "deferred" } : step) }, summary, foundations, trxInputs, additional);
  assert.equal(deferred.steps.find(step => step.name === "order-continuation")?.status, "DEFERRED");
  assert.ok(!deferred.issues.includes("Packet reports PASS with an incomplete or unsuccessful selected payment suite."));
});

test("duplicate and conflicting results are visible", () => {
  const result = normalizePhase10Packet({ status: "passed", steps: [
    { name: "smoke", status: "passed" }, { name: "smoke", status: "failed" },
    { name: "integration", status: "failed" }
  ] }, summary);
  assert.equal(result.overall, "FAIL");
  assert.equal(result.steps.find(step => step.name === "smoke")?.status, "BLOCKED");
  assert.ok(result.issues.some(issue => issue.includes("Duplicate")));
  assert.ok(result.issues.some(issue => issue.includes("despite")));
});

test("a failure inside duplicate steps cannot be hidden", () => {
  const result = normalizePhase10Packet({ status: "passed", steps: [
    { name: "smoke", status: "passed" }, { name: "smoke", status: "failed" }
  ] }, summary);
  assert.equal(result.overall, "FAIL");
});

test("untrusted free text and sensitive details are not reproduced", () => {
  const result = normalizePhase10Packet({ status: "passed", steps: [
    { name: "smoke", status: "deferred", error: "<script>secret</script>" }
  ] }, { runId: "<script>secret</script>", status: "partial" });
  const html = renderPhase10Report(result);
  assert.equal(result.steps.find(step => step.name === "smoke")?.status, "DEFERRED");
  assert.ok(result.issues.some(issue => issue.includes("disagree")));
  assert.doesNotMatch(html, /<script>|secret/);
  assert.equal(result.runId, null);
});

test("CLI renders malformed evidence as blocked and refuses to overwrite", async () => {
  const root = await mkdtemp(join(tmpdir(), "phase10-preview-test-"));
  try {
    await writeFile(join(root, "acceptance-packet.json"), "{bad json");
    const args = ["--import", "tsx", "src/cli/render-phase10-preview.ts", root];
    await execFileAsync(process.execPath, args);
    const output = join(root, "phase10-preview.html");
    const html = await readFile(output, "utf8");
    assert.equal(await readFile(join(root, "index.html"), "utf8"), html);
    assert.match(html, /Overall: BLOCKED/);
    assert.match(html, /Acceptance packet missing or malformed/);
    assert.match(html, /href="phase10-coverage-summary\.json"/);
    const sanitized = JSON.parse(await readFile(join(root, "phase10-coverage-summary.json"), "utf8")) as {
      schema: string; provisional: boolean; integration: { state: string };
    };
    assert.equal(sanitized.schema, "phase10-sanitized-coverage-v2");
    assert.equal(sanitized.provisional, true);
    assert.equal(sanitized.integration.state, "UNAVAILABLE");
    await assert.rejects(execFileAsync(process.execPath, args));
    assert.equal(await readFile(output, "utf8"), html);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("CLI refuses an existing coverage output without replacing it", async () => {
  const root = await mkdtemp(join(tmpdir(), "phase10-preview-test-"));
  try {
    const coveragePath = join(root, "phase10-coverage-summary.json");
    await writeFile(coveragePath, "existing");
    await assert.rejects(execFileAsync(process.execPath, ["--import", "tsx", "src/cli/render-phase10-preview.ts", root]));
    assert.equal(await readFile(coveragePath, "utf8"), "existing");
    assert.equal(await readFile(join(root, "phase10-preview.html"), "utf8"), "");
    assert.equal(await readFile(join(root, "index.html"), "utf8"), "");
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("CLI reads the same-run foundation summary without changing input", async () => {
  const root = await mkdtemp(join(tmpdir(), "phase10-preview-test-"));
  try {
    await mkdir(join(root, "foundations"));
    await writeFile(join(root, "acceptance-packet.json"), JSON.stringify(packet));
    await writeFile(join(root, "run-summary.json"), JSON.stringify(summary));
    const source = JSON.stringify(foundations);
    await writeFile(join(root, "foundations", "summary.json"), source);
    await writeFile(join(root, "foundations", "frontend-vitest.json"), JSON.stringify(vitest));
    const coverageDirectory = join(root, "foundations", "frontend-coverage");
    await mkdir(coverageDirectory);
    const coveragePath = join(coverageDirectory, "coverage-summary.json");
    await writeFile(coveragePath, JSON.stringify({
      total: { lines: { covered: 3, total: 4 }, branches: { covered: 1, total: 2 } }
    }));
    await utimes(coveragePath, new Date(window.finishedUtc), new Date(window.finishedUtc));
    const domainCoverage = join(root, "foundations", "backend-coverage", "Domain", "01234567-89ab-cdef-0123-456789abcdef");
    await mkdir(domainCoverage, { recursive: true });
    const domainCoveragePath = join(domainCoverage, "coverage.cobertura.xml");
    await writeFile(domainCoveragePath, '<coverage lines-covered="3" lines-valid="4" branches-covered="1" branches-valid="2"/>');
    await utimes(domainCoveragePath, new Date(window.finishedUtc), new Date(window.finishedUtc));
    await mkdir(join(root, "integration"));
    await writeFile(join(root, "integration", "integration-1.trx"), trxXml);
    const integrationId = `Integration:${createHash("sha256").update("synthetic test name").digest("hex")}`;
    await writeFile(join(root, "integration", "integration-1.json"), JSON.stringify({
      schema: "phase10-dotnet-test-results-v1", project: "Integration", runnerExitCode: 0, complete: true,
      startedUtc: summary.startedUtc, finishedUtc: summary.finishedUtc, assemblySha256: "b".repeat(64),
      inventorySha256: createHash("sha256").update(integrationId).digest("hex"), expectedIds: [integrationId], expectedCount: 1,
      observedCount: 1, missingCount: 0, unexpectedCount: 0, duplicateCount: 0, tests: [{ id: integrationId, status: "passed" }]
    }));
    const integrationCoverage = join(root, "integration", "coverage-1", "01234567-89ab-cdef-0123-456789abcdef");
    await mkdir(integrationCoverage, { recursive: true });
    const integrationCoveragePath = join(integrationCoverage, "coverage.cobertura.xml");
    await writeFile(integrationCoveragePath, '<coverage lines-covered="5" lines-valid="10" branches-covered="2" branches-valid="4"/>');
    await utimes(integrationCoveragePath, new Date(window.finishedUtc), new Date(window.finishedUtc));
    for (const project of FOUNDATION_TRX_PROJECTS) await writeFile(join(root, "foundations", `${project}.trx`), trxXml);
    const automationRoot = join(root, "foundations", "automation-tests");
    await mkdir(automationRoot);
    for (const suiteId of FOUNDATION_AUTOMATION_TEST_CHECKS) {
      const tests = expectedAutomationTests(suiteId).map(item => ({ id: item.id, status: "passed" }));
      await writeFile(join(automationRoot, `${suiteId}.json`), JSON.stringify({
        schema: "phase10-automation-test-results-v1", suiteId, inventorySha256: automationInventorySha256,
        runnerExitCode: 0, complete: true, expectedCount: tests.length, observedCount: tests.length,
        missingCount: 0, unexpectedCount: 0, duplicateCount: 0, tests
      }));
    }
    const dotnetRoot = join(root, "foundations", "dotnet-tests");
    await mkdir(dotnetRoot);
    for (const project of FOUNDATION_TRX_PROJECTS) {
      const id = `${project}:${createHash("sha256").update("synthetic test name").digest("hex")}`;
      await writeFile(join(dotnetRoot, `${project}.json`), JSON.stringify({
        schema: "phase10-dotnet-test-results-v1", project, runnerExitCode: 0, complete: true,
        startedUtc: window.startedUtc, finishedUtc: window.finishedUtc, assemblySha256: "a".repeat(64),
        inventorySha256: createHash("sha256").update(id).digest("hex"), expectedIds: [id], expectedCount: 1,
        observedCount: 1, missingCount: 0, unexpectedCount: 0, duplicateCount: 0, tests: [{ id, status: "passed" }]
      }));
    }
    await execFileAsync(process.execPath, ["--import", "tsx", "src/cli/render-phase10-preview.ts", root]);
    const html = await readFile(join(root, "phase10-preview.html"), "utf8");
    assert.match(html, /Foundation checks/);
    assert.match(html, /Domain-tests<\/td><td>PASS/);
    assert.match(html, /Domain<\/td><td>PASS<\/td><td>1/);
    assert.match(html, /Integration TRX<\/h2><p>Status: PASS; total: 1/);
    assert.match(html, /Integration test-process coverage<\/h2><p>Lines: 5\/10 \(50\.00%\); branches: 2\/4 \(50\.00%\)/);
    assert.match(html, /Frontend Vitest<\/h2><p>Status: PASS; total: 1/);
    assert.match(html, /Versioned automation cases: 21 expected; 21 observed/);
    assert.match(html, /Discovered \.NET cases: 6 expected; 6 observed across five foundation suites plus integration/);
    assert.match(html, /Domain foundation: showing 1 of 1 outcomes/);
    assert.match(html, /test-callbacks: showing 6 of 6 outcomes/);
    assert.match(html, /Six automation suites reconcile against a versioned expected-test inventory/);
    assert.match(html, /test-callbacks<\/td><td>PASS<\/td><td>PASS/);
    assert.match(html, /Lines: 3\/4 \(75\.00%\); branches: 1\/2 \(50\.00%\)/);
    assert.match(html, /Domain<\/td><td>3\/4 \(75\.00%\)<\/td><td>1\/2 \(50\.00%\)/);
    assert.match(html, /Overall: BLOCKED/);
    assert.equal(await readFile(join(root, "index.html"), "utf8"), html);
    const coverage = await readFile(join(root, "phase10-coverage-summary.json"), "utf8");
    assert.match(coverage, /"covered": 3/);
    assert.deepEqual((JSON.parse(coverage) as { integration: unknown }).integration,
      { state: "MEASURED", lines: { covered: 5, total: 10 }, branches: { covered: 2, total: 4 } });
    assert.doesNotMatch(coverage, /PRIVATE_MARKER|<script>|secret|coverage\.cobertura\.xml/);
    assert.doesNotMatch(html, /Synthetic\.Private\.Name/);
    assert.equal(await readFile(join(root, "foundations", "summary.json"), "utf8"), source);
    const duplicate = join(root, "foundations", "backend-coverage", "Domain", "11234567-89ab-cdef-0123-456789abcdef");
    await mkdir(duplicate);
    await writeFile(join(duplicate, "coverage.cobertura.xml"), "invalid duplicate");
    await writeFile(join(automationRoot, "unexpected.json"), "{}");
    await mkdir(join(root, "integration", "coverage-2"));
    await rm(join(root, "phase10-preview.html"));
    await rm(join(root, "index.html"));
    await rm(join(root, "phase10-coverage-summary.json"));
    await execFileAsync(process.execPath, ["--import", "tsx", "src/cli/render-phase10-preview.ts", root]);
    const duplicateHtml = await readFile(join(root, "phase10-preview.html"), "utf8");
    assert.match(duplicateHtml, /Domain<\/td><td>UNAVAILABLE<\/td><td>UNAVAILABLE/);
    assert.match(duplicateHtml, /Integration test-process coverage<\/h2><p>UNAVAILABLE/);
    assert.match(duplicateHtml, /Unexpected automation result artifact is present/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
