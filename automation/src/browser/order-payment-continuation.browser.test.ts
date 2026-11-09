import assert from "node:assert/strict";
import {mkdir,readFile,writeFile} from "node:fs/promises";
import path from "node:path";
import {fileURLToPath} from "node:url";
import test from "node:test";
import {chromium,type BrowserContext,type Page} from "playwright";

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),"../../..");
const base="http://localhost:5022";
interface Case {tenantCode:string;orderId:number;paymentProvider:string;journeyOutcome:string}

// Explicit acceptance inputs only: this test never starts a charge or rewrites
// provider settings. Optional fixtures create unpaid local trial orders only.
test("Fresh paid/failed/cancelled order continuation and manual local fixtures",{timeout:300000},async()=>{
  const sources=process.env.PHASE10_CONTINUATION_SOURCES?.split(";").filter(Boolean);
  assert.ok(sources?.length,"Set PHASE10_CONTINUATION_SOURCES to completed acceptance summary files.");
  const artifact=path.resolve(process.env.PHASE10_CONTINUATION_ARTIFACT ?? path.join(root,"TestResults/DockerStorage",`continuation-browser-${Date.now()}`));
  assert.ok(artifact.startsWith(path.join(root,"TestResults")+path.sep),"Artifacts must remain in project TestResults.");
  await mkdir(artifact,{recursive:true});
  const env=await readFile(path.join(root,"Resources/Docker/.env.local"),"utf8");
  const passwordLine=env.split(/\r?\n/).find(line=>line.startsWith("KEYCLOAK_TENANT_ADMIN_PASSWORD="));
  assert.ok(passwordLine,"Private local test password must be configured.");
  const password=passwordLine.slice(passwordLine.indexOf("=")+1).trim().replace(/^["']|["']$/g,"");
  const contract=JSON.parse(await readFile(path.join(root,"Resources/Configuration/tenant-bootstrap.local.json"),"utf8")) as {requiredBaselineTenants:string[]};
  const cases:Case[]=[];
  for(const source of sources){
    const summary=JSON.parse(await readFile(path.resolve(source),"utf8"));
    assert.equal(summary.mode,"sandbox");
    assert.notEqual(summary.status,"running","Do not inspect cases while provider fixtures are still active.");
    for(const run of summary.results ?? [])for(const row of run.rows ?? []){
      if(["completed","expected-cancelled","expected-failure"].includes(row.journeyOutcome))cases.push(row);
    }
  }
  assert.ok(cases.length>0,"No completed/cancelled cases were supplied.");
  const browser=await chromium.launch({headless:true});
  const results:unknown[]=[];
  const manual:unknown[]=[];
  let activeTenantCodes:string[]=[];
  const baselineRouteByTenant=new Map<string,string>();
  let overall="running";
  async function session(tenant:string):Promise<{context:BrowserContext;page:Page;headers:Record<string,string>}>{
    const context=await browser.newContext();
    const page=await context.newPage();
    try{
      const authorized=page.waitForRequest(request=>new URL(request.url()).origin===base
        && request.url().includes("/api/v1/Customer/GetAllCustomers") && Boolean(request.headers().authorization),{timeout:30000});
      void authorized.catch(()=>{});
      await page.goto(`${base}/customers?tenantCode=${tenant}`);
      await page.locator("#username").fill("tenant-admin");
      await page.locator("#password").fill(password);
      await page.getByRole("button",{name:/sign in/i}).click();
      const request=await authorized;
      const headers={Authorization:request.headers().authorization,"X-Tenant-Code":tenant};
      await page.getByText("tenant-admin",{exact:true}).waitFor();
      return {context,page,headers};
    }catch(error){await context.close();throw error;}
  }
  try{
    const discovery=await session(contract.requiredBaselineTenants[0]);
    try{
      const response=await discovery.context.request.get(`${base}/api/v1/Info/tenant-registry`,{headers:discovery.headers});
      assert.equal(response.status(),200);
      const registry=await response.json() as Array<{tenantCode:string;paymentProviderCode:string|null}>;
      activeTenantCodes=registry.map(item=>item.tenantCode);
      for(const item of registry) baselineRouteByTenant.set(item.tenantCode,item.paymentProviderCode??"");
      for(const required of contract.requiredBaselineTenants) assert.ok(activeTenantCodes.includes(required),`Required baseline tenant ${required} is not active.`);
      for(const route of baselineRouteByTenant.values()) assert.ok(["Razorpay","OpenPay"].includes(route),"An active tenant has no supported provider route.");
    }finally{await discovery.context.close();}
    assert.ok(cases.length>0,"No completed/cancelled cases were supplied.");
    for(const item of cases) assert.ok(activeTenantCodes.includes(item.tenantCode),`Continuation case tenant ${item.tenantCode} is inactive or undiscovered.`);
    for(const item of cases){
      assert.ok(Number.isInteger(item.orderId) && item.orderId>0);
      const {context,page,headers}=await session(item.tenantCode);
      try{
        const response=await context.request.get(`${base}/api/v1/Order/${item.orderId}`,{headers});
        assert.equal(response.status(),200);
        const order=(await response.json()).data;
        const runtimeResponse=await context.request.get(`${base}/api/v1/Payments/runtime`,{headers});
        assert.equal(runtimeResponse.status(),200);
        const runtime=(await runtimeResponse.json()).data;
        assert.equal(runtime.adapterMode,"sandbox");
        const paid=item.journeyOutcome==="completed";
        assert.equal(order.status,paid?"Paid":"Created");
        assert.equal(order.isFulfilled,false,"Payment completion must not assert delivery.");
        const orderUrl=`${base}/customers/${order.customerId}/orders/${item.orderId}?tenantCode=${item.tenantCode}`;
        await page.goto(orderUrl);
        await page.locator("dd").filter({hasText:new RegExp(`^${order.status}$`)}).waitFor();
        const paymentUrl=orderUrl.replace("?","/payment?");
        await page.goto(paymentUrl);
        let gap:string|null=null;
        if(paid){
          await page.getByText(/Select an existing created order with a valid reference/).waitFor();
          const submit=page.locator('button[type="submit"]');
          assert.equal(await submit.isEnabled(),false,"Paid order must not offer another enabled charge.");
          await page.reload();
          await page.getByText(/Select an existing created order with a valid reference/).waitFor();
          assert.equal(await submit.isEnabled(),false);
        }else if(item.journeyOutcome==="expected-cancelled"){
          await page.getByRole("heading",{name:`Collect payment for order #${item.orderId}`}).waitFor();
          // Observe the missing recovery affordance without submitting another
          // payment. An unresolved cancellation is not proof of a failed charge.
          const recovery=page.getByRole("button",{name:/check payment|resume payment|refresh payment status/i});
          if(await recovery.count()===0)gap="No order-based Check payment status / Resume payment action.";
        }else{
          await page.getByRole("heading",{name:`Collect payment for order #${item.orderId}`}).waitFor();
          await page.waitForFunction(()=>{
            const button=document.querySelector<HTMLButtonElement>('button[type="submit"]');
            return button && !button.disabled;
          },undefined,{timeout:30000});
          assert.equal(await page.locator(".error-banner").count(),0);
        }
        await page.screenshot({path:path.join(artifact,`${item.tenantCode}-${item.orderId}-${item.journeyOutcome}.png`),
          fullPage:true,mask:[page.locator("input,textarea")]});
        results.push({...item,customerId:order.customerId,orderStatus:order.status,isFulfilled:order.isFulfilled,
          currentProvider:runtime.providerType,orderUrl,paymentUrl,status:gap?"gap-observed":"passed",gap,newChargeSubmitted:false,
          retryCaptureVerified:false});
        await writeFile(path.join(artifact,"summary.json"),JSON.stringify({status:"running",results,manual},null,2));
      }finally{await context.close();}
    }
    if(process.env.PHASE10_PREPARE_MANUAL_ORDERS==="1"){
      for(const tenant of activeTenantCodes){
        const {context,page,headers}=await session(tenant);
        try{
          const productsResponse=await context.request.get(`${base}/api/v1/Product/GetAllProducts`,{headers});
          assert.equal(productsResponse.status(),200);
          const products=(await productsResponse.json()).data;
          const product=products.find((item:{price:number})=>item.price>0);
          assert.ok(product,"A positive-valued seeded product is required.");
          const baseline=baselineRouteByTenant.get(tenant)!;
          for(const scenario of ["success","failure","cancelled","alternate-provider"]){
            const provider=scenario==="alternate-provider"?(baseline==="OpenPay"?"Razorpay":"OpenPay"):baseline;
            const threeDs=false;
            const currency=provider==="Razorpay"?"INR":"MXN";
            const name=`Manual ${tenant} ${scenario} ${Date.now()}`;
            const email=`manual-${tenant.toLowerCase()}-${scenario}-${Date.now()}@example.test`;
            const customerResponse=await context.request.post(`${base}/api/v1/Customer`,{headers,data:{name,email}});
            assert.equal(customerResponse.status(),201);
            const customerId=(await customerResponse.json()).data;
            const orderResponse=await context.request.post(`${base}/api/v1/Order`,{headers,
              data:{customerId,productIds:[product.productId],currencyCode:currency}});
            assert.equal(orderResponse.status(),201);
            const order=(await orderResponse.json()).data;
            assert.equal(order.status,"Created");
            const paymentUrl=`${base}/customers/${customerId}/orders/${order.orderId}/payment?tenantCode=${tenant}`;
            if(provider===baseline && scenario!=="openpay-no-3ds"){
              await page.goto(paymentUrl);
              await page.getByRole("heading",{name:`Collect payment for order #${order.orderId}`}).waitFor();
              await page.getByTestId("payment-runtime-mode").filter({hasText:"Payment mode: sandbox"}).waitFor();
              assert.equal(await page.locator(".error-banner").count(),0);
            }
            manual.push({tenant,scenario,provider,threeDs,currency,name,email,customerId,orderId:order.orderId,amount:order.totalPrice,paymentUrl,
              providerRouteChangeRequired:provider!==baseline,settingChangeRequired:provider!==baseline,
              negativeFixtureVerified:provider==="Razorpay",status:"unpaid-no-charge-started"});
            await writeFile(path.join(artifact,"manual-orders.json"),JSON.stringify(manual,null,2));
          }
        }finally{await context.close();}
      }
    }
    overall=results.some((row:any)=>row.status==="gap-observed")?"partial":"passed";
  }finally{
    await browser.close();
    await writeFile(path.join(artifact,"summary.json"),JSON.stringify({status:overall==="running"?"failed":overall,results,manual,
      noNewChargesSubmitted:true,fulfillment:"blocked: no ship/deliver UI/API",partPayments:"not-implemented"},null,2));
  }
  console.log(`Order continuation evidence: ${artifact}`);
});
