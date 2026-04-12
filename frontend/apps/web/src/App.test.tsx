import { render, screen, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import App from "./App";

afterEach(() => {
  localStorage.clear();
  window.history.pushState({}, "", "/");
  vi.restoreAllMocks();
});

describe("App callback bootstrap", () => {
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

  it("boots the shell against the callback tenant and renders the payment status after a direct 3DS return", async () => {
    localStorage.setItem("orderprocessing.activeTenantCode", "TenantB");
    window.history.pushState({}, "", "/payments/callback?tenantCode=TenantA&id=truseqg7dswfmkp6fg1o");

    const fetchSpy = vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
      const requestUrl = typeof input === "string" ? input : input instanceof Request ? input.url : String(input);

      if (requestUrl.includes("/api/v1/Info/runtime-configuration")) {
        expect(init?.headers).toMatchObject({ "X-Tenant-Code": "TenantA" });

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