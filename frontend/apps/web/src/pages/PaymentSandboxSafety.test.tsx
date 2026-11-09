import {render,screen,waitFor} from "@testing-library/react";
import {MemoryRouter,Routes,Route} from "react-router-dom";
import {describe,it,expect,vi} from "vitest";
import type {OrderProcessingApiClient} from "@xydatalabs/orderprocessing-api-sdk";
import {PaymentPage,getRazorpayConstructor} from "./PaymentPage";
import userEvent from "@testing-library/user-event";

describe("Sandbox never silently simulates localhost payments",()=>{
  it("reports checkout dismissal without claiming payment success or resubmitting",async()=>{
    vi.spyOn(globalThis,"fetch").mockResolvedValue(new Response(null,{status:204}));
    (window as Window & {Razorpay?:unknown}).Razorpay=class {
      constructor(private options:{modal:{ondismiss:()=>void}}){}
      on(){}
      open(){this.options.modal.ondismiss();}
    };
    const processPayment=vi.fn().mockResolvedValue({id:"order_fixture",customerOrderId:"ORDER-42",amount:1,currency:"INR",status:"created"});
    const api={processPayment,getOrderById:vi.fn().mockResolvedValue({orderId:42,customerId:7,orderReferenceId:"11111111-1111-1111-1111-111111111111",totalPrice:1,currencyCode:"INR",status:"Created"}),
      getPaymentConfiguration:vi.fn().mockResolvedValue({activeProviderType:"Razorpay",activeProviderName:"Razorpay",collectionMode:"provider_checkout",adapterMode:"sandbox",isProduction:false,isThreeDSecure:false,browserKey:"fixture"})} as unknown as OrderProcessingApiClient;
    render(<MemoryRouter initialEntries={["/customers/7/orders/42/payment"]}><Routes><Route path="/customers/:customerId/orders/:orderId/payment" element={<PaymentPage activeTenantCode="TenantA" apiClient={api}/>}/></Routes></MemoryRouter>);
    const user=userEvent.setup();
    await user.type(screen.getByLabelText("Cardholder name"),"Fixture Payer");
    await user.type(screen.getByLabelText("Email"),"fixture@example.test");
    await waitFor(()=>expect(screen.getByRole("button",{name:"Continue to Razorpay"})).toBeEnabled());
    await user.click(screen.getByRole("button",{name:"Continue to Razorpay"}));
    expect(await screen.findByText(/Checkout closed\. Payment has not been confirmed/)).toBeInTheDocument();
    expect(processPayment).toHaveBeenCalledTimes(1);
    expect(screen.queryByText(/Payment completed successfully/)).not.toBeInTheDocument();
  });
  it("fails if the real Razorpay script fails instead of returning a mock",async()=>{
    Object.defineProperty(window.location,"hostname",{configurable:true,value:"localhost"});
    delete (window as Window & {Razorpay?:unknown}).Razorpay;
    let script: HTMLScriptElement | undefined;
    const append=vi.spyOn(document.head,"append").mockImplementation((...nodes)=>{script=nodes[0] as HTMLScriptElement;});
    const pending = getRazorpayConstructor();
    const rejection = expect(pending).rejects.toThrow("Failed to load Razorpay checkout script");
    expect(script?.src).toBe("https://checkout.razorpay.com/v1/checkout.js");
    script!.dispatchEvent(new Event("error"));
    await rejection;
    append.mockRestore();
  });
  it.each(["sandbox","deterministic"])("uses actual OpenPay device collection in sandbox, not a localhost shortcut (%s)",async mode=>{
    vi.spyOn(globalThis,"fetch").mockResolvedValue(new Response(null,{status:204}));
    const setup=vi.fn().mockReturnValue("actual-provider-device-session");
    (window as Window & {OpenPay?:unknown}).OpenPay={setId:vi.fn(),setApiKey:vi.fn(),setSandboxMode:vi.fn(),deviceData:{setup}};
    const api={getOrderById:vi.fn().mockResolvedValue({orderId:42,customerId:7,orderReferenceId:"11111111-1111-1111-1111-111111111111",totalPrice:1,currencyCode:"MXN",status:"Created"}),
      getPaymentConfiguration:vi.fn().mockResolvedValue({activeProviderType:"OpenPay",activeProviderName:"OpenPay",collectionMode:"direct_card_form",adapterMode:mode,isProduction:false,isThreeDSecure:true,browserKey:"fixture",browserMerchantId:"fixture"})} as unknown as OrderProcessingApiClient;
    render(<MemoryRouter initialEntries={["/customers/7/orders/42/payment"]}><Routes><Route path="/customers/:customerId/orders/:orderId/payment" element={<PaymentPage activeTenantCode="TenantA" apiClient={api}/>}/></Routes></MemoryRouter>);
    await waitFor(()=>expect(screen.getByTestId("payment-runtime-mode")).toHaveTextContent(`Payment mode: ${mode}`));
    if(mode==="sandbox") expect(setup).toHaveBeenCalledWith("payment-form","deviceIdHiddenFieldName");
    else expect(setup).not.toHaveBeenCalled();
  });
});
