import { afterEach, describe, expect, it, vi } from "vitest";
import { configurePublicRuntime } from "./runtime-config";
import { identitySession } from "./identity-session";
const calls = vi.hoisted(() => ({ initialize:vi.fn(), handleRedirectPromise:vi.fn(), acquireTokenSilent:vi.fn(),
  setActiveAccount:vi.fn(), getAllAccounts:vi.fn(), getActiveAccount:vi.fn(), loginRedirect:vi.fn(), logoutRedirect:vi.fn() }));
vi.mock("@azure/msal-browser", () => ({ PublicClientApplication: class {
  initialize=calls.initialize; handleRedirectPromise=calls.handleRedirectPromise; acquireTokenSilent=calls.acquireTokenSilent;
  setActiveAccount=calls.setActiveAccount; getAllAccounts=calls.getAllAccounts; getActiveAccount=calls.getActiveAccount;
  loginRedirect=calls.loginRedirect; logoutRedirect=calls.logoutRedirect;
} }));
const config = { mode:"Entra" as const, authority:"https://login.microsoftonline.com/11111111-1111-1111-1111-111111111111/v2.0",
  clientId:"fixture-spa", scopes:["api://fixture-api/access_as_user"], apiBaseUrl:"", redirectUri:"http://localhost:3000/auth/callback", postLogoutRedirectUri:"http://localhost:3000/signed-out" };
afterEach(() => { configurePublicRuntime({...config,mode:"Disabled"}); vi.clearAllMocks(); });
describe("Entra SPA adapter (controlled fixtures, not Azure E2E)", () => {
  it("uses MSAL API scopes and does not substitute an ID token for the API token", async () => {
    configurePublicRuntime(config);
    const account = {homeAccountId:"fixture"};
    calls.handleRedirectPromise.mockResolvedValue({account});
    calls.getAllAccounts.mockReturnValue([account]);
    calls.getActiveAccount.mockReturnValue(account);
    calls.acquireTokenSilent.mockResolvedValue({accessToken:"fixture-api-token",idToken:"fixture-id-token",expiresOn:new Date(Date.now()+300000)});
    const result = await identitySession().bootstrap();
    expect(result.accessToken).toBe("fixture-api-token");
    expect(calls.acquireTokenSilent).toHaveBeenCalledWith({account,scopes:config.scopes});
  });
  it("uses provider logout and clears local application access", async () => {
    configurePublicRuntime(config);
    localStorage.setItem("orderprocessing.accessToken","fixture-token");
    await identitySession().signOut();
    expect(localStorage.getItem("orderprocessing.accessToken")).toBeNull();
    expect(calls.logoutRedirect).toHaveBeenCalledWith(expect.objectContaining({postLogoutRedirectUri:config.postLogoutRedirectUri}));
  });
  it("requests explicit account selection on sign-in", async () => {
    configurePublicRuntime(config);
    await identitySession().signIn();
    expect(calls.loginRedirect).toHaveBeenCalledWith({scopes:config.scopes,prompt:"select_account"});
  });
});
