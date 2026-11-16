import { open, rename } from "node:fs/promises";

export async function reserveLocalDlqApprovalEvidence(filePath, initialRecord) {
  const handle = await open(filePath, "wx");
  try {
    await handle.writeFile(`${JSON.stringify(initialRecord)}\n`, "utf8");
    await handle.sync();
  } finally { await handle.close(); }
  const journal = await open(`${filePath}.jsonl`, "wx");
  let closed = false;
  let failed = false;
  let sequence = 0;
  let tail = Promise.resolve();
  const append = (record) => {
    if (closed) return Promise.reject(new Error("Local replay evidence reservation is closed."));
    const content = `${JSON.stringify(record)}\n`;
    const task = tail.then(async () => {
      if (failed) throw new Error("Prior evidence write failed; reconcile before proceeding.");
      await journal.writeFile(content, "utf8");
      await journal.sync();
      const temporaryPath = `${filePath}.${sequence++}.tmp`;
      const summary = await open(temporaryPath, "wx");
      try { await summary.writeFile(content, "utf8"); await summary.sync(); }
      finally { await summary.close(); }
      await rename(temporaryPath, filePath);
    });
    tail = task.catch(() => { failed = true; });
    return task;
  };
  try {
    await append(initialRecord);
  } catch (error) {
    closed = true;
    await journal.close();
    throw error;
  }
  return {
    append,
    async close() {
      if (closed) return;
      closed = true;
      await tail;
      await journal.close();
    }
  };
}
