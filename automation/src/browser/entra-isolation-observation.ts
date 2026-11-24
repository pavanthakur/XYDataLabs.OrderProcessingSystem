export function resolveBrowserApiOrigin(uiOrigin: string, gatewayOrigin: string, configuredBase: unknown): string {
  if (typeof configuredBase !== "string") throw new Error("UI runtime API base is missing.");
  const resolved = new URL(configuredBase || "/", uiOrigin);
  if (resolved.protocol !== "https:" || resolved.username || resolved.password ||
      resolved.pathname !== "/" || resolved.search || resolved.hash ||
      ![uiOrigin, gatewayOrigin].includes(resolved.origin)) {
    throw new Error("UI runtime API base must resolve to the approved dev UI or gateway origin.");
  }
  return resolved.origin;
}

export function isCustomerListUrl(url: string, browserApiOrigin: string): boolean {
  const parsed = new URL(url);
  return parsed.origin === browserApiOrigin && parsed.pathname.toLowerCase() === "/api/v1/customer/getallcustomers";
}

export function isAppSignedOutUrl(url: URL, uiOrigin: string): boolean {
  return url.origin === uiOrigin && url.pathname === "/signed-out";
}
