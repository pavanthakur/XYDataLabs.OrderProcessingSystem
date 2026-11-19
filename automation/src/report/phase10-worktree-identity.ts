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
}

function sha256(value: Buffer | string): string {
  return createHash("sha256").update(value).digest("hex");
}

function git(root: string, args: string[]): string {
  return execFileSync("git", args, { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
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
