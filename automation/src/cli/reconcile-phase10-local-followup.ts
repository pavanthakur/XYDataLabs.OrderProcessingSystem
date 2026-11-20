import { createHash } from "node:crypto";
import { lstat, mkdir, readFile, realpath, writeFile } from "node:fs/promises";
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { phase10NfrSealMatches, verifyPhase10Completion } from "../report/phase10-completion.js";
import { phase10ImageSetsMatch, validatePhase10ImageManifest } from "../report/phase10-images.js";
import { reconcilePhase10LocalFollowup, renderPhase10LocalFollowupHtml } from "../report/phase10-local-followup.js";
import { capturePhase10CommittedSnapshotIdentity, capturePhase10WorktreeIdentity } from "../report/phase10-worktree-identity.js";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const testResultsRoot = resolve(repoRoot, "TestResults");
const maxJsonBytes = 2 * 1024 * 1024;
const loadedHashes = new Map<string, string>();

function inside(base: string, path: string): boolean {
  const rel = relative(base, path);
  return rel === "" || (rel !== ".." && !rel.startsWith(".." + sep) && !isAbsolute(rel));
}

async function safePath(path: string, directory = false): Promise<string> {
  const resolved = isAbsolute(path) ? resolve(path) : resolve(repoRoot, path);
  const real = await realpath(resolved);
  const lexicalBase = resolve(testResultsRoot);
  const base = await realpath(lexicalBase);
  if (!inside(lexicalBase, resolved)) throw new Error("Evidence paths must be under TestResults.");
  let cursor = lexicalBase;
  const relativeSegments = relative(lexicalBase, resolved).split(sep).filter(Boolean);
  for (const segment of relativeSegments) {
    cursor = join(cursor, segment);
    const part = await lstat(cursor);
    if (part.isSymbolicLink()) throw new Error("Evidence path components cannot be symlinks.");
  }
  const info = await lstat(resolved);
  if (!inside(base, real) || info.isSymbolicLink() || (directory ? !info.isDirectory() : !info.isFile())) {
    throw new Error("Evidence paths must be regular files/directories under TestResults (symlinks and escapes are rejected).");
  }
  if (!directory && info.size > maxJsonBytes) throw new Error("Evidence JSON exceeds the 2 MiB size limit.");
  return real;
}

async function json(path: string): Promise<unknown> {
  const real = await safePath(path);
  try {
    const bytes = await readFile(real);
    loadedHashes.set(real, createHash("sha256").update(bytes).digest("hex"));
    return JSON.parse(bytes.toString("utf8").replace(/^\uFEFF/, "")) as unknown;
  }
  catch (error) { if (error instanceof SyntaxError) throw new Error("Evidence JSON is malformed."); throw error; }
}

function relativeEvidence(path: string): string {
  return relative(repoRoot, path).split(sep).join("/");
}

async function evidence(id: string, path: string): Promise<{ id: string; path: string; sha256: string; realPath: string }> {
  const realPath = await safePath(path);
  const bytes = await readFile(realPath);
  const sha256 = createHash("sha256").update(bytes).digest("hex");
  if (loadedHashes.has(realPath) && loadedHashes.get(realPath) !== sha256) throw new Error("Evidence changed while it was being reconciled.");
  return { id, path: relativeEvidence(realPath), sha256, realPath };
}

async function optionalEvidence(id: string, path: string): Promise<{ id: string; path: string; sha256: string; realPath: string } | undefined> {
  const resolved = isAbsolute(path) ? resolve(path) : resolve(repoRoot, path);
  try { await lstat(resolved); } catch (error) {
    if (error && typeof error === "object" && "code" in error && error.code === "ENOENT") return undefined;
    throw error;
  }
  return evidence(id, path);
}

async function optionalJson(path: string): Promise<unknown | undefined> {
  const resolved = isAbsolute(path) ? resolve(path) : resolve(repoRoot, path);
  try { await lstat(resolved); } catch (error) {
    if (error && typeof error === "object" && "code" in error && error.code === "ENOENT") return undefined;
    throw error;
  }
  return json(path);
}

interface PaymentArtifactCollection { valid: boolean; files: Array<{ id: string; path: string }>; runRoots: string[] }

function sameImageBinaries(left: ReturnType<typeof validatePhase10ImageManifest>, right: ReturnType<typeof validatePhase10ImageManifest>): boolean {
  if (left.status !== "PASS" || right.status !== "PASS") return false;
  const rightByService = new Map(right.manifest.images.map(image => [image.service, image]));
  return left.manifest.images.length === 13 && right.manifest.images.length === 13 && left.manifest.images.every(image => {
    const other = rightByService.get(image.service);
    return !!other && image.imageId === other.imageId && image.imageReference === other.imageReference &&
      image.repositoryDigests.join("\n") === other.repositoryDigests.join("\n");
  });
}

function asRecord(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : undefined;
}

