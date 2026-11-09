import { afterEach, describe, expect, it, vi } from "vitest";
import { clearApplicationSession, identitySession } from "./identity-session";
import { configurePublicRuntime } from "./runtime-config";

const disabled = { mode: "Disabled" as const, authority: "", clientId: "", scopes: [], apiBaseUrl: "", redirectUri: "", postLogoutRedirectUri: "" };
afterEach(() => { configurePublicRuntime(disabled); vi.restoreAllMocks(); });
describe("identity session boundaries", () => {
  it("clears only application state and not unrelated browser storage", () => {
    for (const storage of [localStorage, sessionStorage]) {
      storage.setItem("unrelated-project", "retain");
      storage.setItem("orderprocessing.accessToken", "fixture-token");
      storage.setItem("pending-payment:fixture", "private-context");
    }
    clearApplicationSession();
    for (const storage of [localStorage, sessionStorage]) {
      expect(storage.getItem("unrelated-project")).toBe("retain");
      expect(storage.getItem("orderprocessing.accessToken")).toBeNull();
      expect(storage.getItem("pending-payment:fixture")).toBeNull();
      storage.removeItem("unrelated-project");
    }
    expect(localStorage.getItem("orderprocessing.logout")).not.toBeNull();
  });
  it("rejects a Keycloak callback with invalid state before token exchange", async () => {
    configurePublicRuntime({ ...disabled, mode: "KeycloakLocal", authority: "http://localhost:8081/realms/xy-phase9", clientId: "local-web" });
    history.replaceState({}, "", "/auth/callback?code=fixture&state=wrong");
    const fetch = vi.spyOn(globalThis, "fetch");
    await expect(identitySession().bootstrap()).rejects.toThrow("OIDC callback state is invalid");
    expect(fetch).not.toHaveBeenCalled();
    history.replaceState({}, "", "/");
  });
  it("does not claim provider logout succeeded when provider discovery fails", async () => {
    configurePublicRuntime({ ...disabled, mode: "KeycloakLocal", authority: "http://localhost:8081/realms/xy-phase9", clientId: "local-web" });
    localStorage.setItem("orderprocessing.accessToken", "fixture-token");
    vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(null, { status: 503 }));
    await expect(identitySession().signOut()).rejects.toThrow("could not be confirmed");
    expect(localStorage.getItem("orderprocessing.accessToken")).toBeNull();
  });
});
