import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { describe, expect, it, vi } from "vitest";
import type { OrderProcessingApiClient, PaymentConfiguration, PaymentResult, PaymentStatusDetails } from "@xydatalabs/orderprocessing-api-sdk";
import { PaymentCallbackPage } from "./PaymentCallbackPage";
import { PaymentPage } from "./PaymentPage";

const openPayConfiguration = {
  activeProviderType: "OpenPay",
  activeProviderName: "OpenPay",
  collectionMode: "direct_card_form",
  browserKey: "pk_test_openpay_browser_key",
  browserMerchantId: "mt_test_openpay_merchant",
  isProduction: false
} satisfies PaymentConfiguration;

describe("PaymentPage", () => {
  function useNonLocalHostname(): void {
    Object.defineProperty(window.location, "hostname", {
      configurable: true,
      value: "app.example.test"
    });
  }

  it("allows entering a two-digit expiry month without resetting to 01", async () => {
    useNonLocalHostname();
    (window as Window & { OpenPay?: unknown }).OpenPay = {
      setId: vi.fn(),
      setApiKey: vi.fn(),
      setSandboxMode: vi.fn(),
      deviceData: {
        setup: vi.fn().mockReturnValue("device-session-123")
      }
    };

    const apiClient = {
      getPaymentConfiguration: vi.fn().mockResolvedValue(openPayConfiguration),
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
    useNonLocalHostname();
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
      getPaymentConfiguration: vi.fn().mockResolvedValue(openPayConfiguration),
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
    useNonLocalHostname();
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
      getPaymentConfiguration: vi.fn().mockResolvedValue(openPayConfiguration),
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

  it("launches Razorpay checkout and routes the success callback into the shared status page", async () => {
    useNonLocalHostname();
    vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(null, { status: 204 }));

    const razorpayOpen = vi.fn();
    const Razorpay = vi.fn().mockImplementation(function (this: {
      on: (eventName: string, handler: (response: unknown) => void) => void;
      open: () => void;
    }, options: {
      handler?: (response: { razorpay_payment_id: string; razorpay_order_id: string; razorpay_signature: string }) => void;
    }) {
      this.on = vi.fn();
      this.open = () => {
        razorpayOpen();
        options.handler?.({
          razorpay_payment_id: "pay_rzp_123",
          razorpay_order_id: "order_rzp_123",
          razorpay_signature: "sig_rzp_123"
        });
      };
    });

    (window as Window & { Razorpay?: unknown }).Razorpay = Razorpay as unknown;

    const processPayment = vi.fn().mockResolvedValue({
      id: "order_rzp_123",
      customerOrderId: "PAY-20260411-RZP123",
      customerId: "cust-123",
      amount: 100,
      currency: "INR",
      status: "created",
      createdAt: "2026-04-11T12:00:00Z",
      transactionId: null,
      isThreeDSecureEnabled: false,
      threeDSecureStage: null,
      threeDSecureUrl: null
    } satisfies PaymentResult);

    const confirmPaymentStatus = vi.fn().mockResolvedValue({
      paymentId: "pay_rzp_123",
      customerOrderId: "PAY-20260411-RZP123",
      status: "completed",
      statusCategory: "success",
      statusMessage: "Payment completed successfully.",
      isSuccess: true,
      isPending: false,
      isFailure: false,
      isFinal: true,
      callbackRecorded: true,
      remoteStatusConfirmed: true,
      statusSource: "razorpay",
      transactionReferenceId: "pay_rzp_123",
      isThreeDSecureEnabled: false,
      threeDSecureStage: "not_applicable"
    } satisfies PaymentStatusDetails);

    const apiClient = {
      getPaymentConfiguration: vi.fn().mockResolvedValue({
        activeProviderType: "Razorpay",
        activeProviderName: "Razorpay",
        collectionMode: "provider_checkout",
        browserKey: "rzp_test_browser_key",
        browserMerchantId: null,
        isProduction: false
      } satisfies PaymentConfiguration),
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

    expect(await screen.findByText("Razorpay payment information")).toBeInTheDocument();
    expect(screen.queryByLabelText("Card number")).not.toBeInTheDocument();

    await user.type(screen.getByLabelText("Cardholder name"), "Alice Smith");
    await user.type(screen.getByLabelText("Email"), "alice@example.com");
    await user.click(screen.getByRole("button", { name: "Continue to Razorpay" }));

    await waitFor(() => expect(processPayment).toHaveBeenCalledTimes(1));
    expect(processPayment).toHaveBeenCalledWith(expect.objectContaining({
      deviceSessionId: "",
      cardNumber: "",
      expirationYear: "",
      expirationMonth: "",
      cvv2: ""
    }));
    await waitFor(() => expect(razorpayOpen).toHaveBeenCalledTimes(1));
    await waitFor(() => expect(confirmPaymentStatus).toHaveBeenCalledWith(
      "pay_rzp_123",
      expect.objectContaining({
        attemptOrderId: "order_rzp_123"
      }),
      "TenantA"
    ));

    expect(await screen.findByText("Provider confirmation (Razorpay)")).toBeInTheDocument();
  });
});
