import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import App from "./App";
import * as identity from "./identity-session";

afterEach(() => {
  localStorage.clear();
  window.history.pushState({}, "", "/");
  vi.restoreAllMocks();
});

describe("App callback bootstrap", () => {
  it("restores a requested payment entry after OIDC rather than forcing Customers", async () => {
    window.history.pushState({}, "", "/auth/callback?code=fixture&state=fixture");
    vi.spyOn(identity,"identitySession").mockReturnValue({
      bootstrap: async () => { history.replaceState({},"","/payments/new?tenantCode=TenantA"); return {accessToken:null,authRedirectInitiated:false}; },
      signIn:async()=>{},signOut:async()=>{}
    });
    vi.spyOn(globalThis,"fetch").mockImplementation(async url => {
      if (String(url).includes("runtime-configuration")) return jsonResponse({activeTenantCode:"TenantA",configuredActiveTenantCode:"TenantA",tenantHeaderName:"X-Tenant-Code",availableTenants:[{tenantCode:"TenantA",tenantName:"A"}]});
      if (String(url).includes("payment-configuration")) return jsonResponse({activeProviderType:"Razorpay",activeProviderName:"Razorpay",collectionMode:"provider_checkout",browserKey:"fixture",isProduction:false});
      return new Response(null,{status:204});
    });
    render(<App />);
    expect(await screen.findByRole("heading",{name:/Collect payment|Take a card payment/i})).toBeInTheDocument();
    expect(location.pathname).toBe("/payments/new");
  });
  it("uses the signed-in tenant rather than the deployment default and hides other tenants", async () => {
    window.history.pushState({}, "", "/customers");
    vi.spyOn(globalThis,"fetch").mockImplementation(async (url, init) => {
      if (String(url).includes("runtime-configuration")) return jsonResponse({activeTenantCode:"TenantB",configuredActiveTenantCode:"TenantA",tenantHeaderName:"X-Tenant-Code",
        session:{username:"tenant-b-user",tenantCode:"TenantB",canAccessAllTenants:false},availableTenants:[{tenantCode:"TenantB",tenantName:"Tenant B"}]});
      expect(init?.headers).toMatchObject({"X-Tenant-Code":"TenantB"});
      return jsonResponse({success:true,data:[]});
    });
    render(<App />);
    expect(await screen.findByText("tenant-b-user")).toBeInTheDocument();
    expect(screen.getByRole("combobox")).toHaveValue("TenantB");
    expect(screen.getByRole("combobox")).toBeDisabled();
    expect(screen.getAllByRole("option")).toHaveLength(1);
  });

  it("rejects unauthorized deep links before fetching tenant business data", async () => {
    window.history.pushState({}, "", "/customers?tenantCode=TenantC");
    const fetch = vi.spyOn(globalThis,"fetch").mockResolvedValue(jsonResponse({activeTenantCode:"TenantB",configuredActiveTenantCode:"TenantA",tenantHeaderName:"X-Tenant-Code",
      session:{username:"tenant-b-user",tenantCode:"TenantB",canAccessAllTenants:false},availableTenants:[{tenantCode:"TenantB",tenantName:"B"}]}));
    render(<App />);
    expect(await screen.findByRole("alert")).toHaveTextContent("not authorized");
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it("does not automatically sign in again on the signed-out landing page", () => {
    window.history.pushState({}, "", "/signed-out");
    const fetch = vi.spyOn(globalThis,"fetch");
    render(<App />);
    expect(screen.getByRole("button",{name:"Sign in"})).toBeInTheDocument();
    expect(fetch).not.toHaveBeenCalled();
  });

  it("invalidates the rendered account when another tab signs out", async () => {
    window.history.pushState({}, "", "/customers");
    vi.spyOn(globalThis,"fetch").mockImplementation(async url => String(url).includes("runtime-configuration")
      ? jsonResponse({activeTenantCode:"TenantA",configuredActiveTenantCode:"TenantA",tenantHeaderName:"X-Tenant-Code",availableTenants:[{tenantCode:"TenantA",tenantName:"A"}]})
      : jsonResponse({success:true,data:[{customerId:1,name:"Private customer",email:"a@example.test",orderDtos:[]}]}));
    render(<App />);
    expect(await screen.findByText("Private customer")).toBeInTheDocument();
    window.dispatchEvent(new StorageEvent("storage",{key:"orderprocessing.logout",newValue:"fixture"}));
    expect(await screen.findByRole("button",{name:"Sign in"})).toBeInTheDocument();
    expect(screen.queryByText("Private customer")).not.toBeInTheDocument();
  });
  it("explains cross-tenant access denial without exposing previous tenant customer rows", async () => {
    window.history.pushState({}, "", "/customers");
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
      if (String(input).includes("runtime-configuration")) {
        return jsonResponse({ activeTenantCode: "TenantA", configuredActiveTenantCode: "TenantA", tenantHeaderName: "X-Tenant-Code",
          availableTenants: ["TenantA", "TenantB", "TenantC"].map((tenantCode, index) => ({ tenantId: index + 1, tenantCode, tenantName: tenantCode })) });
      }
      const tenant = (init?.headers as Record<string, string>)["X-Tenant-Code"];
      return tenant === "TenantA"
        ? jsonResponse({ success: true, data: [{ customerId: 1, name: "Private A customer", email: "a@example.test", orderDtos: [] }] })
        : new Response(JSON.stringify({ error: "The authenticated tenant claim must match X-Tenant-Code." }), { status: 403, headers: { "Content-Type": "application/json" } });
    });
    render(<App />);
    expect(await screen.findByText("Private A customer")).toBeInTheDocument();
    for (const tenant of ["TenantB", "TenantC"]) {
      fireEvent.change(screen.getByRole("combobox"), { target: { value: tenant } });
      expect(await screen.findByText(new RegExp(`Access denied for ${tenant}\\.`))).toBeInTheDocument();
      expect(screen.queryByText("Private A customer")).not.toBeInTheDocument();
      expect(screen.queryByText(/body stream already read/)).not.toBeInTheDocument();
    }
    fireEvent.change(screen.getByRole("combobox"), { target: { value: "TenantA" } });
    expect(await screen.findByText("Private A customer")).toBeInTheDocument();
  });
  it("uses the API bootstrap tenant for the standard shell even when a stale tenant is persisted", async () => {
    localStorage.setItem("orderprocessing.activeTenantCode", "TenantC");
    window.history.pushState({}, "", "/customers");

    const fetchSpy = vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
      const requestUrl = typeof input === "string" ? input : input instanceof Request ? input.url : String(input);

      if (requestUrl.includes("/api/v1/Info/runtime-configuration")) {
        expect(init?.headers).not.toMatchObject({ "X-Tenant-Code": "TenantC" });

        return jsonResponse({
          activeTenantCode: "TenantA",
          configuredActiveTenantCode: "TenantA",
          tenantHeaderName: "X-Tenant-Code",
          availableTenants: [
            { tenantId: 1, tenantCode: "TenantA", tenantName: "Tenant A" },
            { tenantId: 3, tenantCode: "TenantC", tenantName: "Tenant C" }
          ]
        });
      }

      if (requestUrl.includes("/api/v1/Customer/GetAllCustomers")) {
        expect(init?.headers).toMatchObject({ "X-Tenant-Code": "TenantA" });

        return jsonResponse({
          success: true,
          data: [
            {
              customerId: 101,
              name: "Alice Tenant A",
              email: "alice@tenant-a.local",
              orderDtos: []
            }
          ],
          message: null,
          errors: null
        });
      }

      throw new Error(`Unexpected fetch request: ${requestUrl}`);
    });

    render(<App />);

    await waitFor(() => {
      expect(screen.getByLabelText("Tenant")).toHaveValue("TenantA");
    });

    expect(await screen.findByText("Alice Tenant A")).toBeInTheDocument();
    expect(screen.getByText("Configured tenant")).toBeInTheDocument();
    expect(fetchSpy).toHaveBeenCalled();
  });

  it("boots the shell against the callback tenant and renders the payment status after a direct 3DS return on the legacy singular callback route", async () => {
    localStorage.setItem("orderprocessing.activeTenantCode", "TenantB");
    window.history.pushState({}, "", "/payment/callback?tenantCode=TenantA&id=truseqg7dswfmkp6fg1o");

    const fetchSpy = vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
      const requestUrl = typeof input === "string" ? input : input instanceof Request ? input.url : String(input);

      if (requestUrl.includes("/api/v1/Info/runtime-configuration")) {
        expect(init?.headers).not.toHaveProperty("X-Tenant-Code");

        return jsonResponse({
          activeTenantCode: "TenantA",
          configuredActiveTenantCode: "TenantA",
          tenantHeaderName: "X-Tenant-Code",
          availableTenants: [
            { tenantId: 1, tenantCode: "TenantA", tenantName: "Tenant A" },
            { tenantId: 2, tenantCode: "TenantB", tenantName: "Tenant B" }
          ]
        });
      }

      if (requestUrl.includes("/api/v1/Payments/truseqg7dswfmkp6fg1o/confirm-status")) {
        expect(init?.headers).toMatchObject({ "X-Tenant-Code": "TenantA" });

        return jsonResponse({
          success: true,
          data: {
            paymentId: "truseqg7dswfmkp6fg1o",
            customerOrderId: "OR-2-11hApr-tA-http-local-v1",
            status: "completed",
            statusCategory: "success",
            statusMessage: "Payment completed successfully and the final status was confirmed with OpenPay.",
            isSuccess: true,
            isPending: false,
            isFailure: false,
            isFinal: true,
            callbackRecorded: true,
            remoteStatusConfirmed: true,
            statusSource: "openpay",
            errorMessage: null,
            transactionReferenceId: "801585",
            transactionDate: "2026-04-11T07:33:07Z",
            threeDSecureUrl: "https://sandbox-api.openpay.mx/redirect",
            isThreeDSecureEnabled: true,
            threeDSecureStage: "completed"
          },
          message: null,
          errors: null
        });
      }

      if (requestUrl.includes("/payment/client-event")) {
        return new Response(null, { status: 204 });
      }

      throw new Error(`Unexpected fetch request: ${requestUrl}`);
    });

    render(<App />);

    expect(await screen.findByText("Payment completed successfully and the final status was confirmed with OpenPay.")).toBeInTheDocument();

    await waitFor(() => {
      expect(screen.getByLabelText("Tenant")).toHaveValue("TenantA");
    });

    expect(screen.getByText("Customers, orders, and card payments")).toBeInTheDocument();
    expect(fetchSpy).toHaveBeenCalled();
  });
});

function jsonResponse(payload: unknown): Response {
  return new Response(JSON.stringify(payload), {
    status: 200,
    headers: {
      "Content-Type": "application/json"
    }
  });
}
