import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter, Route, Routes, useLocation } from "react-router-dom";
import { describe, expect, it, vi } from "vitest";
import type { OrderProcessingApiClient } from "@xydatalabs/orderprocessing-api-sdk";
import { PaymentPage } from "./PaymentPage";
import { PaymentOrderPicker } from "./PaymentOrderPicker";

const order = { orderId:42, customerId:7, orderReferenceId:"11111111-1111-1111-1111-111111111111", totalPrice:100, currencyCode:"MXN", status:"Created", orderDate:"2026-11-09", isFulfilled:false };
const customer = {customerId:7,name:"Alice",email:"alice@example.test",orderDtos:[order]};
function Destination() {const location=useLocation();return <p>Destination: {location.pathname}{location.search}</p>;}
function mount(api: OrderProcessingApiClient) { return render(<MemoryRouter initialEntries={["/payments/new"]}><Routes>
  <Route path="/payments/new" element={<PaymentPage activeTenantCode="TenantA" apiClient={api} />} />
  <Route path="/customers/:customerId/orders/:orderId/payment" element={<Destination />} />
</Routes></MemoryRouter>); }

describe("Payments entry selects persisted orders", () => {
  it("does not render a payment form or generate an unsupported standalone reference", async () => {
    const processPayment=vi.fn();
    mount({getAllCustomers:vi.fn().mockResolvedValue([customer]),processPayment} as unknown as OrderProcessingApiClient);
    await waitFor(()=>expect(screen.getByLabelText("Customer for payment")).not.toBeDisabled());
    expect(screen.queryByLabelText("Cardholder name")).not.toBeInTheDocument();
    expect(screen.queryByRole("button",{name:"Continue to Razorpay"})).not.toBeInTheDocument();
    expect(screen.getByRole("button",{name:"Continue to payment"})).toBeDisabled();
    expect(processPayment).not.toHaveBeenCalled();
  });
  it("filters ineligible orders and navigates with the selected customer, order and tenant", async () => {
    mount({getAllCustomers:vi.fn().mockResolvedValue([{...customer,orderDtos:[order,{...order,orderId:43,status:"Paid"},{...order,orderId:44,totalPrice:0},{...order,orderId:45,orderReferenceId:""}]}])} as unknown as OrderProcessingApiClient);
    await waitFor(()=>expect(screen.getByLabelText("Customer for payment")).not.toBeDisabled());
    fireEvent.change(screen.getByLabelText("Customer for payment"),{target:{value:"7"}});
    expect(screen.getByLabelText("Order for payment").querySelectorAll("option")).toHaveLength(2);
    fireEvent.change(screen.getByLabelText("Order for payment"),{target:{value:"42"}});
    expect(screen.getByRole("status")).toHaveTextContent("100.00 MXN");
    fireEvent.click(screen.getByRole("button",{name:"Continue to payment"}));
    expect(await screen.findByText("Destination: /customers/7/orders/42/payment?tenantCode=TenantA")).toBeInTheDocument();
  });
  it("offers order creation rather than payment when the customer has no eligible orders", async () => {
    mount({getAllCustomers:vi.fn().mockResolvedValue([{...customer,orderDtos:[]}])} as unknown as OrderProcessingApiClient);
    await waitFor(()=>expect(screen.getByLabelText("Customer for payment")).not.toBeDisabled());
    fireEvent.change(screen.getByLabelText("Customer for payment"),{target:{value:"7"}});
    expect(screen.getByText(/No eligible orders/)).toBeInTheDocument();
    expect(screen.getByRole("link",{name:"Create an order"})).toHaveAttribute("href","/customers/7/orders/new");
    expect(screen.getByRole("button",{name:"Continue to payment"})).toBeDisabled();
  });
  it("reports load failure and supports retry without submitting a payment", async () => {
    const getAllCustomers=vi.fn().mockRejectedValueOnce(new Error("Directory unavailable")).mockResolvedValueOnce([]);
    mount({getAllCustomers} as unknown as OrderProcessingApiClient);
    expect(await screen.findByRole("alert")).toHaveTextContent("Directory unavailable");
    fireEvent.click(screen.getByRole("button",{name:"Reload orders"}));
    expect(await screen.findByText(/No customers are available/)).toBeInTheDocument();
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });
  it("ignores a stale directory response after switching tenants", async () => {
    let resolveOld!: (value: unknown[])=>void;
    const getAllCustomers=vi.fn().mockReturnValueOnce(new Promise(resolve=>{resolveOld=resolve;})).mockResolvedValueOnce([{...customer,customerId:8,name:"Bob",orderDtos:[]}]);
    const api={getAllCustomers} as unknown as OrderProcessingApiClient;
    const view=render(<MemoryRouter><PaymentOrderPicker activeTenantCode="TenantA" apiClient={api} /></MemoryRouter>);
    view.rerender(<MemoryRouter><PaymentOrderPicker activeTenantCode="TenantB" apiClient={api} /></MemoryRouter>);
    expect(await screen.findByRole("option",{name:/Bob/})).toBeInTheDocument();
    resolveOld([customer]);
    await waitFor(()=>expect(screen.queryByRole("option",{name:/Alice/})).not.toBeInTheDocument());
  });
});
