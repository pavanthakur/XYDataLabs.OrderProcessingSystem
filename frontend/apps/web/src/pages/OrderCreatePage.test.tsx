import {render,screen,waitFor} from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import {MemoryRouter,Route,Routes} from "react-router-dom";
import {describe,expect,it,vi} from "vitest";
import type {OrderProcessingApiClient} from "@xydatalabs/orderprocessing-api-sdk";
import {OrderCreatePage} from "./OrderCreatePage";

describe("OrderCreatePage currency",()=>{
  it.each([
    ["TenantA","Razorpay","INR"],
    ["TenantB","Razorpay","INR"],
    ["TenantC","OpenPay","MXN"]
  ])("persists the displayed compatible currency for %s",async(tenant,provider,currency)=>{
    const createOrder=vi.fn().mockResolvedValue({orderId:77});
    const api={getAllProducts:vi.fn().mockResolvedValue([{productId:3,name:"Fixture product",price:1}]),
      getPaymentConfiguration:vi.fn().mockResolvedValue({activeProviderType:provider,supportedCurrencies:provider==="Razorpay"?["INR"]:null}),
      createOrder} as unknown as OrderProcessingApiClient;
    render(<MemoryRouter initialEntries={["/customers/7/orders/new"]}><Routes>
      <Route path="/customers/:customerId/orders/new" element={<OrderCreatePage activeTenantCode={tenant!} apiClient={api}/>}/>
      <Route path="/customers/7/orders/77" element={<p>Created order</p>}/>
    </Routes></MemoryRouter>);
    await screen.findByRole("checkbox",{name:/Fixture product/});
    expect(screen.getByLabelText("Order currency")).toHaveValue(currency);
    await userEvent.click(screen.getByRole("checkbox",{name:/Fixture product/}));
    await userEvent.click(screen.getByRole("button",{name:"Create order"}));
    await waitFor(()=>expect(createOrder).toHaveBeenCalledWith({customerId:7,productIds:[3],currencyCode:currency}));
  });
});
