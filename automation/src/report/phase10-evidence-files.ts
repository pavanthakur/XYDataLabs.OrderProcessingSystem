import { createHash } from "node:crypto";
import { lstat, readFile } from "node:fs/promises";
import { join } from "node:path";

export async function hashAzureManifestFiles(root: string): Promise<{ manifest: unknown; files: Record<string, string>; evidence: Record<string, unknown> }> {
  const manifestPath = join(root, "evidence-manifest.json");
  let manifest: unknown;
  try {
    const info = await lstat(manifestPath);
    if (!info.isFile() || info.isSymbolicLink() || info.size > 2 * 1024 * 1024) return { manifest: undefined, files: {}, evidence: {} };
    manifest = JSON.parse(await readFile(manifestPath, "utf8")) as unknown;
  } catch (error) {
    if (error instanceof SyntaxError || error instanceof Error && "code" in error && error.code === "ENOENT") {
      return { manifest: undefined, files: {}, evidence: {} };
    }
    throw error;
  }
  const source = manifest !== null && typeof manifest === "object" && !Array.isArray(manifest)
    ? manifest as { files?: unknown } : undefined;
  if (!source || !Array.isArray(source.files)) return { manifest, files: {}, evidence: {} };
  const files: Record<string, string> = {};
  const evidence: Record<string, unknown> = {};
  for (const item of source.files) {
    if (item === null || typeof item !== "object" || Array.isArray(item) || typeof (item as { name?: unknown }).name !== "string") continue;
    const name = (item as { name: string }).name;
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(name) || name === ".." || !/\.(?:json|trx|xml|txt)$/i.test(name)) continue;
    const path = join(root, name);
    let info;
    try { info = await lstat(path); } catch (error) {
      if (error instanceof Error && "code" in error && error.code === "ENOENT") continue;
      throw error;
    }
    if (!info.isFile() || info.isSymbolicLink() || info.size > 2 * 1024 * 1024) continue;
    const bytes = await readFile(path);
    files[name] = createHash("sha256").update(bytes).digest("hex");
    if (/\.json$/i.test(name)) {
      try { evidence[name] = JSON.parse(bytes.toString("utf8")) as unknown; } catch { /* Invalid JSON remains absent and therefore BLOCKED. */ }
    }
  }
  return { manifest, files, evidence };
}
