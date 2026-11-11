import { writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";

export default class Phase10SanitizedReporter {
  onTestRunStart() {
    this.startTime = Date.now();
  }

  async onTestRunEnd(modules, errors, reason) {
    const output = process.env.PHASE10_FRONTEND_REPORT;
    if (!output) throw new Error("PHASE10_FRONTEND_REPORT is required.");
    if (!Number.isFinite(this.startTime)) throw new Error("Frontend test start time was not recorded.");

    const states = [];
    const tests = [];
    for (const module of modules) {
      for (const item of module.children.allTests()) {
        const state = item.result().state;
        let normalized;
        if (state === "pending") normalized = "unfinished";
        else if (item.options.mode === "todo") normalized = "todo";
        else if (state === "skipped") normalized = "pending";
        else if (state === "passed" || state === "failed") normalized = state;
        else throw new Error("Unrecognized frontend test state.");
        states.push(normalized);
        // Vitest full names are not unique when a file repeats a title. The
        // stable task ID includes the file-relative position and disambiguates
        // parameterized/duplicate-title cases without exposing test names.
        const identity = `${module.relativeModuleId}\n${item.id}\n${item.fullName}`;
        const id = createHash("sha256").update(identity, "utf8").digest("hex");
        tests.push({ id: `frontend:${id}`, status: normalized });
      }
    }

    const endTime = Date.now();
    const success = reason === "passed" && errors.length === 0 && modules.every(module => module.ok()) &&
      states.every(state => state !== "failed" && state !== "unfinished");
    const inventorySha256 = createHash("sha256").update(tests.map(test => test.id).sort().join("\n"), "utf8").digest("hex");
    const report = { schema: "phase10-vitest-sanitized-v2", startTime: this.startTime, endTime, success,
      interrupted: reason === "interrupted" || states.includes("unfinished"), states, inventorySha256, tests };
    await writeFile(output, JSON.stringify(report), { encoding: "utf8", flag: "wx" });
  }
}
