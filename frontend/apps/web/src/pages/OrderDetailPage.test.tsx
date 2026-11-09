import {render,screen} from "@testing-library/react";
import {MemoryRouter,Route,Routes} from "react-router-dom";
import {describe,expect,it,vi} from "vitest";
import type {OrderProcessingApiClient} from "@xydatalabs/orderprocessing-api-sdk";
import {OrderDetailPage} from "./OrderDetailPage";

describe("OrderDetailPage persisted currency",()=>{
  it.each(["INR","MXN",undefined])("does not substitute USD for %s",async currencyCode=>{
    const api={getOrderById:vi.fn().mockResolvedValue({orderId:42,customerId:7,totalPrice:1,currencyCode,
      status:"Created",isFulfilled:false,orderDate:"2026-11-09",orderProductDtos:[]})} as unknown as OrderProcessingApiClient;
    render(<MemoryRouter initialEntries={["/customers/7/orders/42"]}><Routes>
      <Route path="/customers/:customerId/orders/:orderId" element={<OrderDetailPage activeTenantCode="TenantA" apiClient={api}/>}/>
    </Routes></MemoryRouter>);
    const expected=currencyCode?new Intl.NumberFormat("en-US",{style:"currency",currency:currencyCode}).format(1):"1.00 (currency unavailable)";
    expect(await screen.findByText(expected)).toBeInTheDocument();
  });
});
