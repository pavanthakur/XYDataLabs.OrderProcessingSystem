import { render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { describe, expect, it, vi } from "vitest";
import type { OrderProcessingApiClient, PaymentStatusDetails } from "@xydatalabs/orderprocessing-api-sdk";
import { PaymentCallbackPage } from "./PaymentCallbackPage";

describe("PaymentCallbackPage", () => {
  it("renders the callback summary on a fresh 3DS return before tenant bootstrap completes", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(null, { status: 204 }));

    const confirmPaymentStatus = vi.fn().mockResolvedValue({
      paymentId: "tri4sjvgkcxbnjt2heti",
      customerOrderId: "ORDER-42",
      status: "completed",
      statusCategory: "success",
      statusMessage: "Payment completed successfully.",
      isSuccess: true,
      isPending: false,
      isFailure: false,
      isFinal: true,
      callbackRecorded: true,
      remoteStatusConfirmed: true,
      statusSource: "callback",
      transactionReferenceId: "auth-ref-001",
      isThreeDSecureEnabled: true,
      threeDSecureStage: "completed"
    } satisfies PaymentStatusDetails);

    const apiClient = {
      confirmPaymentStatus
    } as unknown as OrderProcessingApiClient;

    const onTenantChange = vi.fn(() => {
      throw new Error("tenant switch should not happen before runtime bootstrap completes");
    });

    sessionStorage.setItem("pending-payment:tri4sjvgkcxbnjt2heti", JSON.stringify({
      customerOrderId: "ORDER-42",
      clientFlowId: "flow-123",
      customerId: 7,
      orderId: 42
    }));

    render(
      <MemoryRouter initialEntries={["/payments/callback?tenantCode=TenantA&id=tri4sjvgkcxbnjt2heti&status=completed"]}>
        <Routes>
          <Route
            path="/payments/callback"
            element={<PaymentCallbackPage activeTenantCode="" apiClient={apiClient} onTenantChange={onTenantChange} />}
          />
        </Routes>
      </MemoryRouter>
    );

    await waitFor(() => expect(confirmPaymentStatus).toHaveBeenCalledWith(
      "tri4sjvgkcxbnjt2heti",
      expect.objectContaining({
        callbackStatus: "completed"
      }),
      "TenantA"
    ));

    expect(onTenantChange).not.toHaveBeenCalled();
    expect(await screen.findByText("Payment completed successfully.")).toBeInTheDocument();

    const returnLinks = screen.getAllByRole("link", { name: "Return to order" });
    expect(returnLinks).toHaveLength(1);
    returnLinks.forEach((link) => {
      expect(link).toHaveAttribute("href", "/customers/7/orders/42");
    });
  });

  it("keeps the callback page in a waiting state and retries when the first reconciliation result is still pending", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(null, { status: 204 }));

    const confirmPaymentStatus = vi.fn()
      .mockResolvedValueOnce({
        paymentId: "trnyfiicdhyrhvuygchl",
        customerOrderId: "ORDER-99",
        status: "charge_pending",
        statusCategory: "pending",
        statusMessage: "Payment confirmation is still pending with the provider.",
        isSuccess: false,
        isPending: true,
        isFailure: false,
        isFinal: false,
        callbackRecorded: true,
        remoteStatusConfirmed: false,
        statusSource: "database",
        transactionReferenceId: null,
        isThreeDSecureEnabled: true,
        threeDSecureStage: "pending_confirmation"
      } satisfies PaymentStatusDetails)
      .mockResolvedValueOnce({
        paymentId: "trnyfiicdhyrhvuygchl",
        customerOrderId: "ORDER-99",
        status: "completed",
        statusCategory: "success",
        statusMessage: "Payment completed successfully.",
        isSuccess: true,
        isPending: false,
        isFailure: false,
        isFinal: true,
        callbackRecorded: true,
        remoteStatusConfirmed: true,
        statusSource: "openpay",
        transactionReferenceId: "auth-ref-002",
        isThreeDSecureEnabled: true,
        threeDSecureStage: "completed"
      } satisfies PaymentStatusDetails);

    const apiClient = {
      confirmPaymentStatus
    } as unknown as OrderProcessingApiClient;

    render(
      <MemoryRouter initialEntries={["/payments/callback?tenantCode=TenantA&id=trnyfiicdhyrhvuygchl"]}>
        <Routes>
          <Route
            path="/payments/callback"
            element={<PaymentCallbackPage activeTenantCode="TenantA" apiClient={apiClient} onTenantChange={vi.fn()} />}
          />
        </Routes>
      </MemoryRouter>
    );

    await waitFor(() => expect(confirmPaymentStatus).toHaveBeenCalledTimes(1));
    await waitFor(() => expect(screen.getByText("Waiting for the provider to finish confirmation.")).toBeInTheDocument());
    expect(screen.getByText("Retry 1 of 4 will run automatically in a moment.")).toBeInTheDocument();
    expect(screen.getByText("charge_pending")).toBeInTheDocument();

    await waitFor(() => expect(confirmPaymentStatus).toHaveBeenCalledTimes(2), { timeout: 5000 });
    await waitFor(() => expect(screen.getByText("Payment completed successfully.")).toBeInTheDocument());

    expect(screen.getByText("completed")).toBeInTheDocument();
    expect(screen.getByText("1 of 4 used")).toBeInTheDocument();
  }, 10000);
});