import { mkdir, open, rename, lstat, type FileHandle } from "node:fs/promises";
import path from "node:path";

export interface ReservedPhase10Report {
  update(report: unknown): Promise<void>;
  close(): Promise<void>;
}

/** Immutable ownership and checkpoints survive failure of the replaceable summary. */
export async function reservePhase10Report(filePath: string, initialReport: unknown): Promise<ReservedPhase10Report> {
  try {
    await lstat(filePath);
    throw new Error("Report already exists; reconcile existing evidence before another attempt.");
  } catch (error) {
    if (!(error instanceof Error && "code" in error && error.code === "ENOENT")) throw error;
  }
  const owner = await open(`${filePath}.owner.json`, "wx");
  try { await writeDurably(owner, { schema: "phase10-report-owner-v1", pid: process.pid, createdUtc: new Date().toISOString() }); }
  finally { await owner.close(); }
  const checkpoints = `${filePath}.checkpoints`;
  await mkdir(checkpoints);
  let sequence = 0;
  let closed = false;
  let failed = false;
  let tail: Promise<void> = Promise.resolve();
  const update = (report: unknown): Promise<void> => {
    if (closed) return Promise.reject(new Error("Report reservation is closed."));
    const content = JSON.stringify(report, null, 2);
    const task = tail.then(async () => {
      if (failed) throw new Error("Earlier checkpoint failed; reconcile evidence before proceeding.");
      const checkpoint = path.join(checkpoints, `${String(sequence++).padStart(6, "0")}.json`);
      const temp = `${checkpoint}.tmp`;
      const handle = await open(temp, "wx");
      try { await writeDurably(handle, JSON.parse(content)); }
      finally { await handle.close(); }
      await rename(temp, checkpoint);
      const summaryTemp = `${filePath}.${sequence}.tmp`;
      const summary = await open(summaryTemp, "wx");
      try { await writeDurably(summary, JSON.parse(content)); }
      finally { await summary.close(); }
      await rename(summaryTemp, filePath);
    });
    tail = task.catch(() => { failed = true; });
    return task;
  };
  await update(initialReport);
  return { update, close: async () => { closed = true; await tail; } };
}

async function writeDurably(handle: FileHandle, report: unknown): Promise<void> {
  const content = Buffer.from(`${JSON.stringify(report, null, 2)}\n`, "utf8");
  let offset = 0;
  while (offset < content.length) {
    const { bytesWritten } = await handle.write(content, offset, content.length - offset, offset);
    if (bytesWritten <= 0) throw new Error("Could not persist the Phase 10 run report.");
    offset += bytesWritten;
  }
  await handle.sync();
}
