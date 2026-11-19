import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { lstatSync, readFileSync, readlinkSync } from "node:fs";
import { isAbsolute, relative, resolve, sep } from "node:path";

export interface Phase10WorktreeIdentity {
  commit: string;
  worktree: "clean" | "dirty";
  dirtyStatusSha256: string | null;
  worktreeContentSha256: string | null;
  changedPaths: string[];
  committedSnapshot?: Phase10CommittedSnapshotIdentity;
}

export interface Phase10CommittedSnapshotIdentity {
  baseCommit: string;
  commit: string;
  worktreeContentSha256: string;
  changedPaths: string[];
}

function sha256(value: Buffer | string): string {
  return createHash("sha256").update(value).digest("hex");
}

function git(root: string, args: string[]): string {
  return execFileSync("git", args, { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
}

function gitBuffer(root: string, args: string[]): Buffer {
  return execFileSync("git", args, { cwd: root, encoding: null, stdio: ["ignore", "pipe", "pipe"] });
}

function lines(output: string): string[] {
  return output.replace(/\r?\n$/, "").split(/\r?\n/).filter(Boolean);
}

export function capturePhase10WorktreeIdentity(workspaceRoot: string): Phase10WorktreeIdentity {
  const root = resolve(workspaceRoot);
  const commit = git(root, ["rev-parse", "--verify", "HEAD"]).trim();
  if (!/^(?:[a-f0-9]{40}|[a-f0-9]{64})$/.test(commit)) throw new Error("Could not capture a valid Git commit identity.");

  const status = lines(git(root, ["--no-optional-locks", "status", "--porcelain=v1", "--untracked-files=normal"]));
  const dirty = status.length > 0;
  const changed = [...new Set([
    ...lines(git(root, ["diff", "--name-only", "HEAD", "--"])),
    ...lines(git(root, ["ls-files", "--others", "--exclude-standard"]))
  ])].sort();
  const entries = changed.map(path => {
    const normalized = path.replace(/\\/g, "/");
    if (normalized.startsWith("/") || normalized.split("/").some(segment => segment === ".." || segment === ".")) {
      throw new Error("Git returned an unsafe changed path during source identity capture.");
    }
    const file = resolve(root, path);
    const rel = relative(root, file);
    if (!rel || rel === ".." || rel.startsWith(`..${sep}`) || isAbsolute(rel)) {
      throw new Error("Changed worktree path escaped the repository.");
    }
    let state: "deleted" | "link" | "submodule" | "file" = "deleted";
    let contentHash: string | null = null;
    try {
      const info = lstatSync(file);
      if (info.isSymbolicLink()) {
        state = "link";
        contentHash = sha256(readlinkSync(file));
      } else if (info.isDirectory()) {
        state = "submodule";
        const submoduleHead = git(file, ["rev-parse", "--verify", "HEAD"]).trim();
        if (!/^(?:[a-f0-9]{40}|[a-f0-9]{64})$/.test(submoduleHead)) throw new Error("Changed directory is not a verifiable Git submodule.");
        contentHash = sha256(submoduleHead);
      } else {
        state = "file";
        contentHash = sha256(readFileSync(file));
      }
    } catch (error) {
      if (!(error && typeof error === "object" && "code" in error && error.code === "ENOENT")) throw error;
    }
    return { path: normalized, state, sha256: contentHash };
  });
  const worktreeContentSha256 = dirty ? sha256(JSON.stringify(entries)) : null;
  return {
    commit,
    worktree: dirty ? "dirty" : "clean",
    dirtyStatusSha256: dirty ? sha256(status.join("\n")) : null,
    worktreeContentSha256,
    changedPaths: dirty ? entries.map(entry => entry.path) : []
  };
}

/**
 * Rebuilds the canonical worktree-content fingerprint for a committed tree
 * relative to the base commit used by a previously captured dirty worktree.
 * Git's filters are applied so the bytes match the current checkout platform.
 */
export function capturePhase10CommittedSnapshotIdentity(
  workspaceRoot: string,
  baseCommit: string
): Phase10CommittedSnapshotIdentity {
  const root = resolve(workspaceRoot);
  if (!/^(?:[a-f0-9]{40}|[a-f0-9]{64})$/.test(baseCommit)) {
    throw new Error("Could not capture a committed snapshot from an invalid base commit.");
  }
  const commit = git(root, ["rev-parse", "--verify", "HEAD"]).trim();
  if (!/^(?:[a-f0-9]{40}|[a-f0-9]{64})$/.test(commit)) {
    throw new Error("Could not capture a valid Git commit identity.");
  }
  execFileSync("git", ["merge-base", "--is-ancestor", baseCommit, commit], {
    cwd: root, stdio: ["ignore", "ignore", "pipe"]
  });

  const pathBytes = gitBuffer(root, ["diff", "--name-only", "-z", baseCommit, commit, "--"]);
  const paths = pathBytes.toString("utf8").split("\0").filter(Boolean).sort();
  const entries = paths.map(path => {
    const normalized = path.replace(/\\/g, "/");
    if (normalized.startsWith("/") || normalized.split("/").some(segment => segment === ".." || segment === ".")) {
      throw new Error("Git returned an unsafe committed path during source snapshot capture.");
    }

    const treeRecord = gitBuffer(root, ["ls-tree", "-z", "--full-tree", commit, "--", path]).toString("utf8").split("\0")[0];
    let state: "deleted" | "link" | "submodule" | "file" = "deleted";
    let contentHash: string | null = null;
    if (treeRecord) {
      const tabIndex = treeRecord.indexOf("\t");
      if (tabIndex < 0 || treeRecord.slice(tabIndex + 1) !== path) {
        throw new Error("Git returned an unexpected tree entry during source snapshot capture.");
      }
      const [mode, objectType, objectId] = treeRecord.slice(0, tabIndex).split(" ");
      if (!objectId || (mode !== "160000" && objectType !== "blob") || (mode === "160000" && objectType !== "commit")) {
        throw new Error("Committed source snapshot contains an unsupported tree object.");
      }
      if (mode === "160000") {
        state = "submodule";
        contentHash = sha256(objectId);
      } else {
        const worktreeStatus = git(root, ["--no-optional-locks", "status", "--porcelain=v1", "--", path]);
        const file = resolve(root, path);
        const fileRelative = relative(root, file);
        if (!fileRelative || fileRelative === ".." || fileRelative.startsWith(`..${sep}`) || isAbsolute(fileRelative)) {
          throw new Error("Committed source snapshot path escaped the repository.");
        }
        let worktreeBytes: Buffer | undefined;
        if (!worktreeStatus) {
          try {
            const info = lstatSync(file);
            if (info.isSymbolicLink()) {
              state = "link";
              contentHash = sha256(readlinkSync(file));
            } else if (info.isDirectory()) {
              state = "submodule";
              const submoduleHead = git(file, ["rev-parse", "--verify", "HEAD"]).trim();
              if (!/^(?:[a-f0-9]{40}|[a-f0-9]{64})$/.test(submoduleHead) || submoduleHead !== objectId) {
                throw new Error("Committed submodule identity does not match the worktree.");
              }
              contentHash = sha256(submoduleHead);
            } else {
              worktreeBytes = readFileSync(file);
            }
          } catch (error) {
            if (!(error && typeof error === "object" && "code" in error && error.code === "ENOENT")) throw error;
          }
        }
        if (contentHash === null) {
          if (state === "submodule") throw new Error("Could not verify the committed submodule source snapshot.");
          state = mode === "120000" ? "link" : "file";
          const bytes = worktreeBytes ?? gitBuffer(root, ["cat-file", "blob", objectId]);
          contentHash = sha256(state === "link" ? bytes.toString("utf8") : bytes);
        }
      }
    }
    return { path: normalized, state, sha256: contentHash };
  });

  return {
    baseCommit,
    commit,
    worktreeContentSha256: sha256(JSON.stringify(entries)),
    changedPaths: entries.map(entry => entry.path)
  };
}
