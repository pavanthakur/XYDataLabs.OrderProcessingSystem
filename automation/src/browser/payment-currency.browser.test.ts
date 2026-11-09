import assert from "node:assert/strict";
import {execFile} from "node:child_process";
import {mkdir,readFile,writeFile} from "node:fs/promises";
import path from "node:path";
import {fileURLToPath} from "node:url";
import {promisify} from "node:util";
import test from "node:test";
import {chromium} from "playwright";

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),"../../..");
const execute=promisify(execFile);
const base="http://localhost:5022";

test("Every local tenant rejects Razorpay/MXN in UI and direct API without payment side effects",{timeout:240000},async()=>{
  const artifact=path.join(root,"TestResults/DockerStorage",`currency-rejection-browser-${Date.now()}`);
  await mkdir(artifact,{recursive:true});
  const env=await readFile(path.join(root,"Resources/Docker/.env.local"),"utf8");
  const line=env.split(/\r?\n/).find(value=>value.startsWith("KEYCLOAK_TENANT_ADMIN_PASSWORD="));
  assert.ok(line,"Private local test configuration is required.");
  const password=line.slice(line.indexOf("=")+1).trim().replace(/^["']|["']$/g,"");
  const browser=await chromium.launch({headless:true});
  const contract=JSON.parse(await readFile(path.join(root,"Resources/Configuration/tenant-bootstrap.local.json"),"utf8")) as {requiredBaselineTenants:string[]};
  const results:unknown[]=[];
  const orderCreationResults:unknown[]=[];
  let status="failed";
  const activeTenantCodes:string[]=[];
  const providerRouteByTenant=new Map<string,string>();
  try{
    const discoveryContext=await browser.newContext();
    try{
      const page=await discoveryContext.newPage();
      const authorized=page.waitForRequest(request=>new URL(request.url()).origin===base
        && request.url().includes("/api/v1/Customer/GetAllCustomers") && Boolean(request.headers().authorization));
      void authorized.catch(()=>{});
      const discoveryTenant=contract.requiredBaselineTenants[0];
      await page.goto(`${base}/customers?tenantCode=${discoveryTenant}`);
      await page.locator("#username").fill("tenant-admin");
      await page.locator("#password").fill(password);
      await page.getByRole("button",{name:/sign in/i}).click();
      const token=(await authorized).headers().authorization;
      const response=await discoveryContext.request.get(`${base}/api/v1/Info/tenant-registry`,{headers:{Authorization:token,"X-Tenant-Code":discoveryTenant}});
      assert.equal(response.status(),200);
      const registry=await response.json() as Array<{tenantCode:string;paymentProviderCode:string|null}>;
      activeTenantCodes.push(...registry.map(item=>item.tenantCode));
      for(const item of registry) providerRouteByTenant.set(item.tenantCode,item.paymentProviderCode??"");
      for(const required of contract.requiredBaselineTenants) assert.ok(activeTenantCodes.includes(required),`Required baseline tenant ${required} is not active.`);
      assert.ok(activeTenantCodes.length>0,"No active tenant was discovered.");
    }finally{await discoveryContext.close();}

    for(const tenant of activeTenantCodes){
      const manifest=path.join(artifact,`${tenant}-recovery.json`);
      const fixture=path.join(root,"scripts/local-payment-test-state.ps1");
      await execute("pwsh",["-NoProfile","-File",fixture,"-Action","Prepare","-TenantCode",tenant,
        "-ProviderType","Razorpay","-ThreeDs","false","-ManifestPath",manifest]);
      const context=await browser.newContext();
      try{
        const page=await context.newPage();
        const authenticated=page.waitForRequest(request=>new URL(request.url()).origin===base
          && request.url().includes("/api/v1/Customer/GetAllCustomers") && Boolean(request.headers().authorization));
        void authenticated.catch(()=>{});
        await page.goto(`${base}/customers?tenantCode=${tenant}`);
        await page.locator("#username").fill("tenant-admin");
        await page.locator("#password").fill(password);
        await page.getByRole("button",{name:/sign in/i}).click();
        const headers={Authorization:(await authenticated).headers().authorization,"X-Tenant-Code":tenant};
        const runtimeResponse=await context.request.get(`${base}/api/v1/Payments/runtime`,{headers});
        assert.equal(runtimeResponse.status(),200);
        const runtime=(await runtimeResponse.json()).data;
        assert.equal(runtime.adapterMode,"sandbox");
        assert.equal(runtime.providerType,"Razorpay");
        assert.deepEqual(runtime.supportedCurrencies,["INR"]);

        const productsResponse=await context.request.get(`${base}/api/v1/Product/GetAllProducts`,{headers});
        assert.equal(productsResponse.status(),200);
        const product=(await productsResponse.json()).data.find((item:{price:number})=>item.price>0);
        assert.ok(product);
        const customerResponse=await context.request.post(`${base}/api/v1/Customer`,{headers,
          data:{name:`Currency Guard ${tenant}`,email:`currency-guard-${tenant}-${Date.now()}@example.test`}});
        assert.equal(customerResponse.status(),201);
        const customerId=(await customerResponse.json()).data;
        const orderResponse=await context.request.post(`${base}/api/v1/Order`,{headers,
          data:{customerId,productIds:[product.productId],currencyCode:"MXN"}});
        assert.equal(orderResponse.status(),201);
        const order=(await orderResponse.json()).data;
        assert.equal(order.currencyCode,"MXN");
        const paymentUrl=`${base}/customers/${customerId}/orders/${order.orderId}/payment?tenantCode=${tenant}`;
        await page.goto(paymentUrl);
        await page.getByRole("alert").filter({hasText:"Order currency MXN is not supported by Razorpay"}).waitFor();
        assert.equal(await page.getByRole("button",{name:"Continue to Razorpay"}).isEnabled(),false);
        await page.screenshot({path:path.join(artifact,`${tenant}-blocked.png`),fullPage:true,mask:[page.locator("input,textarea")]});

        // Deliberately bypass the disabled UI. This must return before customer,
        // token, provider-order or charge creation; physical SQL proves no rows.
        const bypass=await context.request.post(`${base}/api/v1/Payments/ProcessPayment`,{headers,data:{
          name:"Currency Guard",email:"currency-guard@example.test",deviceSessionId:"",cardNumber:"",expirationYear:"",
          expirationMonth:"",cvv2:"",customerOrderId:`ORDER-${order.orderId}`,orderReferenceId:order.orderReferenceId,
          clientCallbackOrigin:base}});
        assert.equal(bypass.status(),400);
        const errorText=JSON.stringify(await bypass.json());
        assert.match(errorText,/MXN/);assert.match(errorText,/INR/);
        const proof=await execute("pwsh",["-NoProfile","-File",path.join(root,"scripts/verify-local-payment-state.ps1"),
          "-TenantCode",tenant,"-OrderId",String(order.orderId),"-ExpectedOutcome","currency-rejected",
          "-ExpectedAmount",String(order.totalPrice),"-ExpectedCurrency","MXN","-ExpectedReference",order.orderReferenceId]);
        await writeFile(path.join(artifact,`${tenant}-sql-proof.json`),proof.stdout);
        results.push({tenant,customerId,orderId:order.orderId,paymentUrl,amount:order.totalPrice,currency:"MXN",
          provider:"Razorpay",ui:"blocked",apiStatus:400,sql:"no attempts/transactions/payin logs; terms unchanged",status:"passed"});
      }finally{
        await context.close();
        await execute("pwsh",["-NoProfile","-File",fixture,"-Action","Restore","-ManifestPath",manifest]);
      }
    }
    // The fixtures are now restored. Exercise the real order-entry form under
    // normal A/B Razorpay and dedicated C OpenPay routing, without charging.
    for(const tenant of activeTenantCodes){
      const context=await browser.newContext();
      try{
        const page=await context.newPage();
        const authenticated=page.waitForRequest(request=>new URL(request.url()).origin===base
          && request.url().includes("/api/v1/Customer/GetAllCustomers") && Boolean(request.headers().authorization));
        void authenticated.catch(()=>{});
        await page.goto(`${base}/customers?tenantCode=${tenant}`);
        await page.locator("#username").fill("tenant-admin");
        await page.locator("#password").fill(password);
        await page.getByRole("button",{name:/sign in/i}).click();
        const headers={Authorization:(await authenticated).headers().authorization,"X-Tenant-Code":tenant};
        const customerResponse=await context.request.post(`${base}/api/v1/Customer`,{headers,
          data:{name:`Browser Currency ${tenant}`,email:`browser-currency-${tenant}-${Date.now()}@example.test`}});
        assert.equal(customerResponse.status(),201);
        const customerId=(await customerResponse.json()).data;
        await page.goto(`${base}/customers/${customerId}/orders/new?tenantCode=${tenant}`);
        const defaultProvider=providerRouteByTenant.get(tenant);
        assert.ok(defaultProvider==="Razorpay"||defaultProvider==="OpenPay",`Tenant ${tenant} has no supported configured provider.`);
        const expectedCurrency=defaultProvider==="Razorpay"?"INR":"MXN";
        const currency=page.getByLabel("Order currency");
        await currency.waitFor();
        await page.getByRole("checkbox").first().waitFor();
        assert.equal(await currency.inputValue(),expectedCurrency);
        await page.getByRole("checkbox").first().check();
        const created=page.waitForResponse(response=>new URL(response.url()).pathname==="/api/v1/Order" && response.request().method()==="POST");
        await page.getByRole("button",{name:"Create order",exact:true}).click();
        const response=await created;
        assert.equal(response.status(),201);
        assert.equal(response.request().postDataJSON().currencyCode,expectedCurrency);
        const order=(await response.json()).data;
        assert.equal(order.currencyCode,expectedCurrency);
        assert.equal(order.status,"Created");
        await page.getByRole("heading",{name:`Order #${order.orderId}`,exact:true}).waitFor();
        await page.getByText(new Intl.NumberFormat("en-US",{style:"currency",currency:expectedCurrency}).format(order.totalPrice),{exact:true}).first().waitFor();
        const paymentUrl=`${base}/customers/${customerId}/orders/${order.orderId}/payment?tenantCode=${tenant}`;
        await page.goto(paymentUrl);
        await page.getByRole("heading",{name:`Collect payment for order #${order.orderId}`}).waitFor();
        await page.getByTestId("payment-runtime-mode").filter({hasText:"Payment mode: sandbox"}).waitFor();
        assert.equal(await page.locator(".error-banner").count(),0);
        orderCreationResults.push({tenant,customerId,orderId:order.orderId,currency:expectedCurrency,paymentUrl,status:"passed",paymentStarted:false});
      }finally{await context.close();}
    }
    status="passed";
  }finally{
    await browser.close();
    await writeFile(path.join(artifact,"summary.json"),JSON.stringify({status,results,orderCreationResults},null,2));
    console.log(`Currency guard evidence: ${artifact}`);
  }
});
