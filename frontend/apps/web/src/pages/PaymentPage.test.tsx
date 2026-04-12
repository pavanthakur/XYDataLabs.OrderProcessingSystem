import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { describe, expect, it, vi } from "vitest";
import type { OrderProcessingApiClient, PaymentResult, PaymentStatusDetails } from "@xydatalabs/orderprocessing-api-sdk";
import { PaymentCallbackPage } from "./PaymentCallbackPage";
import { PaymentPage } from "./PaymentPage";

describe("PaymentPage", () => {
  it("allows entering a two-digit expiry month without resetting to 01", async () => {
    (window as Window & { OpenPay?: unknown }).OpenPay = {
      setId: vi.fn(),
      setApiKey: vi.fn(),
      setSandboxMode: vi.fn(),
      deviceData: {
        setup: vi.fn().mockReturnValue("device-session-123")
      }
    };

    const apiClient = {
      processPayment: vi.fn(),
      getOrderById: vi.fn()
    } as unknown as OrderProcessingApiClient;

    render(
      <MemoryRouter initialEntries={["/payments/new"]}>
        <Routes>
          <Route path="/payments/new" element={<PaymentPage activeTenantCode="TenantA" apiClient={apiClient} />} />
        </Routes>
      </MemoryRouter>
    );

    const user = userEvent.setup();
    const expiryMonthInput = screen.getByLabelText("Expiry month");

    await user.type(expiryMonthInput, "12");

    expect(expiryMonthInput).toHaveValue("12");
  });

  it("routes a non-3DS payment into the shared status summary page", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(null, { status: 204 }));

    (window as Window & { OpenPay?: unknown }).OpenPay = {
      setId: vi.fn(),
      setApiKey: vi.fn(),
      setSandboxMode: vi.fn(),
      deviceData: {
        setup: vi.fn().mockReturnValue("device-session-123")
      }
    };

    const processPayment = vi.fn().mockResolvedValue({
      id: "pay-123",
      customerOrderId: "PAY-20260411-ABC123",
      customerId: "cust-123",
      amount: 100,
      currency: "MXN",
      status: "completed",
      createdAt: "2026-04-11T12:00:00Z",
      transactionId: "auth-ref-001",
      isThreeDSecureEnabled: false,
      threeDSecureStage: "not_applicable",
      threeDSecureUrl: null
    } satisfies PaymentResult);

    const confirmPaymentStatus = vi.fn().mockResolvedValue({
      paymentId: "pay-123",
      customerOrderId: "PAY-20260411-ABC123",
      status: "completed",
      statusCategory: "success",
      statusMessage: "Payment completed successfully.",
      isSuccess: true,
      isPending: false,
      isFailure: false,
      isFinal: true,
      callbackRecorded: false,
      remoteStatusConfirmed: true,
      statusSource: "openpay",
      transactionReferenceId: "auth-ref-001",
      isThreeDSecureEnabled: false,
      threeDSecureStage: "not_applicable"
    } satisfies PaymentStatusDetails);

    const apiClient = {
      processPayment,
      confirmPaymentStatus,
      getOrderById: vi.fn()
    } as unknown as OrderProcessingApiClient;

    render(
      <MemoryRouter initialEntries={["/payments/new"]}>
        <Routes>
          <Route path="/payments/new" element={<PaymentPage activeTenantCode="TenantA" apiClient={apiClient} />} />
          <Route
            path="/payments/callback"
            element={<PaymentCallbackPage activeTenantCode="TenantA" apiClient={apiClient} onTenantChange={vi.fn()} />}
          />
        </Routes>
      </MemoryRouter>
    );

    const user = userEvent.setup();

    await user.type(screen.getByLabelText("Cardholder name"), "Alice Smith");
    await user.type(screen.getByLabelText("Email"), "alice@example.com");
    await user.type(screen.getByLabelText("Card number"), "4111111111111111");
    await user.type(screen.getByLabelText("Expiry month"), "12");
    await user.type(screen.getByLabelText("Expiry year"), "26");
    await user.type(screen.getByLabelText("CVV"), "123");
    await user.click(screen.getByRole("button", { name: "Process payment" }));

    await waitFor(() => expect(processPayment).toHaveBeenCalledTimes(1));
    expect(processPayment).toHaveBeenCalledWith(expect.objectContaining({
      clientCallbackOrigin: window.location.origin
    }));
    await waitFor(() => expect(confirmPaymentStatus).toHaveBeenCalledWith(
      "pay-123",
      expect.objectContaining({
        callbackStatus: "completed"
      }),
      "TenantA"
    ));

    expect(await screen.findByText("Confirmed payment status")).toBeInTheDocument();
    expect(screen.getByText("Payment completed successfully.")).toBeInTheDocument();
    expect(screen.getByText("Provider confirmation (OpenPay)")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Start another payment" })).toHaveAttribute("href", "/payments/new");
    expect(screen.queryByText("Provider return details")).not.toBeInTheDocument();
  });

  it("shows a redirect loader before navigating to the 3D Secure challenge", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(null, { status: 204 }));

    const assignSpy = vi.spyOn(window.location, "assign").mockImplementation(() => undefined);

    (window as Window & { OpenPay?: unknown }).OpenPay = {
      setId: vi.fn(),
      setApiKey: vi.fn(),
      setSandboxMode: vi.fn(),
      deviceData: {
        setup: vi.fn().mockReturnValue("device-session-123")
      }
    };

    const processPayment = vi.fn().mockResolvedValue({
      id: "pay-3ds-123",
      customerOrderId: "PAY-20260411-3DS123",
      customerId: "cust-123",
      amount: 100,
      currency: "MXN",
      status: "charge_pending",
      createdAt: "2026-04-11T12:00:00Z",
      transactionId: "auth-ref-003",
      isThreeDSecureEnabled: true,
      threeDSecureStage: "redirect_started",
      threeDSecureUrl: "https://sandbox-api.openpay.mx/redirect"
    } satisfies PaymentResult);

    const apiClient = {
      processPayment,
      getOrderById: vi.fn()
    } as unknown as OrderProcessingApiClient;

    render(
      <MemoryRouter initialEntries={["/payments/new"]}>
        <Routes>
          <Route path="/payments/new" element={<PaymentPage activeTenantCode="TenantA" apiClient={apiClient} />} />
        </Routes>
      </MemoryRouter>
    );

    const user = userEvent.setup();

    await user.type(screen.getByLabelText("Cardholder name"), "Alice Smith");
    await user.type(screen.getByLabelText("Email"), "alice@example.com");
    await user.type(screen.getByLabelText("Card number"), "4111111111111111");
    await user.type(screen.getByLabelText("Expiry month"), "12");
    await user.type(screen.getByLabelText("Expiry year"), "26");
    await user.type(screen.getByLabelText("CVV"), "123");
    await user.click(screen.getByRole("button", { name: "Process payment" }));

    await waitFor(() => expect(processPayment).toHaveBeenCalledTimes(1));
    expect(processPayment).toHaveBeenCalledWith(expect.objectContaining({
      clientCallbackOrigin: window.location.origin
    }));

    expect(await screen.findByText("Opening the provider OTP challenge")).toBeInTheDocument();
    expect(screen.getByText(/will move to the provider challenge automatically/i)).toBeInTheDocument();
    expect(screen.queryByText("Payment result")).not.toBeInTheDocument();
    expect(assignSpy).not.toHaveBeenCalled();

    await waitFor(() => expect(assignSpy).toHaveBeenCalledWith("https://sandbox-api.openpay.mx/redirect"), {
      timeout: 4000
    });
  }, 10000);
});