import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { hashAzureManifestFiles } from "./phase10-evidence-files.js";
import { PHASE10_AZURE_EVIDENCE_REQUIRED_FILES, verifyAzureEvidenceFileManifest } from "./phase10-azure-evidence.js";

test("Azure evidence reader hashes actual bounded files and leaves unsafe/missing entries unverifiable", async () => {
  const root = await mkdtemp(join(tmpdir(), "phase10-azure-evidence-"));
  try {
    const bytes = Buffer.from('{"result":"safe"}\n', "utf8");
    const digest = createHash("sha256").update(bytes).digest("hex");
    await writeFile(join(root, "source.json"), bytes);
    const contractFiles = await Promise.all(PHASE10_AZURE_EVIDENCE_REQUIRED_FILES.map(async name => {
      const content = Buffer.from(`${name}\n`, "utf8");
      await writeFile(join(root, name), content);
      return { name, sha256: createHash("sha256").update(content).digest("hex") };
    }));
    await writeFile(join(root, "evidence-manifest.json"), JSON.stringify({
      schema: "phase10-azure-evidence-manifest-v1", environment: "dev",
      files: [...contractFiles, { name: "source.json", sha256: digest }],
      gateSources: Object.fromEntries(["identity", "payments", "transport-functions", "recovery-nfr", "rollback", "restoration"]
        .map(gate => [gate, ["source.json"]]))
    }));
    const accepted = await hashAzureManifestFiles(root);
    assert.equal(accepted.files["source.json"], digest);
    assert.deepEqual(accepted.evidence["source.json"], { result: "safe" });
    assert.equal(verifyAzureEvidenceFileManifest(accepted.manifest, accepted.files).valid, true);

    await writeFile(join(root, "evidence-manifest.json"), JSON.stringify({
      schema: "phase10-azure-evidence-manifest-v1", environment: "dev",
      files: [{ name: "../outside.json", sha256: digest }, { name: "missing.json", sha256: digest }]
    }));
    const rejected = await hashAzureManifestFiles(root);
    assert.equal(rejected.files["../outside.json"], undefined);
    assert.equal(verifyAzureEvidenceFileManifest(rejected.manifest, rejected.files).valid, false);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
