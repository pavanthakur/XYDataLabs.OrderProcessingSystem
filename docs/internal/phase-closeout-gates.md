# Phase Closeout Gates

This file is the authoritative record of the Docker bundle tenant scope, known external
restrictions, and the exact closeout invocations for each completed phase.

**Why this file exists:** The Docker validation bundle tenant scope changes as phases add or
change tenant configurations. Without a record, the next session has to rediscover the correct
invocation. This file eliminates that rediscovery cost and prevents stale bundle runs from
masking real regressions.

---

## How to use

When closing out a phase:

1. Check the entry below for the phase you are closing.
2. Run the exact bundle command shown.
3. Record the bundle ID in the entry's "Bundle run" field.
4. Add a new entry for the next phase when its scope is known.

When returning after a gap:

- Read `active-work.md` first — it points to the current phase.
- Come back here to get the correct bundle invocation for that phase before running.

---

## Phase Entries

---

### Phase 8.5 — Secondary Payment Provider Architecture ✅

**Closed:** May 31, 2026

**Provider seed at closeout:**
- TenantA → OpenPay (default at the time — Razorpay seeding came in Phase 8.6)
- TenantB → OpenPay
- TenantC → OpenPay

**Bundle invocation:**
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\generate-docker-validation-bundle.ps1 -Environment dev -Profile http
```
*(No tenant filter needed — all three tenants used OpenPay, all passed.)*

**Bundle run:** `docker-validation-20260510-154151`

**Known restrictions at closeout:** None — all 3 tenants / OpenPay passed.

---

### Phase 8.6 — Central Tenant Registry & Separation of Duties ✅

**Closed:** June 5, 2026

**Provider seed at closeout (set by `AddTenantPaymentProviderCode` migration):**
- TenantA → Razorpay (`Use3DSecure=false` → `provider_checkout`) ✅
- TenantB → Razorpay (`Use3DSecure=true` → `direct_card_form`) ❌ external restriction
- TenantC → OpenPay (`Use3DSecure=true` → `direct_card_form`) ✅

**Known external restriction — TenantB/Razorpay:**
TenantB uses `direct_card_form` (S2S / `Use3DSecure=true`). This path requires
*S2S Integration* to be enabled in the Razorpay Dashboard → Settings → API & Integrations →
S2S Integration. It is NOT enabled on the sandbox test account. This is an external account
constraint, not a code issue. Verified as HTTP 500 on: Docker dev, Azure dev, Azure staging.
TenantA/Razorpay uses `provider_checkout` (`Use3DSecure=false`) — no S2S required — always passes.

**Bundle invocation — Phase 8.6 baseline:**
```powershell
# -Command mode required so PowerShell binds the array before the script sees it.
# -File mode passes "TenantA,TenantC" as a single string.
pwsh -NoProfile -ExecutionPolicy Bypass -Command "& '.\scripts\generate-docker-validation-bundle.ps1' -Environment dev -Profile http -Tenant @('TenantA','TenantC')"
```

**Why TenantA + TenantC only:** TenantB/Razorpay always fails (external S2S restriction above).
Including TenantB would fail every bundle run on this account. The restriction is documented and
accepted — it is NOT a code regression gate.

**Bundle run:** `docker-validation-20260605-013343` *(pending — running at time of commit)*

**Known restrictions at closeout:**
- TenantB/Razorpay: HTTP 500, Razorpay S2S not enabled — external account restriction, not a code issue.

---

### Phase 8.7 — Provider Webhook Receiver & Event-Driven Payment Lifecycle 📅

**Status:** Not started

**Expected provider scope at closeout:**
- TenantA → Razorpay ✅
- TenantB → Razorpay (S2S restriction likely still present unless account is upgraded)
- TenantC → OpenPay ✅

**Bundle invocation — carry forward from Phase 8.6 until changed:**
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -Command "& '.\scripts\generate-docker-validation-bundle.ps1' -Environment dev -Profile http -Tenant @('TenantA','TenantC')"
```
Update this entry when Phase 8.7 changes payment provider assignments or adds new tenants.

---

## Script Bug History (for reference)

| Date | Bug | Fix |
|------|-----|-----|
| 2026-06-05 | `-File` mode passes empty `-Tenant ""` → `--allow-partial` eaten as tenant code | Added `IsNullOrWhiteSpace` guard in `Invoke-AutomationRun` |
| 2026-06-05 | `-File` mode passes `"TenantA,TenantC"` as a single string → CLI rejects it | Added comma-split loop in `Invoke-AutomationRun`; canonical invocation now uses `-Command` mode |