async function paymentMatrixArtifactsAreBoundToRun(paths: string[], matrices: unknown[]): Promise<PaymentArtifactCollection> {
  const files: PaymentArtifactCollection["files"] = [];
  const runRoots: string[] = [];
  if (paths.length !== 3 || matrices.length !== 3) return { valid: false, files, runRoots };
  let valid = true;
  for (let index = 0; index < paths.length; index++) {
    const summaryPath = await safePath(paths[index]);
    const runRoot = dirname(dirname(dirname(summaryPath)));
    const runRootSegments = relative(testResultsRoot, runRoot).split(sep);
    if (basename(dirname(dirname(summaryPath))).toLowerCase() !== "payments" ||
        runRootSegments[0]?.toLowerCase() !== "playwright" || runRootSegments[1]?.toLowerCase() !== "phase10-docker-http" ||
        !/^phase10-docker-http-[a-z0-9-]+$/i.test(runRootSegments[2] ?? "")) return { valid: false, files, runRoots };
    runRoots.push(runRoot);
    const summaryRelative = relative(runRoot, summaryPath).split(sep);
    if (summaryRelative[0]?.toLowerCase() !== "payments" || summaryRelative.at(-1)?.toLowerCase() !== "summary.json") return { valid: false, files, runRoots };
    const summary = asRecord(matrices[index]);
    const expectedMode = index === 0 ? "deterministic" : "sandbox";
    const expectedNegative = index === 2;
    if (!summary || summary.mode !== expectedMode || summary.negative !== expectedNegative) return { valid: false, files, runRoots };
    const groups = summary.results;
    if (!Array.isArray(groups) || groups.length === 0) return { valid: false, files, runRoots };
    const matrixRoot = dirname(summaryPath);
    for (const group of groups) {
      const entry = asRecord(group);
      if (!entry) { valid = false; continue; }
      if (typeof entry.reportDirectory !== "string") {
        const explicitCapabilityBlock = entry.status === "blocked" &&
          ((entry.provider === "Razorpay" && entry.threeDs === true) || entry.provider === "OpenPay");
        if (explicitCapabilityBlock) continue;
        valid = false;
        continue;
      }
      let reportDirectory: string;
      try { reportDirectory = await safePath(entry.reportDirectory, true); }
      catch (error) {
        if (error && typeof error === "object" && "code" in error && error.code === "ENOENT") { valid = false; continue; }
        throw error;
      }
      const artifactsRelative = relative(runRoot, reportDirectory).split(sep);
      const inMatrixRoot = relative(matrixRoot, reportDirectory);
      const runId = typeof entry.runId === "string" ? entry.runId : "";
      const rows = Array.isArray(entry.rows) ? entry.rows.map(asRecord).filter((row): row is Record<string, unknown> => !!row) : [];
      if (artifactsRelative[0]?.toLowerCase() !== "payments" || !inMatrixRoot || inMatrixRoot.startsWith("..") || isAbsolute(inMatrixRoot) ||
          !runId || basename(reportDirectory) !== runId || rows.length === 0) { valid = false; continue; }

      const artifactPaths = new Map<string, string>();
      const addArtifact = (id: string, path: string) => artifactPaths.set(id, path);
      addArtifact("summary", join(reportDirectory, "summary.json"));
      addArtifact("validated-rows", join(reportDirectory, "acceptance-validated-rows.json"));
      addArtifact("provider-dependencies", join(reportDirectory, "provider-dependencies.json"));
      const validatedRowsValue = await optionalJson(join(reportDirectory, "acceptance-validated-rows.json"));
      const validatedRows = Array.isArray(validatedRowsValue) ? validatedRowsValue.map(asRecord).filter((row): row is Record<string, unknown> => !!row) : [];
      const dependenciesValue = asRecord(await optionalJson(join(reportDirectory, "provider-dependencies.json")));
      const runSummary = asRecord(await optionalJson(join(reportDirectory, "summary.json")));
      if (!validatedRowsValue || !dependenciesValue || !runSummary) valid = false;
      const dependencyEvidence = Array.isArray(dependenciesValue?.evidence) ? dependenciesValue.evidence.filter((item): item is string => typeof item === "string").join("\n") : "";
      const mode = rows[0]?.adapterMode;
      const provider = rows[0]?.paymentProvider;
      const expectedSimulation = mode === "deterministic" ? "Simulation=True" : "Simulation=False";
      if (entry.runId !== runSummary?.runId || dependenciesValue?.mode !== mode ||
          !dependencyEvidence.includes(`Provider=${String(provider)}`) || !dependencyEvidence.includes(expectedSimulation) ||
          !dependencyEvidence.includes("Operation=create-charge")) valid = false;

      for (const [rowIndex, row] of rows.entries()) {
        const tenant = typeof row.tenantCode === "string" ? row.tenantCode : "";
        const providerCode = typeof row.paymentProvider === "string" ? row.paymentProvider.toLowerCase() : "";
        const outcome = row.journeyOutcome;
        if (!tenant || tenant !== basename(tenant) || tenant === "." || tenant === ".." ||
            !providerCode || providerCode !== basename(providerCode) || providerCode === "." || providerCode === ".." ||
            row.runId !== runId || row.adapterMode !== mode || row.paymentProvider !== provider ||
            !validatedRows.some(candidate => candidate.runId === runId && candidate.tenantCode === tenant && candidate.paymentProvider === provider &&
              candidate.orderId === row.orderId && candidate.orderReferenceId === row.orderReferenceId && candidate.journeyOutcome === outcome)) valid = false;
        const caseDirectory = join(reportDirectory, tenant, providerCode);
        const caseRelative = relative(reportDirectory, caseDirectory);
        if (!caseRelative || caseRelative.startsWith("..") || isAbsolute(caseRelative)) { valid = false; continue; }
        const ledgerPath = join(caseDirectory, "case-ledger.json");
        const ledger = asRecord(await optionalJson(ledgerPath));
        const anchors = asRecord(ledger?.anchors);
        const ledgerRow = asRecord(ledger?.row);
        const expectedSqlName = outcome === "completed" ? "positive-sql-proof.json" : "negative-sql-proof.json";
        const sqlPath = join(reportDirectory, expectedSqlName);
        const sqlProof = asRecord(await optionalJson(sqlPath));
        addArtifact(`case-${rowIndex}-ledger`, ledgerPath);
        addArtifact(`case-${rowIndex}-sql-proof`, sqlPath);
        if (!ledger || !anchors || !ledgerRow || !sqlProof || ledger.tenantCode !== tenant || ledger.provider !== provider ||
            anchors.orderId !== row.orderId || anchors.orderReferenceId !== row.orderReferenceId || anchors.amount !== row.orderAmount ||
            anchors.currency !== row.orderCurrencyCode || ledger.verification !== "passed" || ledger.restoration !== "passed" ||
            ledgerRow.tenantCode !== tenant || ledgerRow.orderId !== row.orderId || ledgerRow.orderReferenceId !== row.orderReferenceId ||
            sqlProof.tenantCode !== tenant || sqlProof.orderId !== row.orderId || sqlProof.status !== "passed") valid = false;

        if (outcome === "completed") {
          const confirmationPath = join(caseDirectory, "provider-confirmation.json");
          const confirmation = asRecord(await optionalJson(confirmationPath));
          const providerResult = asRecord(confirmation?.confirmation);
          const verificationPath = join(reportDirectory, `${tenant}-${providerCode}-verification-report.json`);
          const verification = asRecord(await optionalJson(verificationPath));
          const checks = asRecord(verification?.Checks);
          const correlation = Array.isArray(verification?.ChargeCorrelation) ? verification!.ChargeCorrelation.map(asRecord).filter((item): item is Record<string, unknown> => !!item) : [];
          const paymentId = typeof providerResult?.paymentId === "string" ? providerResult.paymentId : "";
          addArtifact(`case-${rowIndex}-provider-confirmation`, confirmationPath);
          addArtifact(`case-${rowIndex}-verification-report`, verificationPath);
          if (!confirmation || !providerResult || !verification || !checks || !correlation.length || !paymentId ||
              confirmation.tenant !== tenant || confirmation.orderId !== row.orderId || confirmation.orderReferenceId !== row.orderReferenceId ||
              confirmation.amount !== row.orderAmount || confirmation.currency !== row.orderCurrencyCode || confirmation.adapterMode !== mode ||
              providerResult.status !== "completed" || providerResult.remoteStatusConfirmed !== true || providerResult.isSuccess !== true ||
              providerResult.providerAmount !== row.orderAmount || (mode === "sandbox" && providerResult.providerCurrency !== row.orderCurrencyCode) ||
              ledger?.mutation !== "provider-confirmed" || anchors?.providerPaymentId !== paymentId ||
              !dependencyEvidence.includes(paymentId) || sqlProof?.expectedOutcome !== "success" || sqlProof.orderStatus !== "Paid" ||
              sqlProof.successfulCharges !== 1 || sqlProof.allAttempts !== 1 || sqlProof.failedAttempts !== 0 || sqlProof.allPayinLogs !== 1 ||
              Object.values(checks).some(check => asRecord(check)?.Outcome !== "PASS") ||
              !correlation.some(item => item.Tenant === tenant && item.CustomerOrderId === row.customerOrderId && item.ChargeId === paymentId &&
                item.InDb === true && item.UiCallbackLogged === true)) valid = false;
          addArtifact(`case-${rowIndex}-provider-dependencies`, join(reportDirectory, "provider-dependencies.json"));
          if (mode !== "deterministic" && !dependencyEvidence.includes("Operation=fetch-charge")) valid = false;
        } else {
          const expected = outcome === "expected-failure" ? "failure" : "cancelled";
          const expectedFailed = expected === "failure" ? 1 : 0;
          if (mode !== "sandbox" || provider !== "Razorpay" || sqlProof?.expectedOutcome !== expected || sqlProof.orderStatus !== "Created" ||
              sqlProof.successfulCharges !== 0 || sqlProof.allAttempts !== 1 || sqlProof.failedAttempts !== expectedFailed ||
              sqlProof.allPayinLogs !== 1 || ledger?.mutation !== "submission-started" || ledgerRow?.journeyOutcome !== outcome ||
              (expected === "failure" && !dependencyEvidence.includes("Operation=fetch-charge"))) valid = false;
        }
      }
      for (const [artifactId, path] of artifactPaths) {
        try { const realPath = await safePath(path); files.push({ id: `payment-${files.length}-${artifactId}`, path: realPath }); }
        catch (error) {
          if (error && typeof error === "object" && "code" in error && error.code === "ENOENT") valid = false;
          else throw error;
        }
      }
    }
  }
  return { valid, files, runRoots };
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const usage = "Usage: report:phase10-local-followup -- --e2e <run-dir> --no-payment-report <sealed-no-payment-run-dir> --foundation <summary.json> --functions <functions-proof.json> --nfr-root <selected-nfr-dir> --image-manifest <selected-nfr-after.json> --operational-root <ops-nfr-dir> --operational-image-manifest <ops-after.json> --persistence-dir <persistence-run-dir> --replay-dir <replay-evidence-dir> --replay-image-manifest <replay-after.json> [--performance-root <performance-nfr-dir>] [--deterministic-payment-summary <summary.json> --sandbox-payment-summary <summary.json> --sandbox-negative-summary <summary.json>] [--customer-directory-retry-summary <summary.json>] --out <new-TestResults-dir>";
  if (args.includes("--help") || args.includes("-h")) {
    console.log(usage);
    return;
  }
  const option = (name: string) => { const index = args.indexOf(name); return index >= 0 ? args[index + 1] : undefined; };
  const e2eArg = option("--e2e");
  const foundationArg = option("--foundation");
  const functionsArg = option("--functions");
  const nfrArg = option("--nfr-root");
  const noPaymentReportArg = option("--no-payment-report");
  const imageArg = option("--image-manifest");
  const operationalRootArg = option("--operational-root");
  const operationalImageArg = option("--operational-image-manifest");
  const persistenceRootArg = option("--persistence-dir");
  const replayRootArg = option("--replay-dir");
  const replayImageArg = option("--replay-image-manifest");
  const performanceRootArg = option("--performance-root");
  const deterministicPaymentArg = option("--deterministic-payment-summary");
  const sandboxPaymentArg = option("--sandbox-payment-summary");
  const sandboxNegativeArg = option("--sandbox-negative-summary");
  const customerRetryArg = option("--customer-directory-retry-summary");
  const outputArg = option("--out");
  const paymentArgs = [deterministicPaymentArg, sandboxPaymentArg, sandboxNegativeArg];
  if (paymentArgs.some(Boolean) && !paymentArgs.every(Boolean)) {
    throw new Error("Provide all three payment summary options together; partial matrix evidence is not accepted.");
  }
  if (!e2eArg || !foundationArg || !functionsArg || !nfrArg || !imageArg || !outputArg) {
    throw new Error(usage);
  }
  const liveSourceIdentity = capturePhase10WorktreeIdentity(repoRoot);

  const e2eRoot = await safePath(e2eArg, true);
  const functionsProofPath = await safePath(functionsArg);
  const functionsProofBoundToE2e = resolve(functionsProofPath).toLowerCase() ===
    resolve(join(e2eRoot, "messaging", "functions-proof.json")).toLowerCase();
  const nfrRoot = await safePath(nfrArg, true);
  const noPaymentRoot = noPaymentReportArg ? await safePath(noPaymentReportArg, true) : undefined;
  const operationalRoot = operationalRootArg ? await safePath(operationalRootArg, true) : nfrRoot;
  const operationalImageBeforeArg = operationalImageArg
    ? join(dirname(operationalImageArg), "docker-image-identities-before.json")
    : undefined;
  const persistenceRoot = persistenceRootArg ? await safePath(persistenceRootArg, true) : undefined;
  const replayRoot = replayRootArg ? await safePath(replayRootArg, true) : undefined;
  const performanceRoot = performanceRootArg ? await safePath(performanceRootArg, true) : undefined;
  const paymentMatrixSummaries = paymentArgs.every(Boolean) ? await Promise.all(paymentArgs.map(path => json(path!))) : undefined;
  const paymentMatrixArtifactCollection = paymentMatrixSummaries
    ? await paymentMatrixArtifactsAreBoundToRun(paymentArgs as string[], paymentMatrixSummaries)
    : { valid: false, files: [], runRoots: [] };
  const e2eFile = (name: string) => join(e2eRoot, name);
  const e2eRestorationFile = await (async () => {
    for (const name of ["restoration-contract.json", "baseline-after-payment.json"]) {
      try { await lstat(e2eFile(name)); return e2eFile(name); }
      catch (error) { if (!(error && typeof error === "object" && "code" in error && error.code === "ENOENT")) throw error; }
    }
    throw new Error("E2E restoration/configuration evidence is missing.");
  })();
  const nfrFile = (name: string) => join(nfrRoot, name);
  const operationalFile = (name: string) => join(operationalRoot, name);
  const persistenceFile = (name: string) => persistenceRoot ? join(persistenceRoot, name) : undefined;
  const replayFile = (name: string) => replayRoot ? join(replayRoot, name) : undefined;
  const performanceFile = (name: string) => performanceRoot ? join(performanceRoot, name) : undefined;
  const e2eCompletion = await verifyPhase10Completion(e2eRoot);
  const [packet, e2eSummary, e2eImageBefore, e2eImage, restorationContract, foundation, functions, nfrRaw, burst, outage, rollback, currentImage,
    paymentSettingsBefore, paymentSettingsAfter, operationsSummary, operationsImage, persistenceSummary, persistenceBefore,
    persistenceAfter, persistenceImageBefore, persistenceImageAfter, replayMessaging, replayRestoration, replayFunctions, replayImage,
    noPaymentSummary, noPaymentPacket, noPaymentCoverage, performanceSummary, performanceWarmup, performanceBurst,
    performanceImageBefore, performanceImageAfter] = await Promise.all([
    json(e2eFile("acceptance-packet.json")), json(e2eFile("run-summary.json")), json(e2eFile("docker-image-identities-before.json")), json(e2eFile("docker-image-identities-after.json")),
    json(e2eRestorationFile), json(foundationArg), json(functionsArg), json(nfrFile("summary.json")),
    optionalJson(operationalFile("operational-100-message-burst.json")), optionalJson(operationalFile("consumer-outage-drill.json")),
    optionalJson(operationalFile("rollback-evidence.json")), json(imageArg),
    optionalJson(nfrFile("payment-settings-before.json")), optionalJson(nfrFile("payment-settings-after.json")),
    optionalJson(operationalFile("summary.json")), operationalImageArg ? optionalJson(operationalImageArg) : Promise.resolve(undefined),
    persistenceFile("summary.json") ? optionalJson(persistenceFile("summary.json")!) : Promise.resolve(undefined),
    persistenceFile("before.json") ? optionalJson(persistenceFile("before.json")!) : Promise.resolve(undefined),
    persistenceFile("after.json") ? optionalJson(persistenceFile("after.json")!) : Promise.resolve(undefined),
    persistenceFile("docker-image-identities-before.json") ? optionalJson(persistenceFile("docker-image-identities-before.json")!) : Promise.resolve(undefined),
    persistenceFile("docker-image-identities-after.json") ? optionalJson(persistenceFile("docker-image-identities-after.json")!) : Promise.resolve(undefined),
    replayFile("messaging-proof.json") ? optionalJson(replayFile("messaging-proof.json")!) : Promise.resolve(undefined),
    replayFile("replay-restoration.json") ? optionalJson(replayFile("replay-restoration.json")!) : Promise.resolve(undefined),
    replayFile("functions-proof.json") ? optionalJson(replayFile("functions-proof.json")!) : Promise.resolve(undefined),
    replayImageArg ? optionalJson(replayImageArg) : Promise.resolve(undefined),
    noPaymentRoot ? optionalJson(join(noPaymentRoot, "run-summary.json")) : Promise.resolve(undefined),
    noPaymentRoot ? optionalJson(join(noPaymentRoot, "acceptance-packet.json")) : Promise.resolve(undefined),
    noPaymentRoot ? optionalJson(join(noPaymentRoot, "phase10-coverage-summary.json")) : Promise.resolve(undefined),
    performanceFile("summary.json") ? optionalJson(performanceFile("summary.json")!) : Promise.resolve(undefined),
    performanceFile("performance-probe-warmup.json") ? optionalJson(performanceFile("performance-probe-warmup.json")!) : Promise.resolve(undefined),
    performanceFile("performance-probe.json") ? optionalJson(performanceFile("performance-probe.json")!) : Promise.resolve(undefined),
    performanceRoot ? optionalJson(join(dirname(performanceRoot), "docker-image-identities-before.json")) : Promise.resolve(undefined),
    performanceRoot ? optionalJson(join(dirname(performanceRoot), "docker-image-identities-after.json")) : Promise.resolve(undefined)
  ]);
  const operationsImageBefore = operationalImageBeforeArg
    ? await optionalJson(operationalImageBeforeArg)
    : undefined;
  const verifyNfrSegment = async (root: string, before: unknown, after: unknown, files: string[]) => {
    if (basename(root) !== "nfr") return false;
    const runRoot = dirname(root);
    const seal = await optionalJson(join(runRoot, "nfr-evidence-seal.json"));
    const runId = basename(runRoot);
    return validatePhase10ImageManifest(before, runId, "before").status === "PASS" &&
      validatePhase10ImageManifest(after, runId, "after").status === "PASS" && phase10NfrSealMatches(seal, runId, [
      "docker-image-identities-before.json", "docker-image-identities-after.json", "nfr/summary.json", ...files
    ], name => loadedHashes.get(join(runRoot, name)));
  };
  const operationsSegmentSealed = await verifyNfrSegment(operationalRoot, operationsImageBefore, operationsImage,
    ["nfr/operational-100-message-burst.json", "nfr/consumer-outage-drill.json", "nfr/rollback-evidence.json"]);
  const performanceSegmentSealed = !!performanceRoot && await verifyNfrSegment(performanceRoot, performanceImageBefore, performanceImageAfter,
    ["nfr/performance-probe-warmup.json", "nfr/performance-probe.json"]);
  const currentImageCandidate = asRecord(asRecord(currentImage)?.candidate);
  const imageBaseCommit = typeof currentImageCandidate?.commit === "string" ? currentImageCandidate.commit : undefined;
  let currentSourceIdentity = liveSourceIdentity;
  if (imageBaseCommit && /^(?:[a-f0-9]{40}|[a-f0-9]{64})$/.test(imageBaseCommit)) {
    try {
      currentSourceIdentity = {
        ...liveSourceIdentity,
        committedSnapshot: capturePhase10CommittedSnapshotIdentity(repoRoot, imageBaseCommit)
      };
    } catch {
      // Missing ancestry or malformed source evidence leaves the identity gate blocked.
    }
  }
  const nfrRecord = nfrRaw !== null && typeof nfrRaw === "object" && !Array.isArray(nfrRaw) ? nfrRaw as Record<string, unknown> : {};
  const nfr = { ...nfrRecord, paymentSettingsBefore, paymentSettingsAfter };
  const paymentRunRoot = paymentMatrixArtifactCollection.runRoots[0];
  const positiveMatricesShareRun = !!paymentRunRoot && paymentMatrixArtifactCollection.runRoots[1] === paymentRunRoot;
  const allPaymentMatricesInE2e = paymentMatrixArtifactCollection.runRoots.length === 3 &&
    paymentMatrixArtifactCollection.runRoots.every(root => root === e2eRoot);
  const linkedPaymentRun = !!paymentRunRoot && positiveMatricesShareRun && paymentRunRoot !== e2eRoot;
  const paymentImagePaths = linkedPaymentRun ? {
    before: join(paymentRunRoot, "docker-image-identities-before.json"),
    afterDeterministic: join(paymentRunRoot, "docker-image-identities-after-deterministic.json"),
    afterPayments: join(paymentRunRoot, "docker-image-identities-after-payments.json")
  } : undefined;
  const paymentImageValues = paymentImagePaths ? await Promise.all([
    optionalJson(paymentImagePaths.before), optionalJson(paymentImagePaths.afterDeterministic), optionalJson(paymentImagePaths.afterPayments)
  ]) : [];
  const paymentImageBefore = paymentImageValues[0];
  const paymentImageAfterDeterministic = paymentImageValues[1];
  const paymentImageAfterPayments = paymentImageValues[2];
  const paymentImageBeforeResult = validatePhase10ImageManifest(paymentImageBefore, undefined, "before");
  const paymentImageDeterministicResult = validatePhase10ImageManifest(paymentImageAfterDeterministic, undefined, "after");
  const paymentImageAfterResult = validatePhase10ImageManifest(paymentImageAfterPayments, undefined, "after");
  const paymentImageManifestsAvailable = paymentImageBeforeResult.status === "PASS" &&
    paymentImageDeterministicResult.status === "PASS" && paymentImageAfterResult.status === "PASS";
  const paymentImageCandidateClean = paymentImageManifestsAvailable &&
    paymentImageBeforeResult.manifest.candidate.worktree === "clean" &&
    paymentImageDeterministicResult.manifest.candidate.worktree === "clean" && paymentImageAfterResult.manifest.candidate.worktree === "clean";
  const paymentImageCandidateSame = paymentImageManifestsAvailable &&
    phase10ImageSetsMatch(paymentImageBeforeResult.manifest, paymentImageDeterministicResult.manifest) &&
    phase10ImageSetsMatch(paymentImageBeforeResult.manifest, paymentImageAfterResult.manifest) &&
    paymentImageBeforeResult.manifest.runId === paymentImageDeterministicResult.manifest.runId &&
    paymentImageBeforeResult.manifest.runId === paymentImageAfterResult.manifest.runId;
  const paymentImagesMatchE2e = paymentImageManifestsAvailable && sameImageBinaries(paymentImageAfterResult, validatePhase10ImageManifest(e2eImage, undefined, "after"));
  const evidenceFiles = (await Promise.all([
    evidence("e2e-acceptance-packet", e2eFile("acceptance-packet.json")),
    evidence("e2e-run-summary", e2eFile("run-summary.json")),
    evidence("e2e-completion", e2eFile("phase10-completion.json")),
    optionalEvidence("operational-run-seal", join(dirname(operationalRoot), "nfr-evidence-seal.json")),
    performanceRoot ? optionalEvidence("performance-run-seal", join(dirname(performanceRoot), "nfr-evidence-seal.json")) : Promise.resolve(undefined),
    evidence("e2e-image-manifest-before", e2eFile("docker-image-identities-before.json")),
    evidence("e2e-image-manifest", e2eFile("docker-image-identities-after.json")),
    evidence("e2e-restoration-contract", e2eRestorationFile),
    evidence("current-foundation", foundationArg), evidence("current-functions", functionsArg),
    evidence("current-nfr-summary", nfrFile("summary.json")), evidence("current-image-manifest", imageArg),
    optionalEvidence("current-payment-settings-before", nfrFile("payment-settings-before.json")),
    optionalEvidence("current-payment-settings-after", nfrFile("payment-settings-after.json")),
    optionalEvidence("operational-nfr-summary", operationalFile("summary.json")),
    optionalEvidence("operational-burst", operationalFile("operational-100-message-burst.json")),
    optionalEvidence("operational-outage", operationalFile("consumer-outage-drill.json")),
    optionalEvidence("operational-rollback", operationalFile("rollback-evidence.json")),
    operationalImageBeforeArg ? optionalEvidence("operational-image-manifest-before", operationalImageBeforeArg) : Promise.resolve(undefined),
    operationalImageArg ? optionalEvidence("operational-image-manifest", operationalImageArg) : Promise.resolve(undefined),
    performanceRoot ? optionalEvidence("performance-nfr-summary", performanceFile("summary.json")!) : Promise.resolve(undefined),
    performanceRoot ? optionalEvidence("performance-warmup", performanceFile("performance-probe-warmup.json")!) : Promise.resolve(undefined),
    performanceRoot ? optionalEvidence("performance-burst", performanceFile("performance-probe.json")!) : Promise.resolve(undefined),
    performanceRoot ? optionalEvidence("performance-image-manifest-before", join(dirname(performanceRoot), "docker-image-identities-before.json")) : Promise.resolve(undefined),
    performanceRoot ? optionalEvidence("performance-image-manifest-after", join(dirname(performanceRoot), "docker-image-identities-after.json")) : Promise.resolve(undefined),
    ...(["summary.json", "before.json", "after.json", "docker-image-identities-before.json", "docker-image-identities-after.json"] as const)
      .map((name, index) => persistenceFile(name) ? optionalEvidence(`persistence-${index}`, persistenceFile(name)!) : Promise.resolve(undefined)),
    ...(["messaging-proof.json", "replay-restoration.json", "functions-proof.json"] as const)
      .map((name, index) => replayFile(name) ? optionalEvidence(`replay-${index}`, replayFile(name)!) : Promise.resolve(undefined)),
    replayImageArg ? optionalEvidence("replay-image-manifest", replayImageArg) : Promise.resolve(undefined),
    ...(paymentMatrixSummaries ? await Promise.all(paymentArgs.map((path, index) => evidence(["payment-deterministic-matrix", "payment-sandbox-positive-matrix", "payment-sandbox-negative-matrix"][index], path!))) : []),
    ...await Promise.all(paymentMatrixArtifactCollection.files.map(item => evidence(item.id, item.path))),
    ...(paymentImagePaths ? await Promise.all([
      optionalEvidence("payment-run-image-manifest-before", paymentImagePaths.before),
      optionalEvidence("payment-run-image-manifest-after-deterministic", paymentImagePaths.afterDeterministic),
      optionalEvidence("payment-run-image-manifest-after-payments", paymentImagePaths.afterPayments)
    ]) : []),
    customerRetryArg ? evidence("customer-directory-isolated-retry", customerRetryArg) : Promise.resolve(undefined),
    ...(noPaymentRoot ? await Promise.all(["run-summary.json", "acceptance-packet.json", "phase10-coverage-summary.json", "phase10-completion.json"]
      .map(name => optionalEvidence(`no-payment-report-${name}`, join(noPaymentRoot, name)))) : [])
  ])).filter((item): item is NonNullable<typeof item> => item !== undefined);
  const noPaymentCompletion = noPaymentRoot ? await verifyPhase10Completion(noPaymentRoot) : undefined;
  const noPaymentCompletionStatus = noPaymentCompletion?.state === "COMPLETE" ? noPaymentCompletion.status : undefined;
  const report = reconcilePhase10LocalFollowup({
    e2e: { completion: e2eCompletion.state,
      completionStatus: e2eCompletion.state === "COMPLETE" ? e2eCompletion.status : undefined,
      packet, summary: e2eSummary, imageBefore: e2eImageBefore, imageAfter: e2eImage, restorationContract },
    noPaymentReport: noPaymentRoot ? { completion: noPaymentCompletion?.state ?? "INCOMPLETE", completionStatus: noPaymentCompletionStatus,
      packet: noPaymentPacket, summary: noPaymentSummary, coverage: noPaymentCoverage } : undefined,
    current: { imageManifest: currentImage, foundation, functions, functionsProofBoundToE2e: functionsProofBoundToE2e &&
        e2eCompletion.state === "COMPLETE" && !!e2eCompletion.functionsProofSha256 &&
        e2eCompletion.functionsProofSha256 === loadedHashes.get(functionsProofPath), nfr, burst, outage, rollback,
      sourceIdentity: currentSourceIdentity,
      operational: { summary: operationsSummary, imageManifest: operationsImage, imageBeforeManifest: operationsImageBefore,
        sealed: operationsSegmentSealed && !!operationalImageArg && !!operationalImageBeforeArg &&
          await safePath(operationalImageArg) === join(dirname(operationalRoot), "docker-image-identities-after.json") &&
          await safePath(operationalImageBeforeArg) === join(dirname(operationalRoot), "docker-image-identities-before.json") },
      performance: performanceRoot ? { summary: performanceSummary, warmup: performanceWarmup, burst: performanceBurst,
        imageBeforeManifest: performanceImageBefore, imageManifest: performanceImageAfter, sealed: performanceSegmentSealed } : undefined,
      paymentMatrices: paymentMatrixSummaries ? {
        deterministic: paymentMatrixSummaries[0], sandboxPositive: paymentMatrixSummaries[1], sandboxNegative: paymentMatrixSummaries[2]
      } : undefined,
      paymentMatrixSource: {
        summariesAndArtifactsNestedInE2e: paymentMatrixSummaries !== undefined && paymentMatrixArtifactCollection.valid && allPaymentMatricesInE2e,
        caseArtifactsHashedAndCorrelated: paymentMatrixSummaries !== undefined && paymentMatrixArtifactCollection.valid,
        linkedSupplementalRun: linkedPaymentRun ? {
          artifactsHashedAndCorrelated: paymentMatrixSummaries !== undefined && paymentMatrixArtifactCollection.valid,
          cleanCandidate: paymentImageCandidateClean,
          sameCandidate: paymentImageCandidateSame,
          imagesMatchE2e: paymentImagesMatchE2e
        } : undefined
      },
      customerDirectoryRetry: customerRetryArg ? await json(customerRetryArg) : undefined,
      persistence: { summary: persistenceSummary, before: persistenceBefore, after: persistenceAfter,
        imageBefore: persistenceImageBefore, imageAfter: persistenceImageAfter },
      replay: { messaging: replayMessaging, restoration: replayRestoration, functions: replayFunctions, imageManifest: replayImage } },
    evidence: evidenceFiles.map(item => ({ id: item.id, path: item.path, sha256: item.sha256 }))
  });

  const output = isAbsolute(outputArg) ? resolve(outputArg) : resolve(repoRoot, outputArg);
  const testRootReal = await realpath(testResultsRoot);
  const phase10RootReal = await realpath(join(testResultsRoot, "Phase10"));
  const outputParent = await realpath(dirname(output));
  const outputParentInfo = await lstat(dirname(output));
  if (!inside(testRootReal, output) || !inside(phase10RootReal, output) || output === phase10RootReal ||
      !inside(phase10RootReal, outputParent) || outputParentInfo.isSymbolicLink()) {
    throw new Error("Output must be a new directory beneath TestResults/Phase10.");
  }
  await mkdir(output, { recursive: false });
  const unlinkedEvidence = new Set(["payment-deterministic-matrix", "payment-sandbox-positive-matrix", "payment-sandbox-negative-matrix", "customer-directory-isolated-retry"]);
  const links = new Map(evidenceFiles.filter(item => !unlinkedEvidence.has(item.id)).map(item => [item.id,
    relative(output, item.realPath).split(sep).map(segment => encodeURIComponent(segment)).join("/")]));
  const jsonOutput = join(output, "local-followup.json");
  const htmlOutput = join(output, "index.html");
  await writeFile(jsonOutput, JSON.stringify({ ...report, generatedUtc: new Date().toISOString() }, null, 2) + "\n", { encoding: "utf8", flag: "wx" });
  await writeFile(htmlOutput, renderPhase10LocalFollowupHtml(report, links), { encoding: "utf8", flag: "wx" });
  console.log("Local follow-up report: " + report.verdict);
  console.log("Same 13 image binaries: " + String(report.imageBinaryMatch) + "; clean candidate: " +
    (report.gates.find(item => item.id === "clean-single-source-candidate")?.status ?? "UNKNOWN"));
  console.log("JSON: " + relativeEvidence(jsonOutput));
  console.log("HTML: " + relativeEvidence(htmlOutput));
  if (report.verdict === "FAIL") process.exitCode = 1;
}

main().catch((error: unknown) => {
  console.error("Could not create Phase 10 local follow-up:", error instanceof Error ? error.message : "unknown error");
  process.exitCode = 2;
});
