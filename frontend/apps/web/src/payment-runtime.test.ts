import {describe,it,expect,vi,afterEach} from "vitest";
import {createOrderProcessingApiClient} from "@xydatalabs/orderprocessing-api-sdk";
afterEach(()=>vi.restoreAllMocks());
const configuration={activeProviderType:"Razorpay",activeProviderName:"Razorpay",collectionMode:"provider_checkout",isProduction:false,isThreeDSecure:false};
const runtime={adapterMode:"sandbox",providerType:"Razorpay",collectionMode:"provider_checkout",isProduction:false,configuredThreeDs:false,supportedCurrencies:["INR"]};
describe("payment configuration uses Payments implementation evidence",()=>{
  it.each([undefined,[],["INVALID"]])("fails closed when Razorpay currency capabilities are missing or invalid (%j)",async supportedCurrencies=>{
    vi.spyOn(globalThis,"fetch").mockResolvedValueOnce(Response.json(configuration)).mockResolvedValueOnce(Response.json({success:true,data:{...runtime,supportedCurrencies}}));
    await expect(createOrderProcessingApiClient().getPaymentConfiguration()).rejects.toThrow("currency capabilities are unavailable");
  });
  it("combines matching Orders and Payments configuration",async()=>{
    vi.spyOn(globalThis,"fetch").mockResolvedValueOnce(Response.json(configuration)).mockResolvedValueOnce(Response.json({success:true,data:runtime}));
    expect(await createOrderProcessingApiClient().getPaymentConfiguration()).toMatchObject({adapterMode:"sandbox"});
  });
  it.each([{configuredThreeDs:true},{providerType:"OpenPay"},{isProduction:true},{collectionMode:"direct_card_form"}])("rejects disagreement (%j)",async change=>{
    vi.spyOn(globalThis,"fetch").mockResolvedValueOnce(Response.json(configuration)).mockResolvedValueOnce(Response.json({success:true,data:{...runtime,...change}}));
    await expect(createOrderProcessingApiClient().getPaymentConfiguration()).rejects.toThrow("disagree");
  });
  it("fails closed when runtime evidence cannot be retrieved",async()=>{
    vi.spyOn(globalThis,"fetch").mockResolvedValueOnce(Response.json(configuration)).mockResolvedValueOnce(new Response(null,{status:503}));
    await expect(createOrderProcessingApiClient().getPaymentConfiguration()).rejects.toThrow("503");
  });
  it("rejects a missing or unknown adapter mode",async()=>{
    vi.spyOn(globalThis,"fetch").mockResolvedValueOnce(Response.json(configuration)).mockResolvedValueOnce(Response.json({success:true,data:{...runtime,adapterMode:"unknown"}}));
    await expect(createOrderProcessingApiClient().getPaymentConfiguration()).rejects.toThrow("unrecognized");
  });
});
