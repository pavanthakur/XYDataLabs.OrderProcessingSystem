import { resolve } from "node:path";
import { verifyPhase10Completion } from "../report/phase10-completion.js";

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  if (args.length !== 1) throw new Error("Usage: npm --prefix automation run verify:phase10-completion -- <run-directory>");
  const result = await verifyPhase10Completion(resolve(args[0]));
  if (result.state === "INCOMPLETE") {
    console.error("Finalization INCOMPLETE: completion record or bound artifacts are missing or inconsistent.");
    process.exitCode = 2;
  } else {
    console.log(`Finalization COMPLETE; recorded run status: ${result.status}. This is not L5/L6 or revision acceptance.`);
    if (result.status !== "passed") process.exitCode = result.status === "failed" ? 1 : 2;
  }
}

main().catch((error: unknown) => {
  console.error("Could not verify Phase 10 completion:", error instanceof Error ? error.message : "unknown error");
  process.exitCode = 2;
});
