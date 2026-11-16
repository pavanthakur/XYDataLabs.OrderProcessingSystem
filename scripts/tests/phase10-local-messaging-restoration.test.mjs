import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { test } from "node:test";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const script = await readFile(path.join(root, "scripts", "test-local-messaging.ps1"), "utf8");

test("messaging replay cleanup restores process environment and location even if evidence writing fails", () => {
  const finallyStart = script.indexOf("}finally{");
  assert.notEqual(finallyStart, -1);
  const cleanup = script.slice(finallyStart);
  const nestedFinally = cleanup.indexOf("}finally{");
  const environmentRestore = cleanup.indexOf("Remove-Item Env:PHASE10_NFR_SQL_CONNECTION_STRING");
  const locationRestore = cleanup.indexOf("Pop-Location");
  const reportWrite = cleanup.indexOf("Set-Content -LiteralPath (Join-Path $artifact 'replay-restoration.json')");

  assert.notEqual(nestedFinally, -1, "outer restoration must have an unconditional finally block");
  assert.ok(environmentRestore > nestedFinally, "caller environment restoration must run inside the nested finally");
  assert.ok(locationRestore > environmentRestore, "location restoration must be protected by finally");
  assert.ok(reportWrite > locationRestore, "writing the restoration report must not precede environment/location cleanup");
  assert.match(cleanup, /if\(\$reportWriteFailed\)\{throw/);
  assert.match(cleanup, /if\(-not\$replayRestored-or\$restoreCommandFailed\)\{throw/);
});

test("messaging replay restoration requires compose success, inspect success, and exact effective setting", () => {
  assert.match(script, /\$replayRestored=\$restoreExit-eq 0-and\$inspectExit-eq 0-and\$replayLine-eq"ServiceBus__ReplayEnabled=\$originalReplay"/);
  assert.match(script, /\$restoreCommandFailed=\$true/);
});

test("messaging acceptance refuses to overwrite prior proof artifacts", () => {
  const outputGuard = script.indexOf("$artifactOutputs=@('messaging-proof.json','functions-proof.json','replay-restoration.json')");
  const createDirectory = script.indexOf('[void][IO.Directory]::CreateDirectory($artifact)');
  assert.ok(outputGuard > 0 && createDirectory > outputGuard, "artifact collision guard must execute before directory use and runtime mutations");
  assert.match(script, /Messaging artifact '\$artifactName' already exists\. Select a new run-specific ArtifactDirectory; prior evidence is never overwritten/);
});
