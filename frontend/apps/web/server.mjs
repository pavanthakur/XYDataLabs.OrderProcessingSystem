import { createServer as createHttpServer } from "node:http";
import { createServer as createHttpsServer } from "node:https";
import { createReadStream, existsSync, readFileSync } from "node:fs";
import { extname, join, normalize, sep } from "node:path";
import { fileURLToPath } from "node:url";

const rootDir = fileURLToPath(new URL(".", import.meta.url));
const distDir = join(rootDir, "dist");
const host = process.env.HOST ?? "0.0.0.0";
const port = Number.parseInt(process.env.PORT ?? "5022", 10);
const useHttps = /^true$/i.test(process.env.USE_HTTPS ?? "false");
const pfxPath = process.env.PFX_PATH ?? "";
const pfxPassword = process.env.PFX_PASSWORD ?? "";

const contentTypes = new Map([
  [".css", "text/css; charset=utf-8"],
  [".gif", "image/gif"],
  [".html", "text/html; charset=utf-8"],
  [".ico", "image/x-icon"],
  [".jpg", "image/jpeg"],
  [".jpeg", "image/jpeg"],
  [".js", "application/javascript; charset=utf-8"],
  [".json", "application/json; charset=utf-8"],
  [".map", "application/json; charset=utf-8"],
  [".png", "image/png"],
  [".svg", "image/svg+xml"],
  [".txt", "text/plain; charset=utf-8"],
  [".woff", "font/woff"],
  [".woff2", "font/woff2"]
]);

function resolveRequestPath(requestUrl) {
  const candidate = new URL(requestUrl ?? "/", `http://${host}:${port}`);
  const pathname = decodeURIComponent(candidate.pathname);
  const relativePath = pathname === "/" ? "index.html" : pathname.replace(/^\/+/, "");
  const normalizedPath = normalize(relativePath);

  if (normalizedPath.startsWith(`..${sep}`) || normalizedPath === "..") {
    return null;
  }

  const absolutePath = join(distDir, normalizedPath);
  if (existsSync(absolutePath)) {
    return absolutePath;
  }

  return join(distDir, "index.html");
}

function requestHandler(request, response) {
  const filePath = resolveRequestPath(request.url);
  if (!filePath) {
    response.writeHead(400, { "Content-Type": "text/plain; charset=utf-8" });
    response.end("Bad request");
    return;
  }

  const contentType = contentTypes.get(extname(filePath).toLowerCase()) ?? "application/octet-stream";
  response.writeHead(200, { "Content-Type": contentType, "Cache-Control": "no-cache" });
  createReadStream(filePath).pipe(response);
}

const server = useHttps
  ? createHttpsServer(
      {
        pfx: readFileSync(pfxPath),
        passphrase: pfxPassword
      },
      requestHandler
    )
  : createHttpServer(requestHandler);

server.listen(port, host, () => {
  const protocol = useHttps ? "https" : "http";
  console.log(`React web server listening on ${protocol}://${host}:${port}`);
});
